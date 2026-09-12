"""用户画像分析模块

职责：
1. 根据 user_id 拉取近期行为数据（订单/浏览/收藏/关注等）
2. 计算 RFM 分 + 行为统计
3. 调用 LLM 产出结构化画像
4. 通过 Redis 做缓存，TTL 默认 1 小时

对外：
- UserProfile : 画像数据结构
- analyze_user_profile(user_id, hints=None) -> UserProfile  : 分析主入口
- get_cached_profile(user_id) -> Optional[UserProfile]       : 只读缓存命中

在 LangGraph agent.py 中通过 user_profile_node(state) 调用，
因此对外保持同步 API。
"""
from __future__ import annotations

import asyncio
import json
import logging
import re
import textwrap
from typing import Any, Dict, List, Optional, Tuple

from pydantic import BaseModel, Field

from database import engine
from model_router import get_default_router
from prompts import load_prompt
from redis_client import redis_client

logger = logging.getLogger("agents.user_profile")

# Redis 缓存 Key 前缀 & TTL
_CACHE_KEY_PREFIX = "profile:user:"
_CACHE_TTL_SECONDS = 60 * 60  # 1 小时

# 合法用户分群（LLM 输出不在此集合里会降级为默认 active）
_ALLOWED_SEGMENTS = {"new_user", "active", "high_value", "price_sensitive", "churn_risk"}

# 默认价格区间（兜底）
_DEFAULT_PRICE_RANGE = (0.0, 10000.0)


class UserProfile(BaseModel):
    """用户画像结构化数据。"""

    user_id: str
    segments: List[str] = Field(default_factory=lambda: ["active"])
    preferred_categories: List[str] = Field(default_factory=list)
    price_range: Tuple[float, float] = Field(default=_DEFAULT_PRICE_RANGE)
    recent_views: List[Dict[str, Any]] = Field(default_factory=list)
    recent_purchases: List[Dict[str, Any]] = Field(default_factory=list)
    rfm_score: Dict[str, float] = Field(
        default_factory=lambda: {"recency": 0.0, "frequency": 0.0, "monetary": 0.0}
    )
    real_time_tags: Dict[str, str] = Field(default_factory=dict)


# --------------------------------------------------------------------------- #
# 数据拉取 & 特征计算
# --------------------------------------------------------------------------- #

def _compute_rfm(stats: Dict[str, Any]) -> Dict[str, float]:
    """根据统计结果计算 RFM 三维分数（0~1）。

    说明：
    - recency:   距离最近一次下单的天数（越小越好），最大值按 30 天归一化
    - frequency: 近 30 天下单次数（越大越好），最大值按 10 单归一化
    - monetary:  客单价均值（越大越好），最大值按 1000 归一化

    当前为启发式规则，业务稳定后可接入真实 RFM 分箱。
    """
    frequency_raw = float(stats.get("purchase_count_30d") or 0)
    recency_days_raw = stats.get("days_since_last_purchase")
    avg_order_amount_raw = float(stats.get("avg_order_amount") or 0)

    frequency = min(1.0, frequency_raw / 10.0)

    if recency_days_raw is None:
        recency = 0.0
    else:
        recency = max(0.0, min(1.0, 1.0 - float(recency_days_raw) / 30.0))

    monetary = min(1.0, avg_order_amount_raw / 1000.0)

    return {"recency": recency, "frequency": frequency, "monetary": monetary}


