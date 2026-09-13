"""库存/限购/预警共享服务单元测试"""
from __future__ import annotations

from services.inventory import (
    LIMIT_QUANTITY,
    MIN_ALERT_STOCK,
    decide,
)


class TestDecide:
    def test_normal_stock(self):
        result = decide([{"id": 1, "stock": 100}])
        assert result["available"] == [1]
        assert result["limits"] == {}
        assert result["alerts"] == []

    def test_limits_low_stock(self):
        result = decide([{"id": 2, "stock": 4}])
        assert result["available"] == [2]
        assert result["limits"] == {2: LIMIT_QUANTITY}

    def test_alert_very_low_stock(self):
        result = decide([{"id": 3, "stock": MIN_ALERT_STOCK}])
        assert result["available"] == [3]
        assert result["limits"] == {3: LIMIT_QUANTITY}
        assert result["alerts"] == [{"product_id": 3, "stock": MIN_ALERT_STOCK}]

    def test_zero_stock_excluded(self):
        result = decide([{"id": 4, "stock": 0}, {"id": 5, "stock": -1}])
        assert result["available"] == []

    def test_missing_stock_defaults_zero(self):
        result = decide([{"id": 6, "stock": None}])
        assert result["available"] == []

    def test_product_id_alias(self):
        result = decide([{"product_id": 7, "stock": 2}])
        assert result["available"] == [7]

    def test_empty_input(self):
        result = decide([])
        assert result == {"available": [], "limits": {}, "alerts": []}
