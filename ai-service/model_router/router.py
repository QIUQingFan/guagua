"""
模型路由 + 首包探测
"""
from __future__ import annotations

import json
import logging
import threading
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from typing import Any, Dict, Generator, List, Optional

from langchain_core.messages import AIMessage
from langchain_openai import ChatOpenAI

from model_router.health_store import CircuitState, ModelHealthStore

logger = logging.getLogger("model_router")



class ModelCandidate:
    """单个模型候选"""

    def __init__(
        self,
        name: str,
        model: str,
        api_key: str,
        base_url: str,
        tier: str = "standard",
        priority: int = 1,
        temperature: float = 0.3,
        streaming: bool = False,
    ):
        self.name = name
        self.model = model
        self.api_key = api_key
        self.base_url = base_url
        self.tier = tier
        self.priority = priority
        self.temperature = temperature
        self.streaming = streaming
        self.chat_model = ChatOpenAI(
            model=model,
            openai_api_key=api_key,
            openai_api_base=base_url,
            temperature=temperature,
            streaming=streaming,
            stream_usage=streaming,
        )


class _FirstPacketTimeout(Exception):
    """首包探测超时（首个 token 未在 timeout 内到达）"""



class RoutingLLMService:
    """
    模型路由服务

    所有 LLM 调用的统一入口，提供候选 failover + 熔断保护 + 首包探测。
    """

    def __init__(
        self,
        candidates: List[ModelCandidate],
        health_store: ModelHealthStore,
        first_packet_timeout_ms: int = 8000,
        invoke_timeout_ms: int = 30000,
    ):
        self._candidates = candidates
        self._health = health_store
        for c in candidates:
            health_store.register(c.name)
        self._first_packet_timeout_s = first_packet_timeout_ms / 1000.0
        self._invoke_timeout_s = invoke_timeout_ms / 1000.0


    def _select_candidates(self, tier: str) -> List[ModelCandidate]:
        """
        按 tier 过滤 + priority 排序 + 跳过熔断中的候选。
        返回可调用的候选列表（已通过熔断器 allow_call 的）。
        注意：HALF_OPEN 候选的探测许可在此消耗，调用方必须回报结果。
        """
        tiered = [c for c in self._candidates if c.tier == tier]
        if not tiered:
            tiered = [c for c in self._candidates if c.tier == "standard"]
        tiered.sort(key=lambda c: c.priority)

        available = []
        for c in tiered:
            if self._health.allow_call(c.name):
                available.append(c)
        return available


    def invoke(self, messages: List[Any], tier: str = "standard") -> AIMessage:
        """
        同步调用
        按候选顺序尝试，失败即切下一候选；全部失败抛最后异常。
        """
        candidates = self._select_candidates(tier)
        if not candidates:
            logger.warning("无可用模型候选（全部熔断或未配置），返回空响应")
            return AIMessage(content="")

        last_error: Optional[Exception] = None
        for candidate in candidates:
            try:
                with ThreadPoolExecutor(max_workers=1, thread_name_prefix="llm-invoke") as ex:
                    future = ex.submit(candidate.chat_model.invoke, messages)
                    result = future.result(timeout=self._invoke_timeout_s)
                self._health.mark_success(candidate.name)
                return result
            except FutureTimeout:
                logger.warning("候选 %s invoke 超时(%ds)，切换下一候选",
                               candidate.name, self._invoke_timeout_s)
                self._health.mark_failure(candidate.name)
                last_error = TimeoutError(f"{candidate.name} invoke timeout")
            except Exception as exc:
                logger.warning("候选 %s invoke 失败: %s，切换下一候选", candidate.name, exc)
                self._health.mark_failure(candidate.name)
                last_error = exc

        logger.error("所有模型候选 invoke 均失败，最后错误: %s", last_error)
        if last_error:
            raise last_error
        return AIMessage(content="")


    def stream(self, messages: List[Any], tier: str = "standard") -> Generator[Any, None, None]:
        """
        流式调用（带首包探测 + failover）。
        """
        candidates = self._select_candidates(tier)
        if not candidates:
            logger.warning("无可用模型候选（全部熔断或未配置），流式返回空")
            yield ""
            return

        last_error: Optional[Exception] = None
        for candidate in candidates:
            try:
                chunk_iter = candidate.chat_model.stream(messages)

                first_chunk = self._probe_first_packet(chunk_iter, candidate)

                self._health.mark_success(candidate.name)
                yield first_chunk
                for chunk in chunk_iter:
                    yield chunk
                return

            except _FirstPacketTimeout:
                logger.warning("候选 %s 首包超时(%dms)，切换下一候选",
                               candidate.name, int(self._first_packet_timeout_s * 1000))
                self._health.mark_failure(candidate.name)
                last_error = TimeoutError(f"{candidate.name} first-packet timeout")
            except Exception as exc:
                logger.warning("候选 %s 流式失败: %s，切换下一候选", candidate.name, exc)
                self._health.mark_failure(candidate.name)
                last_error = exc

        logger.error("所有模型候选流式均失败，最后错误: %s", last_error)
        yield ""

    def _probe_first_packet(self, chunk_iter: Generator, candidate: ModelCandidate):
        """
        首包探测：在独立线程拉取第一个 chunk，超时即抛 _FirstPacketTimeout。

        用临时 executor（每次新建）而非共享池：卡住的探测不会阻塞下一候选的探测。
        超时后底层 HTTP 连接仍会阻塞到 socket 超时（无法强制中断），但主流程已切候选，
        不影响用户感知；卡住的线程随 socket 超时自然回收。
        """
        with ThreadPoolExecutor(max_workers=1, thread_name_prefix="llm-probe") as ex:
            future = ex.submit(self._next_chunk, chunk_iter)
            try:
                chunk = future.result(timeout=self._first_packet_timeout_s)
                if chunk is None:
                    raise _FirstPacketTimeout(f"{candidate.name} returned empty stream")
                return chunk
            except FutureTimeout:
                raise _FirstPacketTimeout(
                    f"{candidate.name} first-packet timeout ({int(self._first_packet_timeout_s*1000)}ms)"
                )

    @staticmethod
    def _next_chunk(chunk_iter: Generator):
        """安全取下一个 chunk，迭代结束返回 None"""
        try:
            return next(chunk_iter)
        except StopIteration:
            return None


    def health_snapshot(self) -> list:
        """全部候选健康状态快照（供管理端接口）"""
        return self._health.snapshot()

    def candidates_info(self) -> list:
        """候选配置信息（脱敏，不含 api_key）"""
        return [
            {"name": c.name, "model": c.model, "tier": c.tier,
             "priority": c.priority, "base_url": c.base_url}
            for c in self._candidates
        ]



