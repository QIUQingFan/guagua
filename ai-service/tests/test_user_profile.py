"""用户画像模块单元测试"""
from __future__ import annotations

import asyncio
import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from langchain_core.messages import AIMessage

from agents.user_profile import (
    UserProfile,
    _compute_rfm,
    _parse_llm_json,
    analyze_user_profile,
    get_cached_profile,
)


class TestComputeRFM:
    """RFM 分数计算测试"""

    def test_no_purchases(self):
        result = _compute_rfm({"purchase_count_30d": 0})
        assert result == {"recency": 0.0, "frequency": 0.0, "monetary": 0.0}

    def test_low_frequency(self):
        result = _compute_rfm({
            "purchase_count_30d": 1,
            "days_since_last_purchase": 5,
            "avg_order_amount": 50.0,
        })
        assert result["frequency"] == 0.1
        assert result["recency"] == pytest.approx(1.0 - 5 / 30, rel=0.01)
        assert result["monetary"] == 0.05

    def test_max_values(self):
        result = _compute_rfm({
            "purchase_count_30d": 15,
            "days_since_last_purchase": 0,
            "avg_order_amount": 2000.0,
        })
        assert result["frequency"] == 1.0
        assert result["recency"] == 1.0
        assert result["monetary"] == 1.0

    def test_boundary_values(self):
        result = _compute_rfm({
            "purchase_count_30d": 10,
            "days_since_last_purchase": 30,
            "avg_order_amount": 1000.0,
        })
        assert result["frequency"] == 1.0
        assert result["recency"] == 0.0
        assert result["monetary"] == 1.0

    def test_missing_keys(self):
        result = _compute_rfm({})
        assert result == {"recency": 0.0, "frequency": 0.0, "monetary": 0.0}

    def test_negative_values(self):
        result = _compute_rfm({
            "purchase_count_30d": -1,
            "days_since_last_purchase": -5,
            "avg_order_amount": -100,
        })
        # 负数购买数 → 走计算分支，frequency = -1/10 = -0.1
        # 实际业务中不会出现负数，但函数应当不崩溃
        assert result["frequency"] == -0.1
        assert result["recency"] == pytest.approx(max(0.0, 1.0 - (-5) / 30), rel=0.01)
        assert result["monetary"] == -0.1  # avg_order_amount = -100, -100/1000 = -0.1


class TestParseLLMJson:
    """LLM 返回 JSON 解析测试"""

    def test_plain_json(self):
        raw = '{"segments": ["active"], "price_range": [0, 100]}'
        result = _parse_llm_json(raw)
        assert result["segments"] == ["active"]
        assert result["price_range"] == [0, 100]

    def test_markdown_code_block(self):
        raw = "```json\n{\"segments\": [\"high_value\"]}\n```"
        result = _parse_llm_json(raw)
        assert result["segments"] == ["high_value"]

    def test_markdown_no_lang(self):
        raw = "```\n{\"segments\": [\"new_user\"]}\n```"
        result = _parse_llm_json(raw)
        assert result["segments"] == ["new_user"]

    def test_empty_string(self):
        with pytest.raises(json.JSONDecodeError):
            _parse_llm_json("")

    def test_invalid_json(self):
        with pytest.raises(json.JSONDecodeError):
            _parse_llm_json("{invalid}")


