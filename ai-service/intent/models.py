"""
意图树数据模型

表结构：
    intent_node
    ├── id              BIGINT    主键
    ├── intent_code     VARCHAR   业务唯一标识，如 group-hr / biz-oa-intro
    ├── name            VARCHAR   展示名称
    ├── level           INT       层级：0=DOMAIN, 1=CATEGORY, 2=TOPIC
    ├── parent_code     VARCHAR   父节点的 intent_code（根节点为空）
    ├── description     TEXT      节点描述
    ├── examples        JSON      示例问题（JSON 数组字符串）
    ├── kind            INT       类型：0=KB(RAG), 1=SYSTEM, 2=MCP
    ├── collection_name VARCHAR   关联知识库集合名称（仅 kind=0 有意义）
    ├── mcp_tool_id     VARCHAR   MCP 工具 ID（仅 kind=2 有意义）
    ├── enabled         TINYINT   是否启用
    └── sort_order      INT       排序
"""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from datetime import datetime
from enum import IntEnum
from typing import Any, Dict, List, Optional

from sqlalchemy import text

from database import SessionLocal

logger = logging.getLogger("intent")


class IntentLevel(IntEnum):
    """意图层级"""
    DOMAIN = 0
    CATEGORY = 1
    TOPIC = 2


class IntentKind(IntEnum):
    """意图节点类型"""
    KB = 0
    SYSTEM = 1
    MCP = 2


@dataclass
class IntentNode:
    """意图树节点"""
    intent_code: str
    name: str
    level: IntentLevel = IntentLevel.TOPIC
    parent_code: Optional[str] = None
    description: str = ""
    examples: List[str] = field(default_factory=list)
    kind: IntentKind = IntentKind.KB
    collection_name: str = ""
    mcp_tool_id: str = ""
    enabled: bool = True
    sort_order: int = 0
    id: Optional[int] = None
    children: List[IntentNode] = field(default_factory=list)
    full_path: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "intent_code": self.intent_code,
            "name": self.name,
            "level": self.level.value,
            "level_name": self.level.name,
            "parent_code": self.parent_code,
            "description": self.description,
            "examples": self.examples,
            "kind": self.kind.value,
            "kind_name": self.kind.name,
            "collection_name": self.collection_name,
            "mcp_tool_id": self.mcp_tool_id,
            "enabled": self.enabled,
            "sort_order": self.sort_order,
            "full_path": self.full_path,
            "children": [c.to_dict() for c in self.children],
        }




def ensure_intent_tables() -> None:
    """幂等创建 intent_node 表。失败不阻断启动。"""
    db = SessionLocal()
    try:
        db.execute(text(
            """
            CREATE TABLE IF NOT EXISTS intent_node (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                intent_code VARCHAR(64) NOT NULL COMMENT '业务唯一标识',
                name VARCHAR(128) NOT NULL COMMENT '展示名称',
                level INT NOT NULL DEFAULT 2 COMMENT '层级：0=DOMAIN, 1=CATEGORY, 2=TOPIC',
                parent_code VARCHAR(64) DEFAULT NULL COMMENT '父节点 intent_code',
                description TEXT COMMENT '节点描述',
                examples JSON COMMENT '示例问题 JSON 数组',
                kind INT NOT NULL DEFAULT 0 COMMENT '类型：0=KB, 1=SYSTEM, 2=MCP',
                collection_name VARCHAR(128) DEFAULT '' COMMENT '关联知识库集合',
                mcp_tool_id VARCHAR(64) DEFAULT '' COMMENT '关联 MCP 工具 ID',
                enabled TINYINT(1) NOT NULL DEFAULT 1,
                sort_order INT NOT NULL DEFAULT 0,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uk_intent_code (intent_code),
                KEY idx_parent (parent_code),
                KEY idx_enabled (enabled)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            COMMENT='意图树节点'
            """
        ))
        db.commit()
        logger.info("intent_node 表已就绪")
    except Exception as exc:
        logger.warning("intent_node 表创建失败（降级为内存树）: %s", exc)
        db.rollback()
    finally:
        db.close()