_default_router: Optional[RoutingLLMService] = None
_router_lock = threading.Lock()


def _build_candidates_from_config() -> List[ModelCandidate]:
    """从 config 装配候选列表（LLM_CANDIDATES 优先，为空则用 OPENAI_* 单候选兜底）"""
    from config import settings

    raw = getattr(settings, "LLM_CANDIDATES", "") or ""
    if raw.strip():
        try:
            items = json.loads(raw)
        except Exception as exc:
            raise ValueError(f"LLM_CANDIDATES JSON 解析失败: {exc}")
        candidates = []
        for it in items:
            candidates.append(ModelCandidate(
                name=it["name"],
                model=it["model"],
                api_key=it["api_key"],
                base_url=it["base_url"],
                tier=it.get("tier", "standard"),
                priority=int(it.get("priority", len(candidates) + 1)),
                temperature=float(it.get("temperature", 0.3)),
            ))
        if not candidates:
            raise ValueError("LLM_CANDIDATES 为空数组，至少需要 1 个候选")
        return candidates

    return [ModelCandidate(
        name=f"{settings.OPENAI_MODEL}",
        model=settings.OPENAI_MODEL,
        api_key=settings.OPENAI_API_KEY,
        base_url=settings.OPENAI_BASE_URL,
        tier="standard",
        priority=1,
        temperature=0.3,
    )]


def build_default_router() -> RoutingLLMService:
    """装配默认路由器（按 config，线程安全单例）"""
    global _default_router
    if _default_router is not None:
        return _default_router
    with _router_lock:
        if _default_router is not None:
            return _default_router
        from config import settings
        candidates = _build_candidates_from_config()
        health_store = ModelHealthStore(
            failure_threshold=getattr(settings, "LLM_FAILURE_THRESHOLD", 2),
            open_duration_ms=getattr(settings, "LLM_OPEN_DURATION_MS", 30000),
        )
        _default_router = RoutingLLMService(
            candidates=candidates,
            health_store=health_store,
            first_packet_timeout_ms=getattr(settings, "LLM_FIRST_PACKET_TIMEOUT_MS", 8000),
            invoke_timeout_ms=getattr(settings, "LLM_INVOKE_TIMEOUT_MS", 30000),
        )
        logger.info(
            "模型路由器已装配 - 候选数:%d, 首包超时:%dms, invoke超时:%dms, 熔断阈值:%d, OPEN冷却:%dms",
            len(candidates),
            _default_router._first_packet_timeout_s * 1000,
            _default_router._invoke_timeout_s * 1000,
            health_store.failure_threshold,
            health_store.open_duration_ms,
        )
        return _default_router


def get_default_router() -> RoutingLLMService:
    """获取默认路由器（未装配则自动装配）"""
    if _default_router is None:
        return build_default_router()
    return _default_router
