"""
Lua 脚本加载器
"""
from __future__ import annotations

import os
from functools import lru_cache


_LUA_DIR = os.path.dirname(os.path.abspath(__file__))


@lru_cache(maxsize=4)
def load_script(name: str) -> str:
    """加载 Lua 脚本内容（进程内缓存，避免重复 IO）。"""
    path = os.path.join(_LUA_DIR, name)
    if not os.path.exists(path):
        raise FileNotFoundError(f"Lua 脚本不存在: {path}")
    with open(path, "r", encoding="utf-8") as f:
        return f.read()