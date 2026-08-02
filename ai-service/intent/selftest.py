"""
意图树 + 多知识库路由 + MCP 工具发现 自测脚本

运行：python -m intent.selftest
"""
from __future__ import annotations

import json
from unittest.mock import AsyncMock, MagicMock, patch

from intent.models import (
    IntentKind,
    IntentLevel,
    IntentNode,
    _build_guagua_intent_tree,
    _fill_full_path,
)
from intent.intent_router import IntentRouter, IntentRouteResult


def _make_test_tree() -> list:
    """构建测试用意图树。"""
    root = IntentNode(
        intent_code="product",
        name="商品咨询",
        level=IntentLevel.DOMAIN,
        kind=IntentKind.KB,
        collection_name="products",
        sort_order=1,
    )
    child = IntentNode(
        intent_code="product-recommend",
        name="商品推荐",
        level=IntentLevel.CATEGORY,
        parent_code="product",
        kind=IntentKind.KB,
        collection_name="products",
        examples=["推荐个耳机", "有什么好东西"],
        sort_order=1,
    )
    child2 = IntentNode(
        intent_code="product-price",
        name="价格库存",
        level=IntentLevel.CATEGORY,
        parent_code="product",
        kind=IntentKind.KB,
        collection_name="products",
        examples=["多少钱", "还有货吗"],
        sort_order=2,
    )
    root.set_children([child, child2])
    _fill_full_path([root], None)
    return [root]


def test_intent_tree_structure():
    """意图树构建正确：三级结构（DOMAIN→CATEGORY→TOPIC）"""
    roots = _build_guagua_intent_tree()
    assert len(roots) == 5, f"应 5 个根节点，实际 {len(roots)}"
    def _walk(nodes, depth=0):
        for node in nodes:
            assert node.level.value == depth, f"{node.intent_code} 层级应为 {depth}，实际 {node.level.value}"
            if node.children:
                _walk(node.children, depth + 1)
    _walk(roots, 0)
    print(f"[PASS] 意图树构建：{len(roots)} 个根节点，层级正确")


def test_intent_node_fields():
    """IntentNode 字段完整"""
    node = IntentNode(
        intent_code="test",
        name="测试",
        level=IntentLevel.TOPIC,
        kind=IntentKind.KB,
        collection_name="test_collection",
        examples=["测试问题"],
        description="测试描述",
        sort_order=1,
    )
    d = node.to_dict()
    assert d["intent_code"] == "test"
    assert d["level"] == 2
    assert d["kind"] == 0
    assert d["collection_name"] == "test_collection"
    print("[PASS] IntentNode 字段完整")


def test_intent_router_classify():
    """IntentRouter.classify 解析 LLM 输出格式"""
    router = IntentRouter(tree=_make_test_tree())

    with patch("intent.intent_router.get_default_router") as mock_router:
        mock_llm = MagicMock()
        mock_llm.invoke.return_value.content = "product-recommend|0.95"
        mock_router.return_value = mock_llm

        code, confidence = router.classify("推荐个耳机")
        assert code == "product-recommend"
        assert confidence == 0.95
        print(f"[PASS] classify 解析：{code}|{confidence}")


def test_intent_router_classify_old_format():
    """IntentRouter.classify 兼容旧格式（recommend/analysis/customer_service）"""
    router = IntentRouter(tree=_make_test_tree())

    with patch("intent.intent_router.get_default_router") as mock_router:
        mock_llm = MagicMock()
        mock_llm.invoke.return_value.content = "recommend"
        mock_router.return_value = mock_llm

        code, confidence = router.classify("推荐个耳机")
        assert code == "product-recommend", f"应映射到 product-recommend，实际 {code}"
        print(f"[PASS] classify 兼容旧格式：{code}")


def test_intent_router_classify_fallback():
    """IntentRouter.classify LLM 失败时返回 none|0.0"""
    router = IntentRouter(tree=_make_test_tree())

    with patch("intent.intent_router.get_default_router") as mock_router:
        mock_llm = MagicMock()
        mock_llm.invoke.side_effect = Exception("LLM 故障")
        mock_router.return_value = mock_llm

        code, confidence = router.classify("测试")
        assert code == "none"
        assert confidence == 0.0
        print("[PASS] classify LLM 故障回退 none|0.0")