@patch("agents.user_profile.get_default_router")
@patch("agents.user_profile.load_prompt")
@patch("agents.user_profile.engine")
@patch("agents.user_profile.redis_client")
@patch("agents.user_profile._fetch_realtime_features", return_value=([], {}))
class TestAnalyzeUserProfile:
    """用户画像分析主流程测试"""

    def test_llm_returns_valid_json(self, mock_fetch, mock_redis, mock_engine, mock_prompt, mock_router):
        mock_conn = MagicMock()
        mock_engine.connect.return_value.__enter__.return_value = mock_conn
        mock_conn.execute.return_value.fetchall.return_value = []
        mock_conn.execute.return_value.fetchone.return_value = (10, 3, 299.0)

        mock_prompt.return_value = "分析用户画像"

        mock_llm = MagicMock()
        mock_llm.invoke.return_value = AIMessage(content='{"segments": ["active","high_value"], "preferred_categories": ["文创周边"], "price_range": [50, 300], "rfm_score": {"recency": 0.8, "frequency": 0.3, "monetary": 0.3}}')
        mock_router.return_value = mock_llm

        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.set = AsyncMock(return_value=True)

        profile = analyze_user_profile("test_user_1")

        assert isinstance(profile, UserProfile)
        assert profile.user_id == "test_user_1"
        assert profile.segments == ["active", "high_value"]
        assert profile.preferred_categories == ["文创周边"]
        assert profile.price_range == (50.0, 300.0)
        assert profile.rfm_score == {"recency": 0.8, "frequency": 0.3, "monetary": 0.3}

    def test_llm_returns_invalid_json(self, mock_fetch, mock_redis, mock_engine, mock_prompt, mock_router):
        mock_conn = MagicMock()
        mock_engine.connect.return_value.__enter__.return_value = mock_conn
        mock_conn.execute.return_value.fetchall.return_value = []
        mock_conn.execute.return_value.fetchone.return_value = (0, 0, 0)

        mock_prompt.return_value = "分析用户画像"

        mock_llm = MagicMock()
        mock_llm.invoke.return_value = AIMessage(content="invalid json")
        mock_router.return_value = mock_llm

        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.set = AsyncMock(return_value=True)

        profile = analyze_user_profile("test_user_2")

        assert isinstance(profile, UserProfile)
        assert profile.segments == ["active"]
        assert profile.preferred_categories == []
        assert profile.price_range == (0.0, 10000.0)

    def test_llm_raises_exception(self, mock_fetch, mock_redis, mock_engine, mock_prompt, mock_router):
        mock_conn = MagicMock()
        mock_engine.connect.return_value.__enter__.return_value = mock_conn
        mock_conn.execute.return_value.fetchall.return_value = []
        mock_conn.execute.return_value.fetchone.return_value = (0, 0, 0)

        mock_prompt.return_value = "分析用户画像"

        mock_llm = MagicMock()
        mock_llm.invoke.side_effect = Exception("LLM 服务不可用")
        mock_router.return_value = mock_llm

        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.set = AsyncMock(return_value=True)

        profile = analyze_user_profile("test_user_3")

        assert isinstance(profile, UserProfile)
        assert profile.segments == ["active"]
        assert profile.user_id == "test_user_3"

    def test_db_query_failure(self, mock_fetch, mock_redis, mock_engine, mock_prompt, mock_router):
        mock_engine.connect.side_effect = Exception("数据库连接失败")

        mock_prompt.return_value = "分析用户画像"

        mock_llm = MagicMock()
        mock_llm.invoke.return_value = AIMessage(content='{"segments": ["active"]}')
        mock_router.return_value = mock_llm

        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.set = AsyncMock(return_value=True)

        profile = analyze_user_profile("test_user_4")

        assert isinstance(profile, UserProfile)
        assert profile.user_id == "test_user_4"
        assert profile.segments == ["active"]
        assert profile.recent_views == []
        assert profile.recent_purchases == []

    def test_redis_cache_write_failure(self, mock_fetch, mock_redis, mock_engine, mock_prompt, mock_router):
        mock_conn = MagicMock()
        mock_engine.connect.return_value.__enter__.return_value = mock_conn
        mock_conn.execute.return_value.fetchall.return_value = []
        mock_conn.execute.return_value.fetchone.return_value = (0, 0, 0)

        mock_prompt.return_value = "分析用户画像"

        mock_llm = MagicMock()
        mock_llm.invoke.return_value = AIMessage(content='{"segments": ["active"]}')
        mock_router.return_value = mock_llm

        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.set = AsyncMock(side_effect=Exception("Redis 写入失败"))

        profile = analyze_user_profile("test_user_5")

        assert isinstance(profile, UserProfile)
        assert profile.user_id == "test_user_5"


