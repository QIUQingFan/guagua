"""
RAG 知识库：
"""
import json
import os
from typing import List, Tuple
from sqlalchemy import text
import chromadb
from langchain_openai import OpenAIEmbeddings
from database import engine, SessionLocal
from config import settings

_CHROMA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "chroma_data")
os.makedirs(_CHROMA_DIR, exist_ok=True)
_chroma_client = chromadb.PersistentClient(path=_CHROMA_DIR)
_collection = _chroma_client.get_or_create_collection(
    name="guagua_knowledge",
    metadata={"hnsw:space": "cosine"},
)

embeddings_model = OpenAIEmbeddings(
    model=settings.ZHIPU_EMBEDDING_MODEL,
    openai_api_key=settings.ZHIPU_API_KEY,
    openai_api_base=settings.ZHIPU_BASE_URL,
)


def query_in_stock_product_ids(ids: List[int]) -> set:
    """实时查询哪些商品当前在售且有库存

    用于检索/推荐链路做实时库存兜底：向量索引是构建时的静态快照，
    商品可能随后售空，这里以数据库为准剔除买不到的商品。
    """
    from guagua_adapter import PRODUCT_STATUS_ON_SALE

    if not ids:
        return set()
    uniq_ids = list(dict.fromkeys(ids))
    in_stock: set = set()
    batch_size = 200
    with engine.connect() as conn:
        for i in range(0, len(uniq_ids), batch_size):
            batch = uniq_ids[i : i + batch_size]
            placeholders = ",".join(f":id{j}" for j in range(len(batch)))
            params = {f"id{j}": pid for j, pid in enumerate(batch)}
            params["status"] = PRODUCT_STATUS_ON_SALE
            rows = conn.execute(
                text(
                    f"SELECT p.id FROM products p "
                    f"WHERE p.id IN ({placeholders}) "
                    f"AND p.is_deleted = 0 AND p.status = :status "
                    f"AND COALESCE(p.stock, 0) > 0"
                ),
                params,
            ).fetchall()
            in_stock.update(r[0] for r in rows)
    return in_stock


def _build_product_chunks() -> List[dict]:
    from guagua_adapter import PRODUCT_STATUS_ON_SALE

    chunks = []
    with engine.connect() as conn:
        rows = conn.execute(text("""
            SELECT p.id, p.title AS name, p.subtitle, p.description, p.price,
                   p.original_price, p.stock, p.sales, p.cover_image,
                   c.name AS category_name
            FROM products p
            LEFT JOIN shop_categories c ON p.category_id = c.id
            WHERE p.is_deleted = 0 AND p.status = :status
              AND COALESCE(p.stock, 0) > 0
        """), {"status": PRODUCT_STATUS_ON_SALE}).fetchall()

    for r in rows:
        content = (
            f"商品名称：{r.name}\n"
            f"副标题：{r.subtitle or ''}\n"
            f"分类：{r.category_name or '未知'}\n"
            f"价格：¥{r.price}（原价：¥{r.original_price or r.price}）\n"
            f"库存：{r.stock} 件\n"
            f"销量：{r.sales}\n"
            f"描述：{r.description or ''}"
        )
        chunks.append({
            "source_type": "product",
            "source_id": r.id,
            "content": content,
            "metadata": {
                "name": r.name,
                "price": float(r.price),
                "category": r.category_name or "",
                "stock": int(r.stock or 0),
            },
        })
    return chunks


def _build_faq_chunks() -> List[dict]:
    chunks = []
    with engine.connect() as conn:
        rows = conn.execute(text("""
            SELECT question, answer, category FROM ai_faqs
            WHERE is_active = 1 ORDER BY sort DESC
        """)).fetchall()

    for r in rows:
        chunks.append({
            "source_type": "faq",
            "source_id": None,
            "content": f"问：{r.question}\n答：{r.answer}",
            "metadata": {
                "question": r.question,
                "category": r.category or "",
            },
        })
    return chunks



