"""
Prompt 体系自测脚本

运行：python -m prompts.selftest
"""
from __future__ import annotations

from prompts import list_templates, load_prompt


def test_all_templates_loadable():
    """所有 .st 模板文件都能被加载"""
    names = list_templates()
    assert len(names) >= 17, f"模板数应 ≥17，实际 {len(names)}"
    for name in names:
        raw = load_prompt(name)
        assert isinstance(raw, str) and len(raw) > 0, f"模板 {name} 内容为空"
    print(f"[PASS] 全部 {len(names)} 个模板可加载: {names}")


def test_static_templates_no_vars():
    """无变量模板直接加载，不应报错"""
    for name in ["agent-recommend", "agent-analysis", "agent-customer-service", "answer-citation-rules"]:
        text = load_prompt(name)
        assert len(text) > 50, f"模板 {name} 内容异常（过短）"
    print("[PASS] 静态模板（无变量）加载正常")


def test_intent_classifier_render():
    """intent-classifier 渲染后含用户输入"""
    rendered = load_prompt("intent-classifier", user_input="推荐个耳机")
    assert "推荐个耳机" in rendered
    assert "product-recommend" in rendered and "after-sale-refund" in rendered
    print("[PASS] intent-classifier 渲染正确（含 user_input 与意图树节点定义）")


def test_task_decomposition_render():
    """task-decomposition 渲染后含查询，且 JSON 示例的 {{ }} 正确转义为 { }"""
    rendered = load_prompt("task-decomposition", task_description="推荐耳机并看销量")
    assert "推荐耳机并看销量" in rendered
    assert '"tasks"' in rendered and rendered.count('"tasks"') >= 1
    assert "{{" not in rendered, "JSON 示例的 {{ }} 未正确转义为 { }"
    print("[PASS] task-decomposition 渲染正确（含查询，JSON 示例转义正确）")


def test_stream_templates_render():
    """stream-* 模板变量正确注入"""
    r = load_prompt("stream-analysis", snapshot="订单:100, 营收:5000")
    assert "订单:100, 营收:5000" in r
    r = load_prompt("stream-recommend", sections="[热销]商品A", action_guidance="")
    assert "[热销]商品A" in r
    r = load_prompt("stream-cs-product", products_text="商品B", action_guidance="")
    assert "商品B" in r
    r = load_prompt("stream-cs-knowledge", context="FAQ内容", order_hint="", action_guidance="")
    assert "FAQ内容" in r
    print("[PASS] stream-* 四个模板渲染正确")


def test_fallback_templates_render():
    """fallback-* 模板变量正确注入"""
    r = load_prompt("fallback-customer-service", user_input="退款流程", context="7天无理由")
    assert "退款流程" in r and "7天无理由" in r
    r = load_prompt("fallback-recommend", user_input="耳机", hot_text="1. 蓝牙耳机")
    assert "耳机" in r and "1. 蓝牙耳机" in r
    r = load_prompt("fallback-analysis", user_input="销量", snapshot="订单:100")
    assert "销量" in r and "订单:100" in r
    print("[PASS] fallback-* 三个模板渲染正确")


def test_aux_templates_render():
    """辅助模板（摘要/标题/推荐追问/改写）变量正确注入"""
    r = load_prompt("conversation-summary", summary_max_chars=400, content="用户:退货\n助手:已处理")
    assert "400" in r and "用户:退货" in r
    r = load_prompt("conversation-title", title_max_chars=30, question="耳机推荐")
    assert "30" in r and "耳机推荐" in r
    r = load_prompt("recommended-questions", count=3, chunks="片段A", question="耳机", answer="推荐X")
    assert "3" in r and "片段A" in r and "耳机" in r
    r = load_prompt("user-question-rewrite", question="它多少钱", history="用户:耳机\n助手:已推荐")
    assert "它多少钱" in r
    print("[PASS] 辅助模板（摘要/标题/追问/改写）渲染正确")


def test_template_cache_works():
    """模板缓存生效：重复加载返回同一对象"""
    from prompts.loader import _TEMPLATE_CACHE
    _TEMPLATE_CACHE.clear()
    load_prompt("agent-recommend")
    assert "agent-recommend" in _TEMPLATE_CACHE
    load_prompt("agent-recommend")
    print("[PASS] 模板缓存生效（首次读取后常驻内存）")


def test_hard_constraints_preserved():
    """项目硬约束：system_content 必须告知下单能力，禁止引导去商城页面下单"""
    cs_prompt = load_prompt("agent-customer-service")
    assert "下单" in cs_prompt, "客服 prompt 应提及下单能力"
    assert "禁止引导" in cs_prompt and "商城页面" in cs_prompt, "客服 prompt 应禁止引导去商城页面"
    recommend_prompt = load_prompt("agent-recommend")
    assert "buy_now" in recommend_prompt or "立即购买" in recommend_prompt, "推荐 prompt 应支持 buy_now"
    print("[PASS] 项目硬约束保留（下单能力话术 + 禁止引导商城页面）")


def main():
    print("=" * 60)
    print("Prompt 体系自测")
    print("=" * 60)
    test_all_templates_loadable()
    test_static_templates_no_vars()
    test_intent_classifier_render()
    test_task_decomposition_render()
    test_stream_templates_render()
    test_fallback_templates_render()
    test_aux_templates_render()
    test_template_cache_works()
    test_hard_constraints_preserved()
    print("=" * 60)
    print("全部通过 ✅")
    print("=" * 60)


if __name__ == "__main__":
    main()
