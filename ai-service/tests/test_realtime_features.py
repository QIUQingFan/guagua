"""画像实时特征单元测试"""
from __future__ import annotations

from unittest.mock import patch

from agents.user_profile import _fetch_realtime_features


@patch("redis_client.get_sync_client")
def test_returns_counts_and_views(mock_get):
    r = mock_get.return_value
    r.zcount.side_effect = [5, 3, 1, 2, 1, 0, 0, 0, 0, 0, 0, 0]
    r.zrevrangebyscore.return_value = [("11", 1000.0), ("22", 900.0)]

    views, counts = _fetch_realtime_features("123")

    assert views == [
        {"product_id": 11, "last_viewed_at": 1000},
        {"product_id": 22, "last_viewed_at": 900},
    ]
    assert counts["views_1h"] == 5
    assert counts["views_24h"] == 3
    assert counts["views_7d"] == 1
    assert counts["purchases_7d"] == 0


@patch("redis_client.get_sync_client")
def test_non_numeric_user_returns_empty(mock_get):
    assert _fetch_realtime_features("abc") == ([], {})


@patch("redis_client.get_sync_client", side_effect=Exception("redis down"))
def test_redis_error_returns_empty(mock_get):
    assert _fetch_realtime_features("123") == ([], {})