def _fetch_behavior_data(user_id: str) -> Dict[str, Any]:
    """从瓜呱业务库拉取用户行为数据。

    表不存在或字段不完整时返回空字典（让后续逻辑降级，不阻塞主流程）。
    """
    data: Dict[str, Any] = {
        "purchase_stats": None,
        "recent_purchases": [],
        "recent_views": [],
    }
    try:
        with engine.connect() as conn:
            # 订单聚合：最近 30 天下单数、最近下单天数、客单价均值
            try:
                purchase_stats = conn.execute(
                    textwrap.dedent(
                        """\
                        SELECT
                            COUNT(DISTINCT o.id) AS purchase_count_30d,
                            DATEDIFF(CURDATE(), MAX(o.created_at)) AS days_since_last_purchase,
                            AVG(o.total_amount) AS avg_order_amount
                        FROM orders o
                        WHERE o.user_id = :user_id
                          AND o.order_status NOT IN ('cancelled', 'refunded')
                          AND o.created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
                        """
                    ),
                    {"user_id": int(user_id) if str(user_id).isdigit() else 0},
                ).fetchone()
                if purchase_stats is not None:
                    data["purchase_stats"] = dict(purchase_stats._mapping)
            except Exception as exc:
                logger.debug("用户画像订单统计拉取失败（降级）: %s", exc)

            # 最近 10 笔已完成下单（类目用于偏好类目提取）
            try:
                rows = conn.execute(
                    textwrap.dedent(
                        """\
                        SELECT
                            o.id             AS order_id,
                            o.total_amount   AS total_amount,
                            o.created_at     AS created_at,
                            GROUP_CONCAT(c.name SEPARATOR ',') AS categories
                        FROM orders o
                        LEFT JOIN order_items oi    ON oi.order_id = o.id
                        LEFT JOIN products p       ON p.id = oi.product_id
                        LEFT JOIN shop_categories c ON c.id = p.category_id
                        WHERE o.user_id = :user_id
                          AND o.order_status NOT IN ('cancelled', 'refunded')
                        GROUP BY o.id
                        ORDER BY o.created_at DESC
                        LIMIT 10
                        """
                    ),
                    {"user_id": int(user_id) if str(user_id).isdigit() else 0},
                ).fetchall()
                data["recent_purchases"] = [dict(r._mapping) for r in rows]
            except Exception as exc:
                logger.debug("用户画像最近订单拉取失败（降级）: %s", exc)

            # 最近浏览（表不存在 / 字段缺失时降级为空）
            try:
                rows = conn.execute(
                    textwrap.dedent(
                        """\
                        SELECT
                            product_id,
                            MAX(created_at) AS last_viewed_at,
                            COUNT(*)       AS view_count
                        FROM ai_user_behaviors
                        WHERE user_id = :user_id AND action = 'view'
                        GROUP BY product_id
                        ORDER BY last_viewed_at DESC
                        LIMIT 10
                        """
                    ),
                    {"user_id": int(user_id) if str(user_id).isdigit() else 0},
                ).fetchall()
                data["recent_views"] = [dict(r._mapping) for r in rows]
            except Exception as exc:
                logger.debug("用户画像浏览行为拉取失败（降级）: %s", exc)
    except Exception as exc:
        logger.warning("用户画像行为数据拉取整体失败，降级为空: %s", exc)

    return data


# --------------------------------------------------------------------------- #
# LLM 解析
# --------------------------------------------------------------------------- #

def _parse_llm_json(raw: str) -> Dict[str, Any]:
    """解析 LLM 返回的 JSON，兼容 markdown 代码块包裹。"""
    if raw is None:
        raise json.JSONDecodeError("Empty LLM content", "", 0)
    text = raw.strip()

    # 去除 ```json ... ``` 或 ``` ... ```
    code_block = re.match(r"```(?:json)?\s*(.*?)\s*```", text, flags=re.S)
    if code_block:
        text = code_block.group(1).strip()

    return json.loads(text)


def _build_behavior_prompt_input(user_id: str, behavior: Dict[str, Any], hints: Dict[str, Any]) -> str:
    """把行为数据 + 提示结构化成可填进 prompt 的字符串。"""
    purchase_stats = behavior.get("purchase_stats") or {}
    rfm = _compute_rfm(purchase_stats)
    recent_purchases = behavior.get("recent_purchases") or []
    recent_views = behavior.get("recent_views") or []

    stats_block = json.dumps(
        {
            "purchase_stats": purchase_stats,
            "rfm_score": rfm,
            "recent_purchases": recent_purchases,
            "recent_views": recent_views,
            "conversation_hints": hints.get("history", [])[-6:] if hints else [],
        },
        ensure_ascii=False,
        indent=2,
    )
    return stats_block, rfm


# --------------------------------------------------------------------------- #
# 对外 API
# --------------------------------------------------------------------------- #

def _sync_redis_get(key: str) -> Optional[str]:
    """同步包装：redis 异步 get。"""
    try:
        return asyncio.run(redis_client.get(key))
    except Exception as exc:
        logger.warning("画像缓存读取失败: %s", exc)
        return None


def _sync_redis_set(key: str, value: str, ex: int) -> None:
    try:
        asyncio.run(redis_client.set(key, value, ex=ex))
    except Exception as exc:
        logger.warning("画像缓存写入失败（忽略）: %s", exc)


def get_cached_profile(user_id: str) -> Optional[UserProfile]:
    """只读 Redis 缓存，返回 UserProfile 或 None。"""
    if not user_id:
        return None
    raw = _sync_redis_get(f"{_CACHE_KEY_PREFIX}{user_id}")
    if not raw:
        return None
    try:
        payload = json.loads(raw)
        return UserProfile(**payload)
    except Exception as exc:
        logger.warning("画像缓存解析失败（视为 miss）: %s", exc)
        return None


