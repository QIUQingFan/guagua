"""RFM 分位分箱单元测试"""
from __future__ import annotations

from services.rfm import level, levels, segment


class TestLevel:
    def test_low(self):
        assert level(0.0) == 1
        assert level(0.19) == 1

    def test_boundaries(self):
        assert level(0.2) == 2
        assert level(0.4) == 3
        assert level(0.6) == 4
        assert level(0.8) == 5

    def test_high(self):
        assert level(1.0) == 5

    def test_clamp(self):
        assert level(-1) == 1
        assert level(2) == 5


class TestLevels:
    def test_basic(self):
        result = levels({"recency": 0.9, "frequency": 0.1, "monetary": 0.5})
        assert result == {"recency": 5, "frequency": 1, "monetary": 3}


class TestSegment:
    def test_new_user_no_purchase(self):
        assert segment({"recency": 0.0, "frequency": 0.0, "monetary": 0.0}, False) == "new_user"

    def test_churn_risk(self):
        assert segment({"recency": 0.1, "frequency": 0.5, "monetary": 0.5}, True) == "churn_risk"

    def test_high_value(self):
        assert segment({"recency": 0.9, "frequency": 0.9, "monetary": 0.9}, True) == "high_value"

    def test_price_sensitive(self):
        assert segment({"recency": 0.9, "frequency": 0.7, "monetary": 0.1}, True) == "price_sensitive"

    def test_active(self):
        assert segment({"recency": 0.5, "frequency": 0.5, "monetary": 0.5}, True) == "active"
