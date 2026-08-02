"""
检索结果后处理：去重 + 加权 RRF 融合 + 候选池截断
"""
from __future__ import annotations

from typing import Dict, List, Optional

from retrieval.channel import RetrievedChunk, SearchChannelResult


def dedup_chunks(chunks: List[RetrievedChunk]) -> List[RetrievedChunk]:
    """
    跨通道去重
    同一 key 的 chunk 只保留首个出现的，但多路命中信息会在 RRF 阶段累加。
    """
    seen = set()
    unique: List[RetrievedChunk] = []
    for chunk in chunks:
        k = chunk.key()
        if k in seen:
            continue
        seen.add(k)
        unique.append(chunk)
    return unique


def fuse_by_rrf(
    channel_results: List[SearchChannelResult],
    deduped_chunks: List[RetrievedChunk],
    k: int = 20,
    weights: Optional[Dict[str, float]] = None,
) -> List[RetrievedChunk]:
    """
    加权 RRF 融合

    :param channel_results: 各通道原始召回结果（保持原始顺序，用于按名次累分）
    :param deduped_chunks: 去重后的 chunk 列表（融合分数会回写到这些 chunk 上）
    :param k: RRF 平滑常数。候选池通常 20~40 条，k=60 会过度平滑名次；
              调低至 20 让头部更有区分度（配合归因日志校准）。
    :param weights: 各通道贡献权重，如 {"vector":1.0, "keyword":1.0, "hot":0.5}
    :return: 按 RRF 分数倒序排列的 chunk 列表
    """
    if weights is None:
        weights = {"vector": 1.0, "keyword": 1.0, "hot": 0.5}

    rrf_scores: Dict[str, float] = {}
    for result in channel_results:
        channel_type = result.channel_type.value
        weight = weights.get(channel_type, 1.0)
        for rank_zero, chunk in enumerate(result.chunks):
            delta = weight / (k + rank_zero + 1)
            rrf_scores[chunk.key()] = rrf_scores.get(chunk.key(), 0.0) + delta

    fused = list(deduped_chunks)
    for chunk in fused:
        chunk.score = rrf_scores.get(chunk.key(), 0.0)
    fused.sort(key=lambda c: c.score, reverse=True)
    return fused


def truncate_for_rerank(ranked: List[RetrievedChunk], limit: int = 40) -> List[RetrievedChunk]:
    """
    候选池截断
    仅保留高分前 N 个送入下游精排，控制成本与延迟。
    limit <= 0 表示不截断（全量透传）。
    """
    if limit > 0 and len(ranked) > limit:
        return ranked[:limit]
    return ranked