def ensure_documents_table() -> None:
    db = SessionLocal()
    try:
        db.execute(text(
            """
            CREATE TABLE IF NOT EXISTS ai_documents (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                title VARCHAR(255) NOT NULL COMMENT '文档标题（唯一，md5 去重键）',
                content MEDIUMTEXT NOT NULL COMMENT '文档正文',
                source_type VARCHAR(32) NOT NULL DEFAULT 'document'
                    COMMENT '来源类型 document/policy/faq',
                category VARCHAR(32) NOT NULL DEFAULT ''
                    COMMENT '分类 refund/after_sale/shipping/payment/other',
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                    ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uk_title (title)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            COMMENT='AI 知识库上传文档（入库 Pipeline 的事实源）'
            """
        ))
        db.commit()
        print("[RAG] ai_documents 表已就绪（文档持久化）")
    except Exception as exc:
        db.rollback()
        print(f"[RAG] ai_documents 建表失败: {exc}")
    finally:
        db.close()


def _save_document(title: str, content: str, source_type: str, category: str) -> bool:
    db = SessionLocal()
    try:
        db.execute(
            text(
                """
                INSERT INTO ai_documents (title, content, source_type, category)
                VALUES (:t, :c, :s, :cat)
                ON DUPLICATE KEY UPDATE
                    content = VALUES(content),
                    source_type = VALUES(source_type),
                    category = VALUES(category)
                """
            ),
            {"t": title, "c": content, "s": source_type, "cat": category},
        )
        db.commit()
        return True
    except Exception as exc:
        db.rollback()
        print(f"[RAG] ai_documents 写入失败: {exc}")
        return False
    finally:
        db.close()


def _load_documents() -> List[dict]:
    rows = []
    try:
        with engine.connect() as conn:
            rows = conn.execute(text(
                "SELECT title, content, source_type, category FROM ai_documents ORDER BY id"
            )).mappings().all()
    except Exception as exc:
        print(f"[RAG] ai_documents 读取失败: {exc}")
    return [dict(r) for r in rows]


def _build_document_chunks() -> List[dict]:
    import hashlib
    chunks: List[dict] = []
    for doc in _load_documents():
        title = doc.get("title") or ""
        if not title:
            continue
        base_id = hashlib.md5(title.encode("utf-8")).hexdigest()[:12]
        pieces = _chunk_text(doc.get("content") or "", max_chunk=500, overlap=50)
        for i, piece in enumerate(pieces):
            chunks.append({
                "source_type": doc.get("source_type") or "document",
                "source_id": base_id,
                "content": piece,
                "metadata": {
                    "title": title,
                    "category": doc.get("category") or "",
                    "chunk_index": str(i),
                },
            })
    return chunks



def build_knowledge_base():
    chunks = _build_product_chunks() + _build_faq_chunks() + _build_document_chunks()
    if not chunks:
        print("[RAG] 无数据可索引")
        return

    print(f"[RAG] 开始索引 {len(chunks)} 个文本块...")
    texts = [c["content"] for c in chunks]

    all_vectors = []
    batch_size = 50
    for i in range(0, len(texts), batch_size):
        batch = texts[i : i + batch_size]
        vectors = embeddings_model.embed_documents(batch)
        all_vectors.extend(vectors)
        print(f"[RAG] 已向量化 {min(i + batch_size, len(texts))}/{len(chunks)}")

    _chroma_client.delete_collection("guagua_knowledge")
    fresh_collection = _chroma_client.get_or_create_collection(
        name="guagua_knowledge",
        metadata={"hnsw:space": "cosine"},
    )
    global _collection
    _collection = fresh_collection

    ids = [f"{c['source_type']}_{c['source_id'] or i}_{i}" for i, c in enumerate(chunks)]
    metadatas = []
    for c in chunks:
        m = {k: (str(v) if v is not None else "") for k, v in c["metadata"].items()}
        m["source_type"] = c["source_type"]
        metadatas.append(m)

    batch_size = 100
    for i in range(0, len(chunks), batch_size):
        _collection.add(
            ids=ids[i : i + batch_size],
            documents=[c["content"] for c in chunks[i : i + batch_size]],
            embeddings=all_vectors[i : i + batch_size],
            metadatas=metadatas[i : i + batch_size],
        )
    print(f"[RAG] 知识库构建完成，共 {len(chunks)} 条（ChromaDB）")


