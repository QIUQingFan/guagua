"""
模型路由 + 三态熔断 + 首包探测 自测脚本（不依赖真实 LLM API 与 DB）

用 mock 候选验证：
1. 熔断器状态机全路径（CLOSED→OPEN→HALF_OPEN→CLOSED/OPEN）
2. 路由 failover（主候选失败切备选）
3. 首包探测（首个 token 超时即切候选）
4. tier 过滤与 priority 排序

运行：python -m model_router.selftest
"""
from __future__ import annotations

import time
from typing import List
from unittest.mock import MagicMock

from langchain_core.messages import AIMessage

from model_router.health_store import CircuitState, ModelHealth, ModelHealthStore
from model_router.router import ModelCandidate, RoutingLLMService



def _make_candidate(name: str, tier: str = "standard", priority: int = 1) -> ModelCandidate:
    """构造 mock 候选（不真实连 API，chat_model 为 MagicMock）"""
    c = ModelCandidate(
        name=name, model=f"mock-{name}", api_key="sk-mock",
        base_url="http://mock", tier=tier, priority=priority,
    )
    c.chat_model = MagicMock()
    return c



def test_circuit_breaker_closed_to_open():
    """CLOSED 状态连续失败达阈值 → 转 OPEN"""
    h = ModelHealth("m1", failure_threshold=2, open_duration_ms=30000)
    assert h.state == CircuitState.CLOSED

    h.mark_failure()
    assert h.state == CircuitState.CLOSED, "1 次失败不应熔断"
    assert h.allow_call() is True

    h.mark_failure()
    assert h.state == CircuitState.OPEN, "达阈值应转 OPEN"
    assert h.allow_call() is False, "OPEN 期内应拒绝"
    print("[PASS] 熔断：CLOSED 连续失败达阈值 → OPEN，OPEN 期内拒绝调用")


def test_circuit_breaker_open_to_half_open():
    """OPEN 到期 → 转 HALF_OPEN 并放行一个探测"""
    h = ModelHealth("m2", failure_threshold=1, open_duration_ms=50)
    h.mark_failure()
    assert h.state == CircuitState.OPEN

    time.sleep(0.06)
    assert h.allow_call() is True, "OPEN 过期应放行探测"
    assert h.state == CircuitState.HALF_OPEN, "应转 HALF_OPEN"
    assert h.allow_call() is False, "HALF_OPEN 期间仅放行 1 个探测"
    print("[PASS] 熔断：OPEN 到期 → HALF_OPEN，仅放行 1 个探测")


def test_circuit_breaker_half_open_success():
    """HALF_OPEN 探测成功 → 回到 CLOSED"""
    h = ModelHealth("m3", failure_threshold=1, open_duration_ms=50)
    h.mark_failure()
    time.sleep(0.06)
    h.allow_call()
    assert h.state == CircuitState.HALF_OPEN

    h.mark_success()
    assert h.state == CircuitState.CLOSED, "探测成功应回 CLOSED"
    assert h.consecutive_failures == 0
    assert h.allow_call() is True
    print("[PASS] 熔断：HALF_OPEN 探测成功 → CLOSED（模型恢复）")


def test_circuit_breaker_half_open_failure():
    """HALF_OPEN 探测失败 → 重新 OPEN"""
    h = ModelHealth("m4", failure_threshold=1, open_duration_ms=30000)
    h.mark_failure()
    time.sleep(0.01)
    h.state = CircuitState.HALF_OPEN
    h.half_open_in_flight = True

    h.mark_failure()
    assert h.state == CircuitState.OPEN, "探测失败应重新 OPEN"
    assert h.half_open_in_flight is False
    print("[PASS] 熔断：HALF_OPEN 探测失败 → 重新 OPEN")


def test_health_store_registry():
    """ModelHealthStore 注册与查询幂等"""
    store = ModelHealthStore(failure_threshold=3, open_duration_ms=10000)
    h1 = store.register("m1")
    h2 = store.get("m1")
    assert h1 is h2, "重复注册应返回同一实例"
    assert len(store.snapshot()) == 1
    store.mark_success("m1")
    assert h1.state == CircuitState.CLOSED
    print("[PASS] 健康注册表：注册幂等，状态查询正常")



def test_invoke_failover():
    """主候选 invoke 抛异常 → 自动切备候选"""
    primary = _make_candidate("primary")
    backup = _make_candidate("backup")
    primary.chat_model.invoke.side_effect = RuntimeError("primary down")
    backup.chat_model.invoke.return_value = AIMessage(content="from backup")

    store = ModelHealthStore(failure_threshold=2, open_duration_ms=30000)
    router = RoutingLLMService(
        candidates=[primary, backup], health_store=store,
        first_packet_timeout_ms=1000, invoke_timeout_ms=2000,
    )
    result = router.invoke([])
    assert result.content == "from backup", f"应切到 backup，实际 {result.content}"
    assert store.get("primary").state == CircuitState.OPEN or \
           store.get("primary").consecutive_failures >= 1
    assert store.get("backup").state == CircuitState.CLOSED
    print("[PASS] 路由：invoke 主候选失败自动切备候选")


def test_invoke_all_fail():
    """所有候选都失败 → 抛最后异常"""
    c1 = _make_candidate("c1")
    c2 = _make_candidate("c2")
    c1.chat_model.invoke.side_effect = RuntimeError("c1 down")
    c2.chat_model.invoke.side_effect = RuntimeError("c2 down")

    store = ModelHealthStore(failure_threshold=5, open_duration_ms=30000)
    router = RoutingLLMService([c1, c2], store, 1000, 2000)
    try:
        router.invoke([])
        raise AssertionError("应抛异常")
    except RuntimeError as e:
        assert "c2" in str(e), f"应保留最后错误，实际 {e}"
    print("[PASS] 路由：所有候选失败抛最后异常")


