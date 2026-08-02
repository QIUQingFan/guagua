"""
意图树 + 多知识库路由模块

模块职责：
- intent/models.py  ：IntentNode 数据模型 + intent_node 表 CRUD
- intent/intent_router.py：意图分类器 → 树匹配 → 多知识库路由引擎
"""
from __future__ import annotations

from intent.models import IntentNode, IntentKind, ensure_intent_tables, seed_intent_tree
from intent.intent_router import IntentRouter, IntentRouteResult, build_default_router

__all__ = [
    "IntentNode", "IntentKind",
    "ensure_intent_tables", "seed_intent_tree",
    "IntentRouter", "IntentRouteResult", "build_default_router",
]