def search_knowledge(query: str, top_k: int = 5) -> List[Tuple[str, dict]]:
    """
    语义检索：返回最相关的文本块列表
    :return: [(content, metadata), ...]
    """
    query_vector = embeddings_model.embed_query(query)

    count = _collection.count()
    if count == 0:
        return []

    results = _collection.query(
        query_embeddings=[query_vector],
        n_results=min(top_k, count),
        include=["documents", "metadatas", "ids"],
    )

    docs = results.get("documents", [[]])[0] or []
    metas = results.get("metadatas", [[]])[0] or []
    ids = results.get("ids", [[]])[0] or []

    # 实时库存过滤：索引是构建时快照，剔除已售空/下架商品，防止推荐买不到的商品
    product_ids: List[int] = []
    for cid, meta in zip(ids, metas):
        if (meta or {}).get("source_type") not in ("product", "hot"):
            continue
        parts = str(cid).split("_")
        if len(parts) >= 2 and parts[1].isdigit():
            product_ids.append(int(parts[1]))
    in_stock = query_in_stock_product_ids(product_ids)

    result: List[Tuple[str, dict]] = []
    for doc, meta, cid in zip(docs, metas, ids):
        if (meta or {}).get("source_type") in ("product", "hot"):
            parts = str(cid).split("_")
            if len(parts) >= 2 and parts[1].isdigit():
                if int(parts[1]) not in in_stock:
                    continue
            else:
                continue
        result.append((doc, meta))
    return result



def _chunk_text(text: str, max_chunk: int = 500, overlap: int = 50) -> List[str]:
    """将长文本按段落 + 固定长度切分为 chunk。

    切分策略：
    1. 先按双换行（段落）拆分
    2. 段落超 max_chunk 字符时按 max_chunk 硬切，带 overlap 保证上下文连续
    3. 段落短于 max_chunk 则整段保留
    """
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


def ingest_document(title: str, content: str, source_type: str = "document",
                    category: str = "", extra_metadata: dict = None) -> dict:
    """增量入库一篇文档：持久化 → 切分 → 向量化 → 写入 ChromaDB。
    :param title: 文档标题（存入 metadata.title，同时作为 MySQL 唯一键）
    :param content: 文档正文
    :param source_type: 来源类型（document/policy 等）
    :param category: 分类标签
    :param extra_metadata: 额外元数据
    :return: {"chunks": N, "title": ...}
    """
    if not content or not content.strip():
        return {"chunks": 0, "title": title}

    _save_document(title, content, source_type, category)

    chunks_text = _chunk_text(content, max_chunk=500, overlap=50)
    if not chunks_text:
        return {"chunks": 0, "title": title}

    batch_size = 50
    all_vectors = []
    for i in range(0, len(chunks_text), batch_size):
        batch = chunks_text[i:i + batch_size]
        vectors = embeddings_model.embed_documents(batch)
        all_vectors.extend(vectors)

    import hashlib
    base_id = hashlib.md5(title.encode("utf-8")).hexdigest()[:12]
    ids = [f"{source_type}_{base_id}_{i}" for i in range(len(chunks_text))]
    metadatas = []
    for i, chunk in enumerate(chunks_text):
        m = {
            "source_type": source_type,
            "title": title,
            "category": category or "",
            "chunk_index": str(i),
        }
        if extra_metadata:
            m.update({k: str(v) if v is not None else "" for k, v in extra_metadata.items()})
        metadatas.append(m)

    try:
        _collection.delete(ids=ids)
    except Exception:
        pass
    _collection.add(
        ids=ids,
        documents=chunks_text,
        embeddings=all_vectors,
        metadatas=metadatas,
    )
    print(f"[RAG] 文档入库完成：{title} → {len(chunks_text)} 个 chunk（已持久化到 ai_documents）")
    return {"chunks": len(chunks_text), "title": title}


def get_knowledge_stats() -> dict:
    """获取知识库统计信息（供管理后台展示）。"""
    try:
        total_chunks = _collection.count()
    except Exception:
        total_chunks = 0

    type_counts: dict = {}
    try:
        all_data = _collection.get(include=["metadatas"])
        for meta in all_data.get("metadatas", []):
            st = (meta or {}).get("source_type", "unknown")
            type_counts[st] = type_counts.get(st, 0) + 1
    except Exception:
        pass

    faq_count = 0
    try:
        with engine.connect() as conn:
            row = conn.execute(text("SELECT COUNT(*) AS cnt FROM ai_faqs WHERE is_active = 1")).fetchone()
            faq_count = row[0] if row else 0
    except Exception:
        pass

    return {
        "total_chunks": total_chunks,
        "type_distribution": type_counts,
        "faq_count": faq_count,
        "collection_name": "guagua_knowledge",
    }