def _build_guagua_intent_tree() -> List[IntentNode]:
    """
    构建瓜呱商城默认意图树。

    三级结构：
    DOMAIN  →  CATEGORY  →  TOPIC
    """
    product = IntentNode(
        intent_code="product",
        name="商品咨询",
        level=IntentLevel.DOMAIN,
        kind=IntentKind.KB,
        description="商品推荐、选购、价格、库存等商品相关问题",
        collection_name="products",
        sort_order=1,
    )
    product_recommend = IntentNode(
        intent_code="product-recommend",
        name="商品推荐",
        level=IntentLevel.CATEGORY,
        parent_code="product",
        kind=IntentKind.KB,
        collection_name="products",
        description="找商品、选什么、性价比、值得买、求推荐等购物建议",
        examples=["有什么推荐的耳机？", "性价比高的笔记本推荐", "适合送朋友的礼物有哪些"],
        sort_order=1,
    )
    product_price = IntentNode(
        intent_code="product-price",
        name="价格库存",
        level=IntentLevel.CATEGORY,
        parent_code="product",
        kind=IntentKind.KB,
        collection_name="products",
        description="商品价格、优惠、库存等查询",
        examples=["这个多少钱？", "有优惠吗？", "还有货吗？"],
        sort_order=2,
    )
    product.set_children([product_recommend, product_price])

    after_sale = IntentNode(
        intent_code="after-sale",
        name="售后服务",
        level=IntentLevel.DOMAIN,
        kind=IntentKind.KB,
        description="退款、退货、物流、订单等售后相关问题",
        collection_name="faqs",
        sort_order=2,
    )
    as_order = IntentNode(
        intent_code="after-sale-order",
        name="订单查询",
        level=IntentLevel.CATEGORY,
        parent_code="after-sale",
        kind=IntentKind.KB,
        collection_name="faqs",
        description="我的订单、物流、发货等订单状态查询",
        examples=["我的订单到哪了？", "订单号 so2024", "什么时候发货？"],
        sort_order=1,
    )
    as_refund = IntentNode(
        intent_code="after-sale-refund",
        name="退款退货",
        level=IntentLevel.CATEGORY,
        parent_code="after-sale",
        kind=IntentKind.KB,
        collection_name="faqs",
        description="退款、退货、换货、售后政策等",
        examples=["怎么退款？", "退货流程是什么？", "能换货吗？"],
        sort_order=2,
    )
    after_sale.set_children([as_order, as_refund])

    policy = IntentNode(
        intent_code="policy",
        name="平台政策",
        level=IntentLevel.DOMAIN,
        kind=IntentKind.KB,
        description="平台规则、用户协议、隐私政策等",
        collection_name="faqs",
        sort_order=3,
    )
    policy_shipping = IntentNode(
        intent_code="policy-shipping",
        name="配送政策",
        level=IntentLevel.CATEGORY,
        parent_code="policy",
        kind=IntentKind.KB,
        collection_name="faqs",
        description="配送范围、运费、配送时效等",
        examples=["包邮吗？", "多久能到？", "能送到宿舍吗？"],
        sort_order=1,
    )
    policy_privacy = IntentNode(
        intent_code="policy-privacy",
        name="隐私政策",
        level=IntentLevel.CATEGORY,
        parent_code="policy",
        kind=IntentKind.KB,
        collection_name="faqs",
        description="用户隐私、数据安全等",
        examples=["我的信息安全吗？", "你们会泄露我的隐私吗？"],
        sort_order=2,
    )
    policy.set_children([policy_shipping, policy_privacy])

    system = IntentNode(
        intent_code="sys",
        name="系统交互",
        level=IntentLevel.DOMAIN,
        kind=IntentKind.SYSTEM,
        description="问候、关于助手等系统交互",
        sort_order=4,
    )
    sys_welcome = IntentNode(
        intent_code="sys-welcome",
        name="欢迎与问候",
        level=IntentLevel.CATEGORY,
        parent_code="sys",
        kind=IntentKind.SYSTEM,
        description="用户打招呼、问好等",
        examples=["你好", "hello", "早上好", "在吗"],
        sort_order=1,
    )
    sys_about = IntentNode(
        intent_code="sys-about",
        name="关于助手",
        level=IntentLevel.CATEGORY,
        parent_code="sys",
        kind=IntentKind.SYSTEM,
        description="询问助手身份与能力",
        examples=["你是谁？", "你能做什么？", "你是瓜呱吗？"],
        sort_order=2,
    )
    system.set_children([sys_welcome, sys_about])

    analysis = IntentNode(
        intent_code="analysis",
        name="经营分析",
        level=IntentLevel.DOMAIN,
        kind=IntentKind.SYSTEM,
        description="销量数据、经营看板等管理端分析",
        sort_order=5,
    )
    analysis_sales = IntentNode(
        intent_code="analysis-sales",
        name="销售数据",
        level=IntentLevel.CATEGORY,
        parent_code="analysis",
        kind=IntentKind.SYSTEM,
        description="销量、营收、趋势等经营数据查询",
        examples=["今天销量多少？", "这个月的营收数据", "最火的商品是什么？"],
        sort_order=1,
    )
    analysis.set_children([analysis_sales])

    _fill_full_path([product, after_sale, policy, system, analysis], None)
    return [product, after_sale, policy, system, analysis]