def _write_cache(profile: UserProfile) -> None:
    try:
        payload = profile.model_dump_json()
    except Exception as exc:
        logger.warning("画像序列化失败，跳过缓存写入: %s", exc)
        return
    _sync_redis_set(f"{_CACHE_KEY_PREFIX}{profile.user_id}", payload, ex=_CACHE_TTL_SECONDS)


def analyze_user_profile(user_id: str, hints: Optional[Dict[str, Any]] = None) -> UserProfile:
    """分析指定用户画像。

    流程：拉行为 -> 算 RFM -> 组 prompt -> 调 LLM -> 结构化 -> 写缓存。
    任何环节失败均走兜底画像（segments=['active']），保证不中断主 Agent。
    """
    hints = hints or {}

    # 1. 拉取行为（失败则为空）
    try:
        behavior = _fetch_behavior_data(user_id)
    except Exception as exc:
        logger.warning("用户画像行为拉取失败，走兜底: %s", exc)
        behavior = {}

    # 2. 组 prompt & 默认 RFM
    try:
        behavior_text, rfm = _build_behavior_prompt_input(user_id, behavior, hints)
        prompt = load_prompt("user-profile", behavior_data=behavior_text)
    except Exception as exc:
        logger.warning("用户画像 prompt 组装失败，走兜底: %s", exc)
        profile = UserProfile(user_id=str(user_id))
        _write_cache(profile)
        return profile

    # 3. 调 LLM
    parsed: Dict[str, Any] = {}
    llm_ok = False
    try:
        llm = get_default_router()
        response = llm.invoke(prompt, tier="fast")
        content = getattr(response, "content", response) if response is not None else ""
        parsed = _parse_llm_json(content)
        llm_ok = True
    except Exception as exc:
        logger.warning("用户画像 LLM 调用失败，走兜底: %s", exc)
        llm_ok = False

    # 4. 字段清洗 + 兜底
    segments_raw = parsed.get("segments") if isinstance(parsed, dict) else None
    if isinstance(segments_raw, list):
        segments = [s for s in segments_raw if isinstance(s, str) and s in _ALLOWED_SEGMENTS]
    else:
        segments = []
    if not segments:
        segments = ["active"]

    preferred_categories_raw = parsed.get("preferred_categories") if isinstance(parsed, dict) else None
    if isinstance(preferred_categories_raw, list):
        preferred_categories = [c for c in preferred_categories_raw if isinstance(c, str)]
    else:
        preferred_categories = []

    price_range_raw = parsed.get("price_range") if isinstance(parsed, dict) else None
    if (
        isinstance(price_range_raw, (list, tuple))
        and len(price_range_raw) >= 2
        and all(isinstance(x, (int, float)) for x in price_range_raw[:2])
    ):
        price_range: Tuple[float, float] = (float(price_range_raw[0]), float(price_range_raw[1]))
    else:
        price_range = _DEFAULT_PRICE_RANGE

    real_time_tags_raw = parsed.get("real_time_tags") if isinstance(parsed, dict) else None
    if isinstance(real_time_tags_raw, dict):
        real_time_tags = {
            str(k): str(v) for k, v in real_time_tags_raw.items() if isinstance(k, str)
        }
    else:
        real_time_tags = {}

    # LLM 若返回了 rfm_score 就覆盖启发式（但仍校验结构）
    rfm_override = parsed.get("rfm_score") if isinstance(parsed, dict) else None
    if isinstance(rfm_override, dict):
        for k in ("recency", "frequency", "monetary"):
            v = rfm_override.get(k)
            if isinstance(v, (int, float)):
                rfm[k] = max(0.0, min(1.0, float(v)))

    # recent_views / recent_purchases 直接取自行为数据（不依赖 LLM，保留结构化）
    recent_views = behavior.get("recent_views") or []
    recent_purchases = behavior.get("recent_purchases") or []

    profile = UserProfile(
        user_id=str(user_id),
        segments=segments,
        preferred_categories=preferred_categories,
        price_range=price_range,
        recent_views=recent_views,
        recent_purchases=recent_purchases,
        rfm_score=rfm,
        real_time_tags=real_time_tags,
    )

    # 仅当 LLM 过程 OK 才写缓存，避免把一次"意外失败的兜底画像"缓存 1 小时
    if llm_ok:
        _write_cache(profile)

    return profile
