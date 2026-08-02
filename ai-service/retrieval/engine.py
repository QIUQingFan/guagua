"""
多通道并行检索引擎
"""
from __future__ import annotations

import json
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, List, Optional

from retrieval.channel import (
    HotProductChannel,
    KeywordSearchChannel,
    RetrievedChunk,
    SearchChannel,
    SearchChannelResult,
    SearchChannelType,
    SearchContext,
    VectorSearchChannel,
)
from retrieval.fusion import dedup_chunks, fuse_by_rrf, truncate_for_rerank
from retrieval.vector_store import ChromaVectorStore

logger = logging.getLogger("retrieval")


class RetrievalBudget:
    """检索漏斗预算"""

    def __init__(self, recall_budget: int, rerank_candidate_limit: int, default_top_k: int):
        self.recall_budget = recall_budget
        self.rerank_candidate_limit = rerank_candidate_limit
        self.default_top_k = default_top_k
        self._validate_invariants()

    def _validate_invariants(self):
        errors = []
        if self.recall_budget < self.default_top_k:
            errors.append(
                f"recall_budget({self.recall_budget}) 必须 ≥ default_top_k({self.default_top_k})"
            )
        if self.rerank_candidate_limit < self.default_top_k:
            errors.append(
                f"rerank_candidate_limit({self.rerank_candidate_limit}) 必须 ≥ default_top_k({self.default_top_k})"
            )
        if errors:
            raise ValueError("检索漏斗配置校验失败：\n  - " + "\n  - ".join(errors))


class MultiChannelRetrievalEngine:
    """多通道并行检索引擎"""

    def __init__(
        self,
        channels: List[SearchChannel],
        budget: RetrievalBudget,
        rrf_k: int = 20,
        channel_weights: Optional[Dict[str, float]] = None,
        max_workers: int = 4,
    ):
        self._channels = channels
        self._budget = budget
        self._rrf_k = rrf_k
        self._channel_weights = channel_weights or {
            "vector": 1.0, "keyword": 1.0, "hot": 0.5,
        }
        self._executor = ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="retrieval")

    def search(self, query: str, top_k: Optional[int] = None) -> List[RetrievedChunk]:
        """
        执行多路并行检索 + RRF 融合，返回最终 top_k 个 chunk。
        单通道异常被捕获并跳过，不影响主链。
        """
        final_top_k = top_k or self._budget.default_top_k
        context = SearchContext(
            query=query,
            recall_budget=self._budget.recall_budget,
            top_k=final_top_k,
        )

        enabled = [ch for ch in self._channels if ch.is_enabled(context)]
        future_to_channel = {
            self._executor.submit(self._safe_search, ch, context): ch
            for ch in enabled
        }
        channel_results: List[SearchChannelResult] = []
        for future in as_completed(future_to_channel):
            ch = future_to_channel[future]
            try:
                result = future.result()
                if result and result.chunks:
                    channel_results.append(result)
            except Exception as exc:
                logger.warning("检索通道 %s 异常，已跳过: %s", ch.get_name(), exc)

        if not channel_results:
            logger.info("多路检索无召回结果，query=%s", query[:50])
            return []

        precision_results = [
            r for r in channel_results
            if r.channel_type != SearchChannelType.HOT
        ]
        hot_results = [
            r for r in channel_results
            if r.channel_type == SearchChannelType.HOT
        ]

        precision_pool: List[RetrievedChunk] = []
        for r in precision_results:
            precision_pool.extend(r.chunks)
        if not precision_pool:
            logger.info(
                "相关性守卫：向量/关键词均无有效召回（低于相似度阈值或被关键词过滤），"
                "仅热销通道有结果，判定为不相关，返回空列表。query=%s",
                query[:50],
            )
            return []

        deduped = dedup_chunks(precision_pool)
        if len(precision_results) > 1:
            fused = fuse_by_rrf(precision_results, deduped, k=self._rrf_k, weights=self._channel_weights)
        else:
            fused = deduped

        top_source_type = fused[0].source_type if fused else "unknown"
        is_product_context = top_source_type in ("product", "hot")
        if hot_results and is_product_context and len(fused) < final_top_k:
            known = {c.key() for c in fused}
            fill = [
                c for r in hot_results for c in r.chunks
                if c.key() not in known
            ]
            if fill:
                fill = fill[: final_top_k - len(fused)]
                logger.info(
                    "热销兜底填充：头部来源=%s，精准%d条不足top_k=%d，补齐%d条热销商品。query=%s",
                    top_source_type, len(fused), final_top_k, len(fill), query[:50],
                )
                fused = fused + fill

        truncated = truncate_for_rerank(fused, self._budget.rerank_candidate_limit)
        final = truncated[:final_top_k]

        self._log_attribution(channel_results, final)

        return final

    @staticmethod
    def _safe_search(channel: SearchChannel, context: SearchContext) -> Optional[SearchChannelResult]:
        """单通道检索的异常隔离包装"""
        try:
            return channel.search(context)
        except Exception as exc:
            logger.warning("通道 %s 检索失败: %s", channel.get_name(), exc)
            return None

    @staticmethod
    def _log_attribution(channel_results: List[SearchChannelResult], final: List[RetrievedChunk]):
        """检索归因日志：最终结果按来源通道分布，便于调参（如调 channel-weights）"""
        if len(channel_results) <= 1:
            return
        source_index: Dict[str, set] = {}
        for result in channel_results:
            for chunk in result.chunks:
                source_index.setdefault(chunk.key(), set()).add(result.channel_type.value)
        counts: Dict[str, int] = {}
        for chunk in final:
            types = source_index.get(chunk.key(), set())
            for t in types:
                counts[t] = counts.get(t, 0) + 1
        logger.info(
            "多路检索归因 - 通道数:%d, 召回合计:%d, 去重融合后送入LLM:%d, 按通道分布:%s",
            len(channel_results),
            sum(len(r.chunks) for r in channel_results),
            len(final),
            json.dumps(counts, ensure_ascii=False),
        )