def _fill_full_path(nodes: List[IntentNode], parent: Optional[IntentNode]):
    """递归填充 fullPath"""
    for node in nodes:
        if parent is None:
            node.full_path = node.name
        else:
            node.full_path = f"{parent.full_path} > {node.name}"
        if node.children:
            _fill_full_path(node.children, node)


def seed_intent_tree() -> None:
    """向 intent_node 表写入种子数据（幂等：仅当表为空时写入）。"""
    db = SessionLocal()
    try:
        row = db.execute(text("SELECT COUNT(*) AS cnt FROM intent_node")).fetchone()
        if row and row[0] > 0:
            logger.info("intent_node 表已有数据，跳过种子写入")
            return
        roots = _build_guagua_intent_tree()
        _flatten_insert(db, roots)
        db.commit()
        logger.info("意图树种子数据写入完成（%d 个根节点）", len(roots))
    except Exception as exc:
        logger.warning("意图树种子写入失败: %s", exc)
        db.rollback()
    finally:
        db.close()


def _flatten_insert(db, nodes: List[IntentNode], parent_code: Optional[str] = None):
    """递归展平插入节点（BFS 顺序）。"""
    for node in nodes:
        db.execute(
            text(
                """INSERT INTO intent_node
                   (intent_code, name, level, parent_code, description, examples, kind,
                    collection_name, mcp_tool_id, enabled, sort_order)
                   VALUES (:code, :name, :level, :parent, :desc, :examples, :kind,
                           :collection, :mcp, :enabled, :sort)"""
            ),
            {
                "code": node.intent_code,
                "name": node.name,
                "level": node.level.value,
                "parent": node.parent_code,
                "desc": node.description,
                "examples": json.dumps(node.examples, ensure_ascii=False),
                "kind": node.kind.value,
                "collection": node.collection_name,
                "mcp": node.mcp_tool_id,
                "enabled": 1 if node.enabled else 0,
                "sort": node.sort_order,
            },
        )
        if node.children:
            _flatten_insert(db, node.children, node.intent_code)




def load_intent_tree() -> List[IntentNode]:
    """
    从 intent_node 表加载完整意图树（内存树结构）。
    表为空时返回空列表。
    """
    db = SessionLocal()
    try:
        rows = db.execute(
            text(
                "SELECT * FROM intent_node WHERE enabled = 1 ORDER BY level, sort_order"
            )
        ).fetchall()
        if not rows:
            return []
        nodes: Dict[str, IntentNode] = {}
        for row in rows:
            examples = []
            if row.examples:
                try:
                    examples = json.loads(row.examples) if isinstance(row.examples, str) else row.examples
                except Exception:
                    pass
            node = IntentNode(
                id=row.id,
                intent_code=row.intent_code,
                name=row.name,
                level=IntentLevel(row.level),
                parent_code=row.parent_code,
                description=row.description or "",
                examples=examples if isinstance(examples, list) else [],
                kind=IntentKind(row.kind),
                collection_name=row.collection_name or "",
                mcp_tool_id=row.mcp_tool_id or "",
                enabled=bool(row.enabled),
                sort_order=row.sort_order,
            )
            nodes[node.intent_code] = node
        roots: List[IntentNode] = []
        for node in nodes.values():
            if node.parent_code and node.parent_code in nodes:
                parent = nodes[node.parent_code]
                parent.children.append(node)
            else:
                roots.append(node)
        for node in nodes.values():
            node.children.sort(key=lambda n: n.sort_order)
        roots.sort(key=lambda n: n.sort_order)
        _fill_full_path(roots, None)
        logger.info("从 DB 加载意图树：%d 个节点", len(nodes))
        return roots
    except Exception as exc:
        logger.warning("从 DB 加载意图树失败: %s", exc)
        return []
    finally:
        db.close()


IntentNode.set_children = lambda self, children: setattr(self, "children", children)