"""
检索通道

每个通道负责一种检索策略，多个通道可并行执行，最后统一合并结果。
- VectorSearchChannel：基于向量库的语义检索
- KeywordSearchChannel：基于 MySQL LIKE 的精确/关键词检索
- HotProductChannel：按销量召回的热销兜底通道

设计要点：
1. VectorStore 抽象隔离向量库实现 —— 切换 Milvus 时只需新增 MilvusVectorStore，
   检索通道、RRF 融合、引擎编排全部不动。
2. 各通道返回 RetrievedChunk，带稳定的去重键（source_type:source_id，缺失时退化为内容 SHA-256）。
3. 商品数据源统一过滤 status='on_sale'、is_deleted=0、stock>0（项目硬约束）。
"""
from __future__ import annotations

import hashlib
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

from sqlalchemy import text




class SearchChannelType(str, Enum):
    """检索通道类型（用于 RRF 加权与归因日志）"""
    VECTOR = "vector"
    KEYWORD = "keyword"
    HOT = "hot"


@dataclass
class RetrievedChunk:
    """检索召回的单个文本块"""
    content: str
    score: float = 0.0
    source_type: str = "unknown"
    source_id: Optional[Any] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    id: Optional[str] = None

    def key(self) -> str:
        """统一去重键：有 id 用 id，否则用 content 的 SHA-256"""
        if self.id:
            return self.id
        return hashlib.sha256(self.content.encode("utf-8")).hexdigest()


@dataclass
class SearchContext:
    """单次检索上下文"""
    query: str
    recall_budget: int = 20
    top_k: int = 10
    user_id: Optional[int] = None


@dataclass
class SearchChannelResult:
    """单通道检索结果（保留原始召回顺序，供 RRF 按名次累分）"""
    channel_type: SearchChannelType
    chunks: List[RetrievedChunk]



class VectorStore(ABC):
    """
    向量存储抽象接口。
    """

    @abstractmethod
    def search(self, query: str, top_k: int) -> List[RetrievedChunk]:
        """语义检索：返回最多 top_k 个相关 chunk"""
        raise NotImplementedError



def _format_product_content(row: Dict[str, Any]) -> str:
    """把 MySQL 商品行格式化为知识文本（与 rag._build_product_chunks 对齐，便于跨通道去重与一致展示）"""
    return (
        f"商品名称：{row['name']}\n"
        f"副标题：{row.get('subtitle') or ''}\n"
        f"分类：{row.get('category_name') or '未知'}\n"
        f"价格：¥{row['price']}（原价：¥{row.get('original_price') or row['price']}）\n"
        f"库存：{row.get('stock', 0)} 件\n"
        f"销量：{row.get('sales', 0)}\n"
        f"描述：{row.get('description') or ''}"
    )



_QUESTION_WORDS = (
    "怎么", "如何", "请问", "一下", "什么", "哪个", "哪些", "可以", "能不能",
    "有没有", "我想", "我要", "麻烦", "帮", "呢", "吗", "呀", "啊", "吧", "哦",
)


def _keyword_candidates(query: str, limit: int = 6) -> List[str]:
    """从用户查询中提取关键词候选（供关键词通道 OR 匹配）。

    思路：
    1. 去掉标点与非中英文数字字符
    2. 剔除常见疑问词/助词（"怎么/如何/请问…"），得到"内容词干"
    3. 词干整句 + 2/3 字滑窗片段都作为候选（"退货退款"→["退货退款","退货","退款"]），
       让"怎么退货退款"能命中 FAQ"如何退货退款"，而不依赖完全相同的措辞

    说明：这是 MySQL LIKE 的轻量替代，做字面包含判断，用 OR 组合弥补措辞差异；候选数受 limit 约束避免 OR 过宽。
    """
    import re
    cleaned = re.sub(r"[^\u4e00-\u9fa5A-Za-z0-9]", "", query)
    for w in _QUESTION_WORDS:
        cleaned = cleaned.replace(w, "")
    candidates: List[str] = []
    if len(cleaned) >= 2:
        candidates.append(cleaned)
    if len(cleaned) >= 4:
        for span in (2, 3):
            for i in range(0, len(cleaned) - span + 1, span):
                seg = cleaned[i:i + span]
                if len(seg) >= 2 and seg not in candidates:
                    candidates.append(seg)
    return candidates[:limit]


class SearchChannel(ABC):
    """
    检索通道接口。
    每个通道负责一种检索策略，独立执行、互不影响。
    """

    @abstractmethod
    def get_name(self) -> str:
        """通道名称（日志/监控用）"""

    @abstractmethod
    def get_type(self) -> SearchChannelType:
        """通道类型"""

    @abstractmethod
    def is_enabled(self, context: SearchContext) -> bool:
        """是否启用该通道"""

    @abstractmethod
    def search(self, context: SearchContext) -> SearchChannelResult:
        """执行检索，返回该通道的召回结果（保持原始顺序）"""



class VectorSearchChannel(SearchChannel):
    """向量语义检索通道"""

    def __init__(self, vector_store: VectorStore):
        self._store = vector_store

    def get_name(self) -> str:
        return "Vector"

    def get_type(self) -> SearchChannelType:
        return SearchChannelType.VECTOR

    def is_enabled(self, context: SearchContext) -> bool:
        return True

    def search(self, context: SearchContext) -> SearchChannelResult:
        chunks = self._store.search(context.query, context.recall_budget)
        return SearchChannelResult(channel_type=self.get_type(), chunks=chunks)



