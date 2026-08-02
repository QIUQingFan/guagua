"""
查询预处理（问题重写 + 查询词映射）自测脚本

不依赖运行中的 DB / LLM：
- apply_mapping / _parse_rewrite_response / _format_history_for_rewrite 是纯函数，直接测
- normalize 通过 monkey-patch load_mappings 注入假规则，绕开 DB
- prepare_retrieval_query 在重写关闭 / LLM 故障时验证降级

运行：python -m query.selftest
"""
from __future__ import annotations

import query.rewrite as rewrite_mod
import query.term_mapping as tm_mod
from query.rewrite import (
    _format_history_for_rewrite,
    _parse_rewrite_response,
    prepare_retrieval_query,
)
from query.term_mapping import apply_mapping, normalize


class _Patch:
    """简易 monkey-patch 上下文管理器：记录 (obj, attr, old_value)，退出时还原。"""

    def __init__(self):
        self._saved = []

    def set(self, obj, attr, value):
        self._saved.append((obj, attr, getattr(obj, attr, None)))
        setattr(obj, attr, value)

    def restore(self):
        for obj, attr, old in self._saved:
            setattr(obj, attr, old)
        self._saved.clear()


def _patch_mappings(rules):
    """注入假映射规则（替代 DB 查询），返回 _Patch（用完调 .restore()）。"""
    p = _Patch()
    p.set(tm_mod, "load_mappings", lambda: rules)
    tm_mod._cache = {"mappings": rules, "loaded_at": float("inf")}
    return p


def _patch_rewrite_flags(enabled=True, tier="fast"):
    """临时覆盖重写开关与档位（直接 patch 函数，避免依赖 pydantic 字段声明）。返回 _Patch。"""
    p = _Patch()
    p.set(rewrite_mod, "_rewrite_enabled", lambda: enabled)
    p.set(rewrite_mod, "_rewrite_tier", lambda: tier)
    return p


def _patch_router_fail():
    """注入调用即抛异常的 mock 路由器，返回 _Patch。"""
    import model_router as mr

    class _FailRouter:
        def invoke(self, messages, tier="standard"):
            raise RuntimeError("模拟 LLM 故障")

    p = _Patch()
    p.set(mr, "get_default_router", lambda: _FailRouter())
    return p


def test_apply_mapping_basic():
    assert apply_mapping("买个蓝牙", "蓝牙", "蓝牙耳机") == "买个蓝牙耳机"
    print("[PASS] apply_mapping：基础替换")


def test_apply_mapping_already_target_skip():
    assert apply_mapping("蓝牙耳机降噪", "蓝牙", "蓝牙耳机") == "蓝牙耳机降噪"
    print("[PASS] apply_mapping：命中位置已是目标词时跳过（避免'蓝牙耳机耳机'）")


def test_apply_mapping_multiple_occurrences():
    assert apply_mapping("蓝牙和蓝牙耳机", "蓝牙", "蓝牙耳机") == "蓝牙耳机和蓝牙耳机"
    print("[PASS] apply_mapping：多处命中混合替换/跳过")


def test_apply_mapping_no_match():
    assert apply_mapping("买个鼠标", "蓝牙", "蓝牙耳机") == "买个鼠标"
    print("[PASS] apply_mapping：无命中原样返回")


def test_apply_mapping_empty_inputs():
    assert apply_mapping("", "蓝牙", "蓝牙耳机") == ""
    assert apply_mapping("蓝牙", "", "蓝牙耳机") == "蓝牙"
    assert apply_mapping("蓝牙", "蓝牙", "") == "蓝牙"
    assert apply_mapping(None, "蓝牙", "蓝牙耳机") is None
    print("[PASS] apply_mapping：空入参安全返回")


def test_normalize_multiple_rules():
    p = _patch_mappings([
        {"source_term": "耳机", "target_term": "蓝牙耳机", "priority": 100},
        {"source_term": "pad", "target_term": "平板电脑", "priority": 90},
    ])
    try:
        assert normalize("推荐个耳机") == "推荐个蓝牙耳机"
        assert normalize("买个pad") == "买个平板电脑"
    finally:
        p.restore()
    print("[PASS] normalize：多规则分别应用")


def test_normalize_long_term_first():
    p = _patch_mappings([
        {"source_term": "蓝牙耳机", "target_term": "无线蓝牙耳机", "priority": 100},
        {"source_term": "耳机", "target_term": "蓝牙耳机", "priority": 100},
    ])
    try:
        result = normalize("蓝牙耳机")
        assert "无线" in result, f"长词应先匹配，实际 {result}"
        assert "耳机耳机" not in result, f"不应出现重复，实际 {result}"
    finally:
        p.restore()
    print(f"[PASS] normalize：长词优先匹配")


def test_normalize_no_rules_passthrough():
    p = _patch_mappings([])
    try:
        assert normalize("原样返回") == "原样返回"
    finally:
        p.restore()
    print("[PASS] normalize：无规则原样返回")


def test_normalize_chain():
    p = _patch_mappings([
        {"source_term": "考研", "target_term": "考研复习资料", "priority": 100},
        {"source_term": "复习资料", "target_term": "真题复习资料", "priority": 90},
    ])
    try:
        result = normalize("考研")
        assert "真题" in result, f"链式替换应生效，实际 {result}"
    finally:
        p.restore()
    print(f"[PASS] normalize：链式替换（'考研' → '{result}'）")


