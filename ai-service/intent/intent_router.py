"""
意图树路由引擎
"""
from __future__ import annotations

import logging
import re
from typing import Dict, List, Optional, Tuple

from langchain_core.messages import HumanMessage

from config import settings
from intent.models import (
    IntentKind,
    IntentLevel,
    IntentNode,
    _build_guagua_intent_tree,
    load_intent_tree,
)
from model_router import get_default_router
from prompts import load_prompt

logger = logging.getLogger("intent_router")


class IntentRouteResult:
    """
    意图路由结果。

    Attributes:
        intent_code: 匹配到的叶子节点 code
        intent_name: 节点名称
        full_path: 完整路径（如 "商品咨询 > 商品推荐"）
        confidence: 置信度 0.0~1.0
        kind: 节点类型（KB/SYSTEM/MCP）
        collection_name: 关联知识库集合（仅 KB 类型）
        is_high_confidence: 是否为高置信度（≥ threshold）
        is_system: 是否为系统交互节点
        is_mcp: 是否为 MCP 工具节点
        leaf_node: 匹配到的叶子节点
    """

    def __init__(
        self,
        intent_code: str,
        confidence: float,
        leaf_node: Optional[IntentNode] = None,
        threshold: float = 0.7,
    ):
        self.intent_code = intent_code
        self.confidence = confidence
        self.leaf_node = leaf_node
        self.threshold = threshold

        self.intent_name = leaf_node.name if leaf_node else intent_code
        self.full_path = leaf_node.full_path if leaf_node else intent_code
        self.kind = leaf_node.kind if leaf_node else IntentKind.KB
        self.collection_name = leaf_node.collection_name if leaf_node else ""
        self.is_high_confidence = confidence >= threshold
        self.is_system = leaf_node.kind == IntentKind.SYSTEM if leaf_node else False
        self.is_mcp = leaf_node.kind == IntentKind.MCP if leaf_node else False

    def __repr__(self) -> str:
        return (
            f"IntentRouteResult(code={self.intent_code}, "
            f"confidence={self.confidence:.2f}, "
            f"path={self.full_path}, "
            f"high_conf={self.is_high_confidence})"
        )


class IntentRouter:
    """
    意图路由器：LLM 分类 → 树匹配 → 路由决策。

    责责：
    - 用 LLM 做语义分类（而非全文 Embedding）
    - 匹配意图树叶子节点
    - 高置信走定向检索，低置信走全局兜底
    """

    def __init__(
        self,
        tree: Optional[List[IntentNode]] = None,
        confidence_threshold: float = 0.7,
    ):
        self._tree = tree or []
        self._threshold = confidence_threshold
        self._index: Dict[str, IntentNode] = {}
        self._rebuild_index()

    def _rebuild_index(self):
        """重建节点索引（增删节点后调用）。"""
        self._index.clear()

        def _walk(nodes: List[IntentNode]):
            for node in nodes:
                self._index[node.intent_code] = node
                if node.children:
                    _walk(node.children)

        _walk(self._tree)

    def classify(self, user_input: str) -> Tuple[str, float]:
        """
        LLM 分类：返回 (intent_code, confidence)。

        解析格式：INTENT_CODE|CONFIDENCE
        如 "product-recommend|0.95" → ("product-recommend", 0.95)
        """
        prompt = load_prompt("intent-classifier", user_input=user_input)
        try:
            result = get_default_router().invoke(
                [HumanMessage(content=prompt)], tier="fast"
            )
            raw = (result.content or "").strip()
        except Exception as exc:
            logger.warning("意图分类 LLM 调用失败: %s", exc)
            return "none", 0.0

        match = re.match(r"^(\S+)\|([\d.]+)$", raw)
        if match:
            code = match.group(1).strip().lower()
            try:
                confidence = float(match.group(2))
                confidence = max(0.0, min(1.0, confidence))
            except ValueError:
                confidence = 0.0
            return code, confidence

        if raw in ("recommend", "analysis", "customer_service"):
            mapping = {
                "recommend": "product-recommend",
                "analysis": "analysis-sales",
                "customer_service": "after-sale",
            }
            return mapping.get(raw, "none"), 0.6

        logger.warning("意图分类解析失败，raw=%s", raw)
        return "none", 0.0

    def route(self, user_input: str) -> IntentRouteResult:
        """
        路由决策：输入 → 分类 → 树匹配 → 返回结果。

        Args:
            user_input: 用户输入

        Returns:
            IntentRouteResult 包含路由决策信息
        """
        code, confidence = self.classify(user_input)
        leaf_node = self._index.get(code)

        if leaf_node is None:
            return IntentRouteResult(
                intent_code="none",
                confidence=confidence,
                leaf_node=None,
                threshold=self._threshold,
            )

        return IntentRouteResult(
            intent_code=code,
            confidence=confidence,
            leaf_node=leaf_node,
            threshold=self._threshold,
        )

    def get_node(self, intent_code: str) -> Optional[IntentNode]:
        """按 code 获取节点。"""
        return self._index.get(intent_code)

    def get_leaves_by_kind(self, kind: IntentKind) -> List[IntentNode]:
        """获取指定类型的所有叶子节点。"""
        leaves: List[IntentNode] = []

        def _walk(nodes: List[IntentNode]):
            for node in nodes:
                if not node.children:
                    if node.kind == kind:
                        leaves.append(node)
                else:
                    _walk(node.children)

        _walk(self._tree)
        return leaves

    def list_nodes(self) -> List[dict]:
        """列出所有节点（展平为列表，用于管理端）。"""
        flat: List[dict] = []

        def _walk(nodes: List[IntentNode]):
            for node in nodes:
                flat.append(node.to_dict())
                if node.children:
                    _walk(node.children)

        _walk(self._tree)
        return flat



_default_router: Optional[IntentRouter] = None


def build_default_router() -> IntentRouter:
    """构建/获取默认意图路由器。"""
    global _default_router
    if _default_router is not None:
        return _default_router

    tree = load_intent_tree()
    if not tree:
        tree = _build_guagua_intent_tree()
        logger.info("使用内存意图树（%d 个根节点）", len(tree))

    _default_router = IntentRouter(
        tree=tree,
        confidence_threshold=float(
            getattr(settings, "INTENT_CONFIDENCE_THRESHOLD", 0.7)
        ),
    )
    logger.info("意图路由器已装配：%d 个节点，置信度阈值=%.1f",
                len(_default_router._index), _default_router._threshold)
    return _default_router


def reset_default_router():
    """重置默认路由器（用于测试/管理员刷新）。"""
    global _default_router
    _default_router = None