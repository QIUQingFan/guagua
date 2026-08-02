"""
Redis 连接管理（单例连接池）
"""
from __future__ import annotations

import logging
from typing import Optional

import redis.asyncio as aioredis

from config import settings

logger = logging.getLogger("redis_client")


class RedisClient:
    def __init__(self):
        self._pool: Optional[aioredis.ConnectionPool] = None
        self._client: Optional[aioredis.Redis] = None

    def _ensure(self) -> aioredis.Redis:
        if self._client is None:
            self._pool = aioredis.ConnectionPool(
                host=settings.REDIS_HOST,
                port=settings.REDIS_PORT,
                db=settings.REDIS_DB,
                password=settings.REDIS_PASSWORD or None,
                decode_responses=True,
                max_connections=settings.REDIS_MAX_CONNECTIONS,
            )
            self._client = aioredis.Redis(connection_pool=self._pool)
            logger.info(
                "Redis 连接池已创建: %s:%s/%s (max_connections=%d)",
                settings.REDIS_HOST,
                settings.REDIS_PORT,
                settings.REDIS_DB,
                settings.REDIS_MAX_CONNECTIONS,
            )
        return self._client

    async def close(self):
        if self._pool:
            await self._pool.disconnect()
            self._pool = None
            self._client = None
            logger.info("Redis 连接池已关闭")


    async def set(self, name: str, value: str, ex: Optional[int] = None) -> bool:
        return await self._ensure().set(name, value, ex=ex)

    async def get(self, name: str) -> Optional[str]:
        return await self._ensure().get(name)

    async def delete(self, *names: str) -> int:
        return await self._ensure().delete(*names)

    async def exists(self, name: str) -> bool:
        return await self._ensure().exists(name) > 0

    async def expire(self, name: str, time: int) -> bool:
        return await self._ensure().expire(name, time)

    async def zadd(self, name: str, mapping: dict, nx: bool = False) -> int:
        return await self._ensure().zadd(name, mapping, nx=nx)

    async def zrem(self, name: str, *values: str) -> int:
        return await self._ensure().zrem(name, *values)

    async def zcard(self, name: str) -> int:
        return await self._ensure().zcard(name)

    async def zrank(self, name: str, value: str) -> Optional[int]:
        return await self._ensure().zrank(name, value)

    async def incr(self, name: str) -> int:
        return await self._ensure().incr(name)

    async def decr(self, name: str) -> int:
        return await self._ensure().decr(name)

    async def eval(self, script: str, keys: list, args: list) -> list:
        """执行 Lua 脚本（原子操作）。"""
        return await self._ensure().eval(script, len(keys), *(keys + args))


    async def ping(self) -> bool:
        try:
            return await self._ensure().ping()
        except Exception:
            return False


redis_client = RedisClient()