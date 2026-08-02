"""
Redis 公平排队 + 限流

核心概念：
- 公平排队：请求按到达顺序入队 ZSET，位于队头窗口（可用许可数内）的请求出队执行业务
- 限流：全局并发许可数限制，超出的请求排队等待或超时返回 429
- 许可回收：请求结束后释放许可，支持僵尸清理（客户端断开/超时后自动过期）
"""
from __future__ import annotations

import asyncio
import logging
import time
import uuid
from typing import Optional

from config import settings
from lua import load_script
from redis_client import redis_client

logger = logging.getLogger("rate_limiter")

_QUEUE_CLAIM_SCRIPT = load_script("queue_claim_atomic.lua")

_QUEUE_KEY = "rate:queue"
_ALIVE_PREFIX = "rate:alive:"
_CONCURRENT_KEY = "rate:concurrent"
_LOCK_KEY = "rate:lock:"


async def try_acquire(
    request_id: str,
    max_concurrent: Optional[int] = None,
    max_wait_seconds: Optional[int] = None,
) -> bool:
    """
    尝试获取许可（公平排队 + 限流）。

    流程：
    1. 先入队 ZSET（score=当前时间戳）
    2. 执行 Lua 原子 claim：扫描队头窗口，清理僵尸，判断是否在存活窗口内
    3. 若 claim 成功：INCR 并发数，返回 True
    4. 若 claim 失败：返回 False（排队中或超时）

    Args:
        request_id: 请求唯一标识
        max_concurrent: 最大并发数（默认 settings.RATE_LIMIT_MAX_CONCURRENT）
        max_wait_seconds: 最大等待秒数（默认 settings.RATE_LIMIT_MAX_WAIT_SECONDS）

    Returns:
        True=获取许可成功，可执行业务；False=排队中/超时
    """
    max_concurrent = max_concurrent or settings.RATE_LIMIT_MAX_CONCURRENT
    max_wait_seconds = max_wait_seconds or settings.RATE_LIMIT_MAX_WAIT_SECONDS

    now = time.time()
    deadline = now + max_wait_seconds

    await redis_client.zadd(_QUEUE_KEY, {request_id: now}, nx=True)
    await redis_client.set(_ALIVE_PREFIX + request_id, "1", ex=max_wait_seconds)

    while time.time() < deadline:
        result = await redis_client.eval(
            _QUEUE_CLAIM_SCRIPT,
            keys=[_QUEUE_KEY],
            args=[request_id, str(max_concurrent), _ALIVE_PREFIX],
        )
        if result and result[0] == 1:
            await redis_client.incr(_CONCURRENT_KEY)
            return True

        await asyncio.sleep(0.5)

    await redis_client.zrem(_QUEUE_KEY, request_id)
    await redis_client.delete(_ALIVE_PREFIX + request_id)
    return False


async def release(request_id: str):
    """释放许可（请求结束时调用）。"""
    await redis_client.decr(_CONCURRENT_KEY)
    await redis_client.zrem(_QUEUE_KEY, request_id)
    await redis_client.delete(_ALIVE_PREFIX + request_id)


async def current_concurrent() -> int:
    """获取当前并发数。"""
    val = await redis_client.get(_CONCURRENT_KEY)
    return int(val) if val else 0


async def queue_length() -> int:
    """获取当前排队长度"""
    return await redis_client.zcard(_QUEUE_KEY)


async def health_check() -> dict:
    """
    限流器健康检查。

    Returns:
        {"ok": bool, "concurrent": int, "queue": int, "latency_ms": float}
    """
    start = time.time()
    try:
        ok = await redis_client.ping()
        c = await current_concurrent()
        q = await queue_length()
        return {
            "ok": ok,
            "concurrent": c,
            "queue": q,
            "latency_ms": round((time.time() - start) * 1000, 1),
        }
    except Exception as exc:
        return {"ok": False, "error": str(exc), "latency_ms": -1}



def try_acquire_sync(
    request_id: str,
    max_concurrent: Optional[int] = None,
    max_wait_seconds: Optional[int] = None,
) -> bool:
    """同步版 try_acquire（在 run_in_executor 线程中调用）。"""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(
            try_acquire(request_id, max_concurrent, max_wait_seconds)
        )
    finally:
        loop.close()


def release_sync(request_id: str):
    """同步版 release。"""
    loop = asyncio.new_event_loop()
    try:
        loop.run_until_complete(release(request_id))
    finally:
        loop.close()



class RateLimitAcquire:
    """
    限流许可上下文管理器。

    用法：
        async with RateLimitAcquire() as acquired:
            if acquired:
                # 执行业务
            else:
                # 返回 429
    """

    def __init__(
        self,
        request_id: Optional[str] = None,
        max_concurrent: Optional[int] = None,
        max_wait_seconds: Optional[int] = None,
    ):
        self.request_id = request_id or f"req:{uuid.uuid4().hex}"
        self.max_concurrent = max_concurrent
        self.max_wait_seconds = max_wait_seconds
        self.acquired = False

    async def __aenter__(self) -> bool:
        self.acquired = await try_acquire(
            self.request_id, self.max_concurrent, self.max_wait_seconds
        )
        return self.acquired

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.acquired:
            await release(self.request_id)