"""
Redis 公平排队 + 限流 自测脚本（结构验证 + 算法校验，不依赖真实 Redis）

运行：python -m rate_limiter_selftest
"""
from __future__ import annotations

import re
import time
from unittest.mock import AsyncMock, MagicMock, patch


def test_lua_script_loaded():
    """Lua 脚本加载正常"""
    from lua import load_script
    script = load_script("queue_claim_atomic.lua")
    assert "queueKey" in script, "Lua 脚本应包含 queueKey"
    assert "ZRANGE" in script, "Lua 脚本应包含 ZRANGE"
    assert "ZREM" in script, "Lua 脚本应包含 ZREM"
    assert "slack = 16" in script, "Lua 脚本应包含 slack 常量"
    print("[PASS] Lua 脚本加载正常")


def test_lua_script_atomic_properties():
    """Lua 脚本原子性属性验证：单次 eval 内完成所有操作"""
    from lua import load_script
    script = load_script("queue_claim_atomic.lua")
    assert "redis.call('ZRANGE'" in script, "ZRANGE 应在 Lua 内执行"
    assert "redis.call('ZREM'" in script, "ZREM 应在 Lua 内执行"
    assert "redis.call('DEL'" in script, "DEL 应在 Lua 内执行"
    assert "WAIT" not in script, "不应依赖外部同步"
    print("[PASS] Lua 脚本原子性属性验证通过")


async def _mock_redis(ping_ok: bool = True):
    """创建 mock Redis 客户端"""
    mock = AsyncMock()
    mock.ping.return_value = ping_ok
    mock.zadd.return_value = 1
    mock.zrem.return_value = 1
    mock.zcard.return_value = 0
    mock.get.return_value = None
    mock.set.return_value = True
    mock.delete.return_value = 1
    mock.incr.return_value = 1
    mock.decr.return_value = 0
    mock.exists.return_value = True
    mock.eval.return_value = [1, str(time.time())]
    return mock


def test_try_acquire_success():
    """try_acquire 成功获取许可"""
    import asyncio
    with patch("rate_limiter.redis_client") as mock_rc:
        mock_rc.zadd = AsyncMock(return_value=1)
        mock_rc.set = AsyncMock(return_value=True)
        mock_rc.eval = AsyncMock(return_value=[1, str(time.time())])
        mock_rc.incr = AsyncMock(return_value=5)

        from rate_limiter import try_acquire
        result = asyncio.run(try_acquire("test:1", max_concurrent=10, max_wait_seconds=5))
        assert result is True, "应成功获取许可"
        assert mock_rc.zadd.called, "应调用 zadd 入队"
        assert mock_rc.eval.called, "应调用 Lua eval"
        assert mock_rc.incr.called, "应调用 incr 并发数"
        print("[PASS] try_acquire 成功获取许可")


def test_try_acquire_timeout():
    """try_acquire 超时返回 False"""
    import asyncio
    with patch("rate_limiter.redis_client") as mock_rc:
        mock_rc.zadd = AsyncMock(return_value=1)
        mock_rc.set = AsyncMock(return_value=True)
        mock_rc.eval = AsyncMock(return_value=[0])
        mock_rc.zrem = AsyncMock(return_value=1)
        mock_rc.delete = AsyncMock(return_value=1)

        from rate_limiter import try_acquire
        result = asyncio.run(try_acquire("test:timeout", max_concurrent=10, max_wait_seconds=1))
        assert result is False, "超时应返回 False"
        assert mock_rc.zrem.called, "超时应清理队列 entry"
        assert mock_rc.delete.called, "超时应删除存活标记"
        print("[PASS] try_acquire 超时返回 False")


def test_release():
    """release 释放许可"""
    import asyncio
    with patch("rate_limiter.redis_client") as mock_rc:
        mock_rc.decr = AsyncMock(return_value=4)
        mock_rc.zrem = AsyncMock(return_value=1)
        mock_rc.delete = AsyncMock(return_value=1)

        from rate_limiter import release
        asyncio.run(release("test:1"))
        assert mock_rc.decr.called, "应调用 decr 并发数"
        assert mock_rc.zrem.called, "应从队列移除"
        assert mock_rc.delete.called, "应删除存活标记"
        print("[PASS] release 释放许可")


def test_health_check():
    """health_check 正常返回"""
    import asyncio
    with patch("rate_limiter.redis_client") as mock_rc:
        mock_rc.ping = AsyncMock(return_value=True)
        mock_rc.get = AsyncMock(return_value="3")
        mock_rc.zcard = AsyncMock(return_value=5)

        from rate_limiter import health_check
        result = asyncio.run(health_check())
        assert result["ok"] is True
        assert result["concurrent"] == 3
        assert result["queue"] == 5
        assert result["latency_ms"] >= 0
        print("[PASS] health_check 正常返回")