_default_engine: Optional[MultiChannelRetrievalEngine] = None


def build_default_engine() -> MultiChannelRetrievalEngine:
    """
    按配置装配默认多通道检索引擎。
    - 向量通道：ChromaVectorStore（复用 rag.py 的 collection 与 embeddings）
    - 关键词通道：MySQL LIKE（products / ai_faqs）
    - 热销通道：按销量召回兜底
    """
    global _default_engine
    if _default_engine is not None:
        return _default_engine

    from config import settings
    from rag import _collection, embeddings_model

    try:
        weights = json.loads(getattr(settings, "RETRIEVAL_CHANNEL_WEIGHTS", "{}"))
    except Exception:
        weights = {"vector": 1.0, "keyword": 1.0, "hot": 0.5}

    budget = RetrievalBudget(
        recall_budget=getattr(settings, "RETRIEVAL_RECALL_BUDGET", 20),
        rerank_candidate_limit=getattr(settings, "RETRIEVAL_RERANK_CANDIDATE_LIMIT", 40),
        default_top_k=getattr(settings, "RETRIEVAL_DEFAULT_TOP_K", 10),
    )

    vector_store = ChromaVectorStore(
        _collection,
        embeddings_model,
        min_score=float(getattr(settings, "RETRIEVAL_VECTOR_MIN_SCORE", 0.45) or 0.45),
    )

    def _flag(name: str, default: str = "true") -> bool:
        return str(getattr(settings, name, default)).lower() in ("true", "1", "yes", "on")

    channels: List[SearchChannel] = [
        VectorSearchChannel(vector_store),
        KeywordSearchChannel(enabled=_flag("RETRIEVAL_ENABLE_KEYWORD", "true")),
        HotProductChannel(enabled=_flag("RETRIEVAL_ENABLE_HOT", "true")),
    ]

    _default_engine = MultiChannelRetrievalEngine(
        channels=channels,
        budget=budget,
        rrf_k=getattr(settings, "RETRIEVAL_RRF_K", 20),
        channel_weights=weights,
        max_workers=getattr(settings, "RETRIEVAL_MAX_WORKERS", 4),
    )
    logger.info(
        "多路检索引擎已装配 - 漏斗(recall=%d→rerank=%d→topk=%d), rrf_k=%d, weights=%s",
        budget.recall_budget, budget.rerank_candidate_limit, budget.default_top_k,
        _default_engine._rrf_k, json.dumps(weights, ensure_ascii=False),
    )
    return _default_engine
