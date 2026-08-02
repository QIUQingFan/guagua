"""
入库 Pipeline 节点
"""
from __future__ import annotations

import hashlib
import time
from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional

from sqlalchemy import text

from database import engine


class IngestionContext:
    """Pipeline 执行上下文：前序节点输出存入 items/chunks/vectors，供后续节点消费。"""

    def __init__(self, task_type: str = "full"):
        self.task_type = task_type
        self.items: List[dict] = []
        self.chunks: List[dict] = []
        self.vectors: List[List[float]] = []
        self.stats: Dict[str, int] = {}


class IngestionNode(ABC):
    """节点抽象基类：execute(ctx) -> ctx。"""

    node_key: str = "base"

    def __init__(self, config: Optional[dict] = None):
        self.config = config or {}

    @abstractmethod
    def execute(self, ctx: IngestionContext) -> IngestionContext:
        raise NotImplementedError

    def should_run(self, ctx: IngestionContext) -> bool:
        """条件执行：配置 skip_if_empty=true 时，前置无数据则跳过节点。"""
        if self.config.get("skip_if_empty") and not ctx.chunks and not ctx.items:
            return False
        return True



class DocumentFetcherNode(IngestionNode):
    node_key = "fetcher"

    def execute(self, ctx: IngestionContext) -> IngestionContext:
        from guagua_adapter import PRODUCT_STATUS_ON_SALE

        items: List[dict] = []
        since = self.config.get("since")

        with engine.connect() as conn:
            product_sql = """
                SELECT p.id, p.title AS name, p.subtitle, p.description, p.price,
                       p.original_price, p.stock, p.sales, p.cover_image,
                       c.name AS category_name
                FROM products p
                LEFT JOIN shop_categories c ON p.category_id = c.id
                WHERE p.is_deleted = 0 AND p.status = :status
            """
            params: Dict[str, Any] = {"status": PRODUCT_STATUS_ON_SALE}
            if since:
                product_sql += " AND p.updated_at > :since"
                params["since"] = since
            product_sql += " ORDER BY p.id"
            for r in conn.execute(text(product_sql), params).fetchall():
                items.append({"kind": "product", "row": dict(r._mapping)})

            if not since:
                for r in conn.execute(text(
                    "SELECT question, answer, category FROM ai_faqs WHERE is_active = 1 ORDER BY sort DESC"
                )).fetchall():
                    items.append({"kind": "faq", "row": dict(r._mapping)})

            if not since:
                for r in conn.execute(text(
                    "SELECT title, content, source_type, category FROM ai_documents ORDER BY id"
                )).fetchall():
                    items.append({"kind": "document", "row": dict(r._mapping)})

        ctx.items = items
        ctx.stats["fetched"] = len(items)
        return ctx



def _chunk_text(text: str, max_chunk: int = 500, overlap: int = 50) -> List[str]:
    """长文本切分（与 rag.py _chunk_text 逻辑一致，保证 id/内容完全对齐）。"""
    import re
    paragraphs = re.split(r'\n\s*\n', text.strip())
    chunks: List[str] = []
    for para in paragraphs:
        para = para.strip()
        if not para:
            continue
        if len(para) <= max_chunk:
            chunks.append(para)
        else:
            start = 0
            while start < len(para):
                end = start + max_chunk
                chunks.append(para[start:end])
                start = end - overlap
    return chunks or [text.strip()]


class ChunkingNode(IngestionNode):
    node_key = "chunker"

    def execute(self, ctx: IngestionContext) -> IngestionContext:
        chunks: List[dict] = []
        for item in ctx.items:
            kind = item["kind"]
            row = item["row"]
            if kind == "product":
                content = (
                    f"商品名称：{row.get('name')}\n"
                    f"副标题：{row.get('subtitle') or ''}\n"
                    f"分类：{row.get('category_name') or '未知'}\n"
                    f"价格：¥{row.get('price')}（原价：¥{row.get('original_price') or row.get('price')}）\n"
                    f"库存：{row.get('stock')} 件\n"
                    f"销量：{row.get('sales')}\n"
                    f"描述：{row.get('description') or ''}"
                )
                chunks.append({
                    "source_type": "product",
                    "source_id": row.get("id"),
                    "content": content,
                    "metadata": {
                        "name": row.get("name"),
                        "price": float(row.get("price") or 0),
                        "category": row.get("category_name") or "",
                        "stock": int(row.get("stock") or 0),
                    },
                })
            elif kind == "faq":
                content = f"问：{row.get('question')}\n答：{row.get('answer')}"
                chunks.append({
                    "source_type": "faq",
                    "source_id": None,
                    "content": content,
                    "metadata": {"question": row.get("question"), "category": row.get("category") or ""},
                })
            elif kind == "document":
                title = row.get("title") or ""
                base_id = hashlib.md5(title.encode("utf-8")).hexdigest()[:12]
                pieces = _chunk_text(row.get("content") or "")
                for i, piece in enumerate(pieces):
                    chunks.append({
                        "source_type": row.get("source_type") or "document",
                        "source_id": base_id,
                        "content": piece,
                        "metadata": {
                            "title": title,
                            "category": row.get("category") or "",
                            "chunk_index": str(i),
                        },
                    })

        ctx.chunks = chunks
        ctx.stats["chunked"] = len(chunks)
        return ctx



