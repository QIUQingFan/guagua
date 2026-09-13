"""action 富化（库存 + 营销文案 + A-B）接线测试"""
from __future__ import annotations

from unittest.mock import patch

from agent import _enrich_action


def _products_text():
    return "\n".join([
        "#1 耳机 | category: 二手数码 | price: CNY 99.00 | sales: 10 | stock: 2",
        "#2 手办 | category: 文创周边 | price: CNY 199.00 | sales: 5 | stock: 100",
    ])


def test_enrich_adds_inventory_and_copies():
    action = {"type": "buy_now", "productId": 1, "productName": "耳机"}
    profile = {"segments": ["price_sensitive"]}
    result = _enrich_action(action, _products_text(), profile, 42)
    assert result is action
    assert result["inventory"]["limits"] == {1: 2}
    assert result["inventory"]["alerts"] == [{"product_id": 1, "stock": 2}]
    assert len(result["copies"]) == 2
    assert result["copies"][0]["product_id"] == 1
    assert "耳机" in result["copies"][0]["copy"]


def test_enrich_none_action_returns_none():
    assert _enrich_action(None, _products_text(), None, 1) is None


def test_enrich_empty_products_keeps_action():
    action = {"type": "buy_now", "productId": 1}
    result = _enrich_action(action, "No matched live products were found.", None, 1)
    assert result is action
    assert "inventory" not in result


def test_enrich_exception_silent():
    action = {"type": "buy_now"}
    with patch("agent._parse_products", side_effect=Exception("boom")):
        result = _enrich_action(action, "whatever", None, 1)
    assert result is action
    assert "inventory" not in result