def test_intent_route_high_confidence():
    """高置信度时 is_high_confidence=True"""
    router = IntentRouter(tree=_make_test_tree(), confidence_threshold=0.7)

    with patch("intent.intent_router.get_default_router") as mock_router:
        mock_llm = MagicMock()
        mock_llm.invoke.return_value.content = "product-recommend|0.95"
        mock_router.return_value = mock_llm

        result = router.route("推荐个耳机")
        assert result.is_high_confidence is True
        assert result.intent_code == "product-recommend"
        assert result.kind == IntentKind.KB
        assert result.collection_name == "products"
        print(f"[PASS] 高置信度路由：{result}")


def test_intent_route_low_confidence():
    """低置信度时 is_high_confidence=False"""
    router = IntentRouter(tree=_make_test_tree(), confidence_threshold=0.7)

    with patch("intent.intent_router.get_default_router") as mock_router:
        mock_llm = MagicMock()
        mock_llm.invoke.return_value.content = "product-recommend|0.50"
        mock_router.return_value = mock_llm

        result = router.route("推荐个耳机")
        assert result.is_high_confidence is False
        print(f"[PASS] 低置信度路由：{result}")


def test_intent_route_none():
    """无法匹配时返回 none"""
    router = IntentRouter(tree=_make_test_tree())

    with patch("intent.intent_router.get_default_router") as mock_router:
        mock_llm = MagicMock()
        mock_llm.invoke.return_value.content = "none|0.0"
        mock_router.return_value = mock_llm

        result = router.route("不知道")
        assert result.intent_code == "none"
        assert result.leaf_node is None
        assert result.is_high_confidence is False
        print(f"[PASS] 无法匹配路由：{result}")


def test_intent_route_system():
    """系统交互节点 is_system=True"""
    router = IntentRouter(tree=_make_test_tree())

    sys_node = IntentNode(
        intent_code="sys-welcome",
        name="欢迎与问候",
        level=IntentLevel.CATEGORY,
        kind=IntentKind.SYSTEM,
    )
    router._index["sys-welcome"] = sys_node

    with patch("intent.intent_router.get_default_router") as mock_router:
        mock_llm = MagicMock()
        mock_llm.invoke.return_value.content = "sys-welcome|0.99"
        mock_router.return_value = mock_llm

        result = router.route("你好")
        assert result.is_system is True
        assert result.kind == IntentKind.SYSTEM
        print(f"[PASS] 系统交互路由：{result}")


def test_get_leaves_by_kind():
    """get_leaves_by_kind 按类型过滤"""
    router = IntentRouter(tree=_make_test_tree())
    leaves = router.get_leaves_by_kind(IntentKind.KB)
    assert len(leaves) > 0
    for leaf in leaves:
        assert leaf.kind == IntentKind.KB
        assert not leaf.children
    print(f"[PASS] get_leaves_by_kind：{len(leaves)} 个 KB 叶子")


def test_list_nodes():
    """list_nodes 返回展平列表"""
    router = IntentRouter(tree=_make_test_tree())
    nodes = router.list_nodes()
    assert len(nodes) > 0
    for n in nodes:
        assert "intent_code" in n
        assert "name" in n
        assert "full_path" in n
    print(f"[PASS] list_nodes：{len(nodes)} 个节点")


def test_intent_route_result_high_confidence():
    """IntentRouteResult 高置信度"""
    node = IntentNode(
        intent_code="test", name="测试", level=IntentLevel.TOPIC,
        kind=IntentKind.KB, collection_name="test",
    )
    result = IntentRouteResult("test", 0.85, leaf_node=node, threshold=0.7)
    assert result.is_high_confidence is True
    assert result.collection_name == "test"
    assert result.kind == IntentKind.KB
    print("[PASS] IntentRouteResult 高置信度")


def test_intent_route_result_no_leaf():
    """IntentRouteResult 无叶子节点"""
    result = IntentRouteResult("none", 0.0, leaf_node=None, threshold=0.7)
    assert result.is_high_confidence is False
    assert result.is_system is False
    assert result.is_mcp is False
    assert result.collection_name == ""
    print("[PASS] IntentRouteResult 无叶子节点")