class EmbeddingNode(IngestionNode):
    node_key = "embedder"

    def execute(self, ctx: IngestionContext) -> IngestionContext:
        from rag import embeddings_model

        texts = [c["content"] for c in ctx.chunks]
        vectors: List[List[float]] = []
        batch_size = 50
        for i in range(0, len(texts), batch_size):
            batch = texts[i : i + batch_size]
            vectors.extend(embeddings_model.embed_documents(batch))
        ctx.vectors = vectors
        ctx.stats["embedded"] = len(vectors)
        return ctx



class VectorWriteNode(IngestionNode):
    node_key = "vector_write"

    def _build_ids(self, chunks: List[dict]) -> List[str]:
        """生成 ChromaDB id（与 rag.py build_knowledge_base / ingest_document 完全一致）。"""
        ids = []
        for i, c in enumerate(chunks):
            if c["source_type"] == "document":
                ids.append(f"document_{c['source_id']}_{c['metadata'].get('chunk_index', i)}")
            else:
                ids.append(f"{c['source_type']}_{c['source_id'] or i}_{i}")
        return ids

    def execute(self, ctx: IngestionContext) -> IngestionContext:
        from rag import _chroma_client, _collection

        if not ctx.chunks:
            ctx.stats["written"] = 0
            return ctx

        if ctx.task_type == "full":
            _chroma_client.delete_collection("guagua_knowledge")
            fresh = _chroma_client.get_or_create_collection(
                name="guagua_knowledge",
                metadata={"hnsw:space": "cosine"},
            )
            import rag
            rag._collection = fresh
            collection = fresh
        else:
            collection = _collection

        ids = self._build_ids(ctx.chunks)
        metadatas = []
        for c in ctx.chunks:
            m = {k: (str(v) if v is not None else "") for k, v in c["metadata"].items()}
            m["source_type"] = c["source_type"]
            metadatas.append(m)

        if ctx.task_type == "incremental":
            try:
                collection.delete(ids=ids)
            except Exception:
                pass

        batch_size = 100
        for i in range(0, len(ctx.chunks), batch_size):
            collection.add(
                ids=ids[i : i + batch_size],
                documents=[c["content"] for c in ctx.chunks[i : i + batch_size]],
                embeddings=ctx.vectors[i : i + batch_size],
                metadatas=metadatas[i : i + batch_size],
            )
        ctx.stats["written"] = len(ids)
        return ctx



class KeywordIndexSyncNode(IngestionNode):
    node_key = "keyword_sync"

    def execute(self, ctx: IngestionContext) -> IngestionContext:
        counts: Dict[str, int] = {}
        with engine.connect() as conn:
            try:
                counts["product"] = conn.execute(text(
                    "SELECT COUNT(*) AS c FROM products WHERE is_deleted = 0 AND status = 'on_sale'"
                )).fetchone()[0]
            except Exception:
                pass
            try:
                counts["faq"] = conn.execute(text(
                    "SELECT COUNT(*) AS c FROM ai_faqs WHERE is_active = 1"
                )).fetchone()[0]
            except Exception:
                pass
            try:
                counts["document"] = conn.execute(text(
                    "SELECT COUNT(*) AS c FROM ai_documents"
                )).fetchone()[0]
            except Exception:
                pass
        counts["vector_chunk"] = ctx.stats.get("written", len(ctx.chunks))
        ctx.stats["keyword_synced"] = counts
        return ctx
