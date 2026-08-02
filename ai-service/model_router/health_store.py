"""
三态熔断器
"""
from __future__ import annotations

import threading
import time
from enum import Enum
from typing import Dict


class CircuitState(Enum):
    """熔断器三态"""
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


class ModelHealth:
    """单个模型候选的健康状态"""

    def __init__(
        self,
        name: str,
        failure_threshold: int = 2,
        open_duration_ms: int = 30000,
    ):
        self.name = name
        self.state = CircuitState.CLOSED
        self.consecutive_failures = 0
        self.open_until = 0.0
        self.half_open_in_flight = False
        self.failure_threshold = failure_threshold
        self.open_duration_ms = open_duration_ms
        self._lock = threading.Lock()

    def allow_call(self) -> bool:
        """
        判定是否允许调用。HALF_OPEN 转换与放行在此原子完成。
        返回 True 表示获得调用许可（调用方随后必须调 mark_success / mark_failure 回报结果）。
        """
        now = time.time() * 1000
        with self._lock:
            if self.state == CircuitState.OPEN:
                if self.open_until > now:
                    return False
                self.state = CircuitState.HALF_OPEN
                self.half_open_in_flight = True
                return True

            if self.state == CircuitState.HALF_OPEN:
                if self.half_open_in_flight:
                    return False
                self.half_open_in_flight = True
                return True

            return True

    def mark_success(self):
        """调用成功：无论何种状态，都回到 CLOSED（模型已恢复）"""
        with self._lock:
            self.state = CircuitState.CLOSED
            self.consecutive_failures = 0
            self.open_until = 0.0
            self.half_open_in_flight = False

    def mark_failure(self):
        """调用失败：累计计数，达阈值转 OPEN；HALF_OPEN 探测失败立即转 OPEN"""
        now = time.time() * 1000
        with self._lock:
            if self.state == CircuitState.HALF_OPEN:
                self.state = CircuitState.OPEN
                self.open_until = now + self.open_duration_ms
                self.half_open_in_flight = False
                return

            self.consecutive_failures += 1
            if self.consecutive_failures >= self.failure_threshold:
                self.state = CircuitState.OPEN
                self.open_until = now + self.open_duration_ms
                self.consecutive_failures = 0

    def snapshot(self) -> dict:
        """状态快照（监控/日志用）"""
        with self._lock:
            return {
                "name": self.name,
                "state": self.state.value,
                "consecutive_failures": self.consecutive_failures,
                "open_until_ms": int(self.open_until),
                "half_open_in_flight": self.half_open_in_flight,
            }


class ModelHealthStore:
    """所有模型候选的健康状态注册表"""

    def __init__(self, failure_threshold: int = 2, open_duration_ms: int = 30000):
        self.failure_threshold = failure_threshold
        self.open_duration_ms = open_duration_ms
        self._health: Dict[str, ModelHealth] = {}

    def register(self, name: str) -> ModelHealth:
        """注册一个候选（幂等，已注册则返回既有实例）"""
        if name not in self._health:
            self._health[name] = ModelHealth(
                name=name,
                failure_threshold=self.failure_threshold,
                open_duration_ms=self.open_duration_ms,
            )
        return self._health[name]

    def get(self, name: str) -> ModelHealth:
        """获取候选健康状态（未注册则自动注册）"""
        return self.register(name)

    def allow_call(self, name: str) -> bool:
        return self.get(name).allow_call()

    def mark_success(self, name: str):
        self.get(name).mark_success()

    def mark_failure(self, name: str):
        self.get(name).mark_failure()

    def snapshot(self) -> list:
        """全部候选状态快照（供 /ai/admin/health 接口或日志使用）"""
        return [h.snapshot() for h in self._health.values()]