def test_parse_clean_json():
    raw = '{"rewrite": "怎么申请退货", "should_split": false, "sub_questions": ["怎么申请退货"]}'
    assert _parse_rewrite_response(raw, "fallback") == "怎么申请退货"
    print("[PASS] parse：干净 JSON 解析")


def test_parse_markdown_fence():
    raw = '```json\n{"rewrite": "降噪耳机推荐", "should_split": false}\n```'
    assert _parse_rewrite_response(raw, "fallback") == "降噪耳机推荐"
    print("[PASS] parse：markdown 代码块标记去除")


def test_parse_embedded_json():
    raw = '好的，结果是：{"rewrite": "退货退款流程"} 以上。'
    assert _parse_rewrite_response(raw, "fallback") == "退货退款流程"
    print("[PASS] parse：正则提取嵌入 JSON")


def test_parse_empty_rewrite_fallback():
    raw = '{"rewrite": "", "should_split": false}'
    assert _parse_rewrite_response(raw, "归一化结果") == "归一化结果"
    print("[PASS] parse：rewrite 为空回退")


def test_parse_garbage_fallback():
    assert _parse_rewrite_response("这不是JSON", "fallback") == "fallback"
    assert _parse_rewrite_response("", "fallback") == "fallback"
    assert _parse_rewrite_response(None, "fallback") == "fallback"
    print("[PASS] parse：无法解析时回退")


def test_format_history_none():
    assert _format_history_for_rewrite(None) == "（无）"
    assert _format_history_for_rewrite([]) == "（无）"
    print("[PASS] format_history：空历史返回'（无）'")


def test_format_history_filters_system():
    history = [
        {"role": "system", "content": "[会话摘要] 用户在挑耳机"},
        {"role": "user", "content": "推荐个耳机"},
        {"role": "assistant", "content": "降噪耳机适合你"},
    ]
    text = _format_history_for_rewrite(history)
    assert "会话摘要" not in text
    assert "推荐个耳机" in text
    assert "降噪耳机" in text
    print("[PASS] format_history：过滤 system 摘要")


def test_format_history_truncates_to_4():
    history = [
        {"role": "user", "content": "第1轮问题"},
        {"role": "assistant", "content": "第1轮回答"},
        {"role": "user", "content": "第2轮问题"},
        {"role": "assistant", "content": "第2轮回答"},
        {"role": "user", "content": "第3轮问题"},
        {"role": "assistant", "content": "第3轮回答"},
    ]
    text = _format_history_for_rewrite(history)
    assert "第1轮" not in text
    assert "第3轮问题" in text and "第3轮回答" in text
    print("[PASS] format_history：截断到最近 2 轮")


def test_format_history_coreference():
    history = [
        {"role": "user", "content": "推荐个降噪耳机"},
        {"role": "assistant", "content": "推荐 Bose QC45"},
    ]
    text = _format_history_for_rewrite(history)
    assert "降噪耳机" in text
    print("[PASS] format_history：指代消解历史正确注入")


def test_prepare_query_rewrite_disabled():
    """QUERY_REWRITE_ENABLED=false 时只做术语归一化，不调 LLM"""
    p1 = _patch_rewrite_flags(enabled=False)
    p2 = _patch_mappings([{"source_term": "耳机", "target_term": "蓝牙耳机", "priority": 100}])
    try:
        result = prepare_retrieval_query("推荐个耳机", history=None)
        assert result == "推荐个蓝牙耳机", f"重写关闭时应只归一化，实际 {result}"
    finally:
        p2.restore()
        p1.restore()
    print("[PASS] prepare_retrieval_query：重写关闭时只做归一化")


def test_prepare_query_empty_input():
    assert prepare_retrieval_query("", None) == ""
    assert prepare_retrieval_query("   ", None) == "   "
    print("[PASS] prepare_retrieval_query：空入参原样返回")


def test_prepare_query_llm_fail_fallback():
    """LLM 调用失败时回退到归一化结果（降级安全）"""
    p1 = _patch_rewrite_flags(enabled=True, tier="fast")
    p2 = _patch_mappings([{"source_term": "耳机", "target_term": "蓝牙耳机", "priority": 100}])
    p3 = _patch_router_fail()
    try:
        result = prepare_retrieval_query("推荐个耳机", history=None)
        assert result == "推荐个蓝牙耳机", f"LLM 失败应回退归一化，实际 {result}"
    finally:
        p3.restore()
        p2.restore()
        p1.restore()
    print("[PASS] prepare_retrieval_query：LLM 失败回退归一化")


def main():
    print("=" * 60)
    print("查询预处理（问题重写 + 查询词映射）自测")
    print("=" * 60)

    test_apply_mapping_basic()
    test_apply_mapping_already_target_skip()
    test_apply_mapping_multiple_occurrences()
    test_apply_mapping_no_match()
    test_apply_mapping_empty_inputs()

    test_normalize_multiple_rules()
    test_normalize_long_term_first()
    test_normalize_no_rules_passthrough()
    test_normalize_chain()

    test_parse_clean_json()
    test_parse_markdown_fence()
    test_parse_embedded_json()
    test_parse_empty_rewrite_fallback()
    test_parse_garbage_fallback()

    test_format_history_none()
    test_format_history_filters_system()
    test_format_history_truncates_to_4()
    test_format_history_coreference()

    test_prepare_query_rewrite_disabled()
    test_prepare_query_empty_input()
    test_prepare_query_llm_fail_fallback()

    print("=" * 60)
    print("全部通过 ✅")
    print("=" * 60)


if __name__ == "__main__":
    main()