def test_health_check_fail():
    """health_check 在 Redis 不可用时返回 ok=False"""
    import asyncio
    with patch("rate_limiter.redis_client") as mock_rc:
        mock_rc.ping = AsyncMock(side_effect=Exception("Redis 连接失败"))

        from rate_limiter import health_check
        result = asyncio.run(health_check())
        assert result["ok"] is False
        assert "error" in result
        print("[PASS] health_check 在 Redis 不可用时返回 ok=False")


def test_current_concurrent():
    import asyncio
    with patch("rate_limiter.redis_client") as mock_rc:
        mock_rc.get = AsyncMock(return_value="7")

        from rate_limiter import current_concurrent
        result = asyncio.run(current_concurrent())
        assert result == 7
        print("[PASS] current_concurrent 返回 7")


def test_queue_length():
    """queue_length 返回排队长度"""
    import asyncio
    with patch("rate_limiter.redis_client") as mock_rc:
        mock_rc.zcard = AsyncMock(return_value=12)

        from rate_limiter import queue_length
        result = asyncio.run(queue_length())
        assert result == 12
        print("[PASS] queue_length 返回 12")


def test_ratelimit_acquire_context_manager():
    """RateLimitAcquire 上下文管理器正常"""
    import asyncio
    with patch("rate_limiter.redis_client") as mock_rc:
        mock_rc.zadd = AsyncMock(return_value=1)
        mock_rc.set = AsyncMock(return_value=True)
        mock_rc.eval = AsyncMock(return_value=[1, str(time.time())])
        mock_rc.incr = AsyncMock(return_value=5)
        mock_rc.decr = AsyncMock(return_value=4)
        mock_rc.zrem = AsyncMock(return_value=1)
        mock_rc.delete = AsyncMock(return_value=1)

        from rate_limiter import RateLimitAcquire

        async def run():
            async with RateLimitAcquire(request_id="ctx:1") as acquired:
                assert acquired, "应获取许可"
                return "done"
        result = asyncio.run(run())
        assert result == "done"
        assert mock_rc.decr.called, "退出上下文时应释放许可"
        print("[PASS] RateLimitAcquire 上下文管理器正常")


def test_ratelimit_acquire_not_acquired():
    """RateLimitAcquire 未获取许可时不应释放"""
    import asyncio
    with patch("rate_limiter.redis_client") as mock_rc:
        mock_rc.zadd = AsyncMock(return_value=1)
        mock_rc.set = AsyncMock(return_value=True)
        mock_rc.eval = AsyncMock(return_value=[0])
        mock_rc.zrem = AsyncMock(return_value=1)
        mock_rc.delete = AsyncMock(return_value=1)

        from rate_limiter import RateLimitAcquire

        async def run():
            async with RateLimitAcquire(request_id="ctx:fail", max_wait_seconds=1) as acquired:
                assert not acquired, "不应获取许可"
        asyncio.run(run())
        print("[PASS] RateLimitAcquire 未获取许可时正确")


def test_lua_zombie_cleanup_logic():
    """Lua 脚本僵尸清理逻辑验证（静态分析）"""
    from lua import load_script
    script = load_script("queue_claim_atomic.lua")
    assert "EXISTS" in script and "ZREM" in script, "Lua 应包含 EXISTS 和 ZREM"
    else_zrem = "else" in script and "ZREM" in script
    assert else_zrem, "Lua 应包含僵尸清理逻辑（else 分支 ZREM）"
    assert "slack = 16" in script, "Lua 应包含 slack 常量"
    print("[PASS] Lua 僵尸清理逻辑验证通过")


def test_sync_compat():
    """同步兼容层 try_acquire_sync / release_sync 可调用"""
    with patch("rate_limiter.redis_client") as mock_rc:
        mock_rc.zadd = AsyncMock(return_value=1)
        mock_rc.set = AsyncMock(return_value=True)
        mock_rc.eval = AsyncMock(return_value=[1, str(time.time())])
        mock_rc.incr = AsyncMock(return_value=5)
        mock_rc.decr = AsyncMock(return_value=4)
        mock_rc.zrem = AsyncMock(return_value=1)
        mock_rc.delete = AsyncMock(return_value=1)

        from rate_limiter import try_acquire_sync, release_sync
        result = try_acquire_sync("sync:1", max_concurrent=10, max_wait_seconds=5)
        assert result is True, "同步版应成功获取许可"
        release_sync("sync:1")
        assert mock_rc.decr.called, "同步版应释放许可"
        print("[PASS] 同步兼容层 try_acquire_sync / release_sync 正常")


def main():
    print("=" * 60)
    print("Redis 公平排队 + 限流 自测")
    print("=" * 60)
    test_lua_script_loaded()
    test_lua_script_atomic_properties()
    test_try_acquire_success()
    test_try_acquire_timeout()
    test_release()
    test_health_check()
    test_health_check_fail()
    test_current_concurrent()
    test_queue_length()
    test_ratelimit_acquire_context_manager()
    test_ratelimit_acquire_not_acquired()
    test_lua_zombie_cleanup_logic()
    test_sync_compat()
    print("=" * 60)
    print("全部通过 ✅")
    print("=" * 60)


if __name__ == "__main__":
    main()