class KeywordSearchChannel(SearchChannel):
    """
    关键词检索通道：基于 MySQL products / ai_faqs 的 LIKE 匹配。
    """

    def __init__(self, enabled: bool = True):
        self._enabled = enabled

    def get_name(self) -> str:
        return "Keyword"

    def get_type(self) -> SearchChannelType:
        return SearchChannelType.KEYWORD

    def is_enabled(self, context: SearchContext) -> bool:
        return self._enabled and bool(context.query.strip())

    def search(self, context: SearchContext) -> SearchChannelResult:
        from database import engine as db_engine
        from guagua_adapter import PRODUCT_STATUS_ON_SALE

        query = context.query.strip()
        limit = context.recall_budget
        chunks: List[RetrievedChunk] = []

        candidates = _keyword_candidates(query)
        if not candidates:
            candidates = [query]
        like_clause = " OR ".join(
            [
                "(p.title LIKE :q0 OR COALESCE(p.subtitle,'') LIKE :q0 OR COALESCE(p.description,'') LIKE :q0 OR COALESCE(c.name,'') LIKE :q0)"
            ]
            * len(candidates)
        )
        params: dict = {"status": PRODUCT_STATUS_ON_SALE, "limit": limit}
        for i, kw in enumerate(candidates):
            params[f"q{i}"] = f"%{kw}%"

        product_sql = text(
            f"""
            SELECT p.id, p.title AS name, COALESCE(p.subtitle,'') AS subtitle,
                   COALESCE(p.description,'') AS description, p.price,
                   COALESCE(p.original_price, p.price) AS original_price,
                   COALESCE(p.stock,0) AS stock, COALESCE(p.sales,0) AS sales,
                   COALESCE(c.name,'') AS category_name
            FROM products p
            LEFT JOIN shop_categories c ON p.category_id = c.id
            WHERE p.is_deleted = 0 AND p.status = :status AND COALESCE(p.stock,0) > 0
              AND ({like_clause})
            ORDER BY COALESCE(p.sales,0) DESC
            LIMIT :limit
            """
        )
        with db_engine.connect() as conn:
            rows = conn.execute(product_sql, params).mappings().all()

        for r in rows:
            chunks.append(RetrievedChunk(
                content=_format_product_content(dict(r)),
                source_type="product",
                source_id=r["id"],
                id=f"product:{r['id']}",
                metadata={"name": r["name"], "price": float(r["price"] or 0),
                          "category": r["category_name"] or "", "stock": int(r["stock"] or 0)},
            ))

        faq_limit = max(0, limit - len(chunks))
        if faq_limit:
            faq_like = " OR ".join(
                [
                    "(question LIKE :q0 OR answer LIKE :q0 OR COALESCE(category,'') LIKE :q0)"
                ]
                * len(candidates)
            )
            faq_params = {"limit": faq_limit}
            for i, kw in enumerate(candidates):
                faq_params[f"q{i}"] = f"%{kw}%"
            faq_sql = text(
                f"""
                SELECT question, answer, category FROM ai_faqs
                WHERE is_active = 1
                  AND ({faq_like})
                ORDER BY sort DESC LIMIT :limit
                """
            )
            with db_engine.connect() as conn:
                faq_rows = conn.execute(faq_sql, faq_params).mappings().all()
            for r in faq_rows:
                content = f"问：{r['question']}\n答：{r['answer']}"
                chunks.append(RetrievedChunk(
                    content=content,
                    source_type="faq",
                    source_id=r["question"],
                    id=f"faq:{hashlib.sha256(content.encode('utf-8')).hexdigest()[:16]}",
                    metadata={"question": r["question"], "category": r["category"] or ""},
                ))

        return SearchChannelResult(channel_type=self.get_type(), chunks=chunks)



class HotProductChannel(SearchChannel):
    """
    热销兜底通道：按销量召回在售商品。

    作用：当用户问题模糊（如「推荐个东西」）导致向量/关键词召回稀少时，
    热销商品作为基础候选参与 RRF 融合，避免空结果。降权（默认 0.5）避免噪声抢前排。
    """

    def __init__(self, enabled: bool = True):
        self._enabled = enabled

    def get_name(self) -> str:
        return "Hot"

    def get_type(self) -> SearchChannelType:
        return SearchChannelType.HOT

    def is_enabled(self, context: SearchContext) -> bool:
        return self._enabled

    def search(self, context: SearchContext) -> SearchChannelResult:
        from database import engine as db_engine
        from guagua_adapter import PRODUCT_STATUS_ON_SALE

        sql = text("""
            SELECT p.id, p.title AS name, COALESCE(p.subtitle,'') AS subtitle,
                   COALESCE(p.description,'') AS description, p.price,
                   COALESCE(p.original_price, p.price) AS original_price,
                   COALESCE(p.stock,0) AS stock, COALESCE(p.sales,0) AS sales,
                   COALESCE(c.name,'') AS category_name
            FROM products p
            LEFT JOIN shop_categories c ON p.category_id = c.id
            WHERE p.is_deleted = 0 AND p.status = :status AND COALESCE(p.stock,0) > 0
            ORDER BY COALESCE(p.sales,0) DESC, p.created_at DESC
            LIMIT :limit
        """)
        with db_engine.connect() as conn:
            rows = conn.execute(sql, {
                "status": PRODUCT_STATUS_ON_SALE, "limit": context.recall_budget,
            }).mappings().all()

        chunks = [
            RetrievedChunk(
                content=_format_product_content(dict(r)),
                source_type="hot",
                source_id=r["id"],
                id=f"product:{r['id']}",
                metadata={"name": r["name"], "price": float(r["price"] or 0),
                          "category": r["category_name"] or "", "stock": int(r["stock"] or 0)},
            )
            for r in rows
        ]
        return SearchChannelResult(channel_type=self.get_type(), chunks=chunks)