@patch("agents.user_profile.redis_client")
class TestGetCachedProfile:
    """缓存读取测试"""

    def test_cache_hit(self, mock_redis):
        cached = UserProfile(
            user_id="cached_user",
            segments=["high_value"],
            preferred_categories=["数码"],
            price_range=(100, 500),
        )
        mock_redis.get = AsyncMock(return_value=cached.model_dump_json())

        result = get_cached_profile("cached_user")

        assert result is not None
        assert result.user_id == "cached_user"
        assert result.segments == ["high_value"]
        assert result.preferred_categories == ["数码"]

    def test_cache_miss(self, mock_redis):
        mock_redis.get = AsyncMock(return_value=None)

        result = get_cached_profile("unknown_user")

        assert result is None

    def test_cache_redis_error(self, mock_redis):
        mock_redis.get = AsyncMock(side_effect=Exception("Redis 不可用"))

        result = get_cached_profile("error_user")

        assert result is None

    def test_cache_invalid_data(self, mock_redis):
        mock_redis.get = AsyncMock(return_value="not valid json")

        result = get_cached_profile("bad_user")

        assert result is None


@patch("agents.user_profile.get_default_router")
@patch("agents.user_profile.load_prompt")
@patch("agents.user_profile.engine")
@patch("agents.user_profile.redis_client")
@patch("agents.user_profile._fetch_realtime_features", return_value=([], {}))
class TestUserProfileNode:
    """user_profile_node 集成测试（通过直接调用 analyze_user_profile）"""

    def test_profile_contains_all_required_fields(self, mock_fetch, mock_redis, mock_engine, mock_prompt, mock_router):
        mock_conn = MagicMock()
        mock_engine.connect.return_value.__enter__.return_value = mock_conn
        mock_conn.execute.return_value.fetchall.return_value = []
        mock_conn.execute.return_value.fetchone.return_value = (5, 1, 150.0)

        mock_prompt.return_value = "分析用户画像"
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = AIMessage(content=json.dumps({
            "segments": ["active"],
            "preferred_categories": ["学习用品"],
            "price_range": [20, 200],
            "rfm_score": {"recency": 0.5, "frequency": 0.1, "monetary": 0.15},
            "real_time_tags": {"活跃时段": "晚上", "偏好风格": "简约"},
        }))
        mock_router.return_value = mock_llm
        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.set = AsyncMock(return_value=True)

        profile = analyze_user_profile("test_user")

        profile_dict = profile.model_dump()
        assert "user_id" in profile_dict
        assert "segments" in profile_dict
        assert "preferred_categories" in profile_dict
        assert "price_range" in profile_dict
        assert "recent_views" in profile_dict
        assert "recent_purchases" in profile_dict
        assert "rfm_score" in profile_dict
        assert "real_time_tags" in profile_dict

    def test_segments_default_to_active(self, mock_fetch, mock_redis, mock_engine, mock_prompt, mock_router):
        mock_conn = MagicMock()
        mock_engine.connect.return_value.__enter__.return_value = mock_conn
        mock_conn.execute.return_value.fetchall.return_value = []
        mock_conn.execute.return_value.fetchone.return_value = (0, 0, 0)

        mock_prompt.return_value = "分析用户画像"
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = AIMessage(content='{"segments": ["invalid_segment"]}')
        mock_router.return_value = mock_llm
        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.set = AsyncMock(return_value=True)

        profile = analyze_user_profile("test_user")
        assert profile.segments == ["active"]

    def test_price_range_default(self, mock_fetch, mock_redis, mock_engine, mock_prompt, mock_router):
        mock_conn = MagicMock()
        mock_engine.connect.return_value.__enter__.return_value = mock_conn
        mock_conn.execute.return_value.fetchall.return_value = []
        mock_conn.execute.return_value.fetchone.return_value = (0, 0, 0)

        mock_prompt.return_value = "分析用户画像"
        mock_llm = MagicMock()
        mock_llm.invoke.return_value = AIMessage(content='{"segments": ["active"]}')
        mock_router.return_value = mock_llm
        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.set = AsyncMock(return_value=True)

        profile = analyze_user_profile("test_user")
        assert profile.price_range == (0.0, 10000.0)