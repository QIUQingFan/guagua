"""
向量存储实现
"""
from __future__ import annotations

import hashlib
from typing import List

from retrieval.channel import RetrievedChunk, VectorStore


def _parse_chroma_id(chroma_id: str):
    """
    解析 ChromaDB 文档 id（rag.py 存入格式：{source_type}_{source_id or index}_{index}）
    返回 (source_type, source_id_str)。无法解析时 source_id 为 None。
    """
    parts = chroma_id.split("_")
    if len(parts) >= 2:
        source_type = parts[0]
        source_id = parts[1]
        if source_type == "faq":
            return source_type, None
        return source_type, source_id
    return None, None


class ChromaVectorStore(VectorStore):
    """
    ChromaDB 向量存储实现。
    复用 rag.py 的 collection 与 embeddings_model，保证与既有入库链路同源。

    相似度阈值（RETRIEVAL_VECTOR_MIN_SCORE）：
    ChromaDB 返回的余弦距离无最低相似度概念，任意问题都会返回 top_k 条结果
    （大量无关 chunk 相似度 0.42~0.46）。这里按阈值过滤，把低相似度噪声剔除——
    比如"怎么退货退款"命中 FAQ(0.497) 时，商品块(0.42~0.46) 全部被丢弃，
    从源头避免无关商品进入 RRF 融合、最终霸占引用来源。
    """

    def __init__(self, collection, embeddings_model, min_score: float = 0.45):
        self._collection = collection
        self._embeddings = embeddings_model
        self._min_score = min_score

    def search(self, query: str, top_k: int) -> List[RetrievedChunk]:
        if not query.strip():
            return []
        count = self._collection.count()
        if count == 0:
            return []

        query_vector = self._embeddings.embed_query(query)
        results = self._collection.query(
            query_embeddings=[query_vector],
            n_results=min(top_k, count),
            include=["documents", "metadatas", "distances"],
        )

        docs = results.get("documents", [[]])[0] or []
        metas = results.get("metadatas", [[]])[0] or []
        ids = results.get("ids", [[]])[0] or []
        distances = results.get("distances", [[]])[0] or []

        chunks: List[RetrievedChunk] = []
        for doc, meta, cid, dist in zip(docs, metas, ids, distances):
            source_type, source_id = _parse_chroma_id(cid)
            similarity = max(0.0, 1.0 - float(dist))
            if similarity < self._min_score:
                continue
            chunk_id = None
            if source_type and source_id:
                chunk_id = f"{source_type}:{source_id}"
            elif source_type == "faq":
                chunk_id = f"faq:{hashlib.sha256(doc.encode('utf-8')).hexdigest()[:16]}"
            chunks.append(RetrievedChunk(
                content=doc,
                score=similarity,
                source_type=source_type or (meta.get("source_type") if meta else "unknown") or "unknown",
                source_id=source_id,
                id=chunk_id,
                metadata=dict(meta) if meta else {},
            ))
        return chunks