def test_mcp_tool_def():
    """MCP ToolDef 基本功能"""
    from mcp_tools import ToolDef, ToolParam
    tool = ToolDef(
        name="search_products",
        description="搜索商品",
        parameters=[
            ToolParam(name="query", type="string", description="关键词", required=True),
            ToolParam(name="limit", type="integer", description="数量", required=False, default=5),
        ],
    )
    schema = tool.to_openai_schema()
    assert schema["function"]["name"] == "search_products"
    assert "query" in schema["function"]["parameters"]["properties"]
    assert "limit" in schema["function"]["parameters"]["properties"]
    mcp = tool.to_mcp_tool()
    assert mcp["name"] == "search_products"
    assert "inputSchema" in mcp
    print("[PASS] MCP ToolDef 基本功能")


def test_mcp_tool_registry():
    """MCP ToolRegistry 基本功能"""
    from mcp_tools import McpToolRegistry, ToolExecutor
    registry = McpToolRegistry()

    def dummy_fn(query: str = "") -> str:
        return f"result: {query}"

    executor = ToolExecutor(
        tool_id="test-tool",
        name="test_tool",
        description="测试工具",
        fn=dummy_fn,
        parameters=[],
    )
    registry.register(executor)
    assert registry.size() == 1
    assert registry.contains("test-tool")
    assert registry.get_executor("test-tool") is not None
    tools = registry.list_all_tools()
    assert len(tools) == 1
    assert tools[0].name == "test_tool"
    registry.unregister("test-tool")
    assert registry.size() == 0
    print("[PASS] MCP ToolRegistry 基本功能")


def test_mcp_tool_validate_params():
    """MCP 参数校验"""
    from mcp_tools import McpToolRegistry, ToolExecutor, ToolParam
    registry = McpToolRegistry()

    def dummy_fn(query: str = "", limit: int = 5) -> str:
        return "ok"

    executor = ToolExecutor(
        tool_id="search",
        name="search_products",
        description="搜索",
        fn=dummy_fn,
        parameters=[
            ToolParam(name="query", type="string", description="关键词", required=True),
            ToolParam(name="limit", type="integer", description="数量", required=False, default=5),
        ],
    )
    registry.register(executor)
    assert registry.validate_params("search", {"query": "耳机"}) == []
    errors = registry.validate_params("search", {})
    assert len(errors) == 1
    assert "缺少必填参数" in errors[0]
    errors = registry.validate_params("nonexist", {})
    assert len(errors) == 1
    assert "未注册" in errors[0]
    print("[PASS] MCP 参数校验")


def test_prompt_loaded():
    """intent-classifier.st 和 mcp-parameter-extract.st 模板存在且可渲染"""
    from prompts import load_prompt
    classifier = load_prompt("intent-classifier", user_input="测试")
    assert "product-recommend" in classifier
    mcp = load_prompt("mcp-parameter-extract", tool_definition="{}", user_query="测试")
    assert "工具定义" in mcp
    print("[PASS] Prompt 模板加载正常")


def test_ensure_intent_tables():
    """ensure_intent_tables 幂等执行"""
    from intent.models import ensure_intent_tables
    ensure_intent_tables()
    print("[PASS] ensure_intent_tables 幂等执行")


def main():
    print("=" * 60)
    print("意图树 + 多知识库路由 + MCP 工具发现 自测")
    print("=" * 60)
    test_intent_tree_structure()
    test_intent_node_fields()
    test_intent_router_classify()
    test_intent_router_classify_old_format()
    test_intent_router_classify_fallback()
    test_intent_route_high_confidence()
    test_intent_route_low_confidence()
    test_intent_route_none()
    test_intent_route_system()
    test_get_leaves_by_kind()
    test_list_nodes()
    test_intent_route_result_high_confidence()
    test_intent_route_result_no_leaf()
    test_mcp_tool_def()
    test_mcp_tool_registry()
    test_mcp_tool_validate_params()
    test_prompt_loaded()
    test_ensure_intent_tables()
    print("=" * 60)
    print("全部通过 ✅")
    print("=" * 60)


if __name__ == "__main__":
    main()