def test_invoke_skip_open_candidate():
    """OPEN 候选直接跳过（不消耗配额）"""
    primary = _make_candidate("primary")
    backup = _make_candidate("backup")
    store = ModelHealthStore(failure_threshold=1, open_duration_ms=30000)
    store.register("primary")
    store.mark_failure("primary")
    assert store.get("primary").state == CircuitState.OPEN

    primary.chat_model.invoke.side_effect = RuntimeError("should not be called")
    backup.chat_model.invoke.return_value = AIMessage(content="from backup")

    router = RoutingLLMService([primary, backup], store, 1000, 2000)
    result = router.invoke([])
    assert result.content == "from backup"
    primary.chat_model.invoke.assert_not_called()
    print("[PASS] 路由：OPEN 候选直接跳过，不消耗 API 配额")



def test_stream_first_packet_failover():
    """首包超时 → 切下一候选，最终拿到正常流"""
    slow = _make_candidate("slow")
    fast = _make_candidate("fast")

    def slow_stream(_msgs):
        yield from _blocking_iter()

    def fast_stream(_msgs):
        yield AIMessageChunkLike("hello")
        yield AIMessageChunkLike(" world")

    slow.chat_model.stream.side_effect = slow_stream
    fast.chat_model.stream.side_effect = fast_stream

    store = ModelHealthStore(failure_threshold=2, open_duration_ms=30000)
    router = RoutingLLMService(
        candidates=[slow, fast], health_store=store,
        first_packet_timeout_ms=200,
        invoke_timeout_ms=2000,
    )

    chunks = []
    for c in router.stream([]):
        if hasattr(c, "content") and c.content:
            chunks.append(c.content)
    assert "".join(chunks) == "hello world", f"应从 fast 候选拿到完整流，实际 {''.join(chunks)}"
    assert store.get("slow").consecutive_failures >= 1
    print("[PASS] 首包探测：slow 候选首包超时 → 自动切 fast 候选")


def test_stream_success_no_failover():
    """首包正常到达 → 不切换，直接排空"""
    primary = _make_candidate("primary")
    primary.chat_model.stream.side_effect = lambda _: iter([
        AIMessageChunkLike("a"), AIMessageChunkLike("b"), AIMessageChunkLike("c"),
    ])
    store = ModelHealthStore(failure_threshold=2, open_duration_ms=30000)
    router = RoutingLLMService([primary], store, 1000, 2000)

    chunks = []
    for c in router.stream([]):
        if hasattr(c, "content") and c.content:
            chunks.append(c.content)
    assert chunks == ["a", "b", "c"], f"应排空所有 chunk，实际 {chunks}"
    assert store.get("primary").state == CircuitState.CLOSED
    print("[PASS] 首包探测：首包正常到达 → mark_success，排空剩余")



def test_tier_filter_and_priority():
    """tier 过滤 + priority 排序：standard tier 不含 fast/deep 候选"""
    fast = _make_candidate("fast", tier="fast", priority=1)
    std1 = _make_candidate("std1", tier="standard", priority=2)
    std2 = _make_candidate("std2", tier="standard", priority=1)
    deep = _make_candidate("deep", tier="deep", priority=1)

    store = ModelHealthStore(failure_threshold=2, open_duration_ms=30000)
    router = RoutingLLMService([fast, std1, std2, deep], store, 1000, 2000)

    selected = router._select_candidates("standard")
    names = [c.name for c in selected]
    assert names == ["std2", "std1"], f"standard tier 应按 priority 排序，实际 {names}"
    print(f"[PASS] tier 过滤：standard 候选 = {names}（按 priority 排序）")


def test_tier_fallback_to_standard():
    """请求 fast tier 但无 fast 候选 → 回退到 standard"""
    std = _make_candidate("std", tier="standard", priority=1)
    store = ModelHealthStore(failure_threshold=2, open_duration_ms=30000)
    router = RoutingLLMService([std], store, 1000, 2000)

    selected = router._select_candidates("fast")
    assert len(selected) == 1 and selected[0].name == "std", "无 fast 候选应回退 standard"
    print("[PASS] tier 回退：请求 fast 但无候选 → 回退 standard")



class AIMessageChunkLike:
    """模拟 LangChain stream chunk（只需 .content 属性）"""
    def __init__(self, content: str):
        self.content = content


def _blocking_iter():
    """模拟首包阻塞：yield 前睡眠很久"""
    time.sleep(5)
    yield AIMessageChunkLike("never")


def main():
    print("=" * 60)
    print("模型路由 + 三态熔断 + 首包探测 自测")
    print("=" * 60)
    test_circuit_breaker_closed_to_open()
    test_circuit_breaker_open_to_half_open()
    test_circuit_breaker_half_open_success()
    test_circuit_breaker_half_open_failure()
    test_health_store_registry()
    test_invoke_failover()
    test_invoke_all_fail()
    test_invoke_skip_open_candidate()
    test_stream_first_packet_failover()
    test_stream_success_no_failover()
    test_tier_filter_and_priority()
    test_tier_fallback_to_standard()
    print("=" * 60)
    print("全部通过 ✅")
    print("=" * 60)


if __name__ == "__main__":
    main()
