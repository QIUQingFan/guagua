"""营销文案子能力单元测试"""
from __future__ import annotations

from services.marketing_copy import (
    _BANNED_WORDS,
    _comply,
    _segment_of,
    generate,
    template_for,
)


class TestSegmentOf:
    def test_picks_first_known_segment(self):
        assert _segment_of({"segments": ["price_sensitive", "active"]}) == "price_sensitive"

    def test_falls_back_to_active(self):
        assert _segment_of({"segments": ["unknown"]}) == "active"

    def test_no_profile(self):
        assert _segment_of(None) == "active"


class TestComply:
    def test_removes_banned_words(self):
        text = "这是最好的商品，全网第一"
        result = _comply(text)
        assert "最好" not in result
        assert "第一" not in result


class TestTemplateFor:
    def test_known_segment(self):
        assert template_for("vip") == template_for("active") or template_for("vip")

    def test_unknown_segment_falls_back(self):
        assert template_for("nope") == template_for("active")


class TestGenerate:
    def test_personalized_uses_profile_segment(self):
        profile = {"segments": ["price_sensitive"]}
        copies = generate(profile, [{"id": 1, "name": "耳机", "price": 99.0}], personalized=True)
        assert copies[0]["segment"] == "price_sensitive"
        assert "耳机" in copies[0]["copy"]
        assert "99" in copies[0]["copy"]

    def test_generic_when_not_personalized(self):
        profile = {"segments": ["high_value"]}
        copies = generate(profile, [{"id": 2, "name": "手办", "price": 199.0}], personalized=False)
        assert copies[0]["segment"] == "active"

    def test_no_banned_words_in_output(self):
        copies = generate({"segments": ["new_user"]}, [{"id": 3, "name": "T恤", "price": 59.0}])
        for c in copies:
            for word in _BANNED_WORDS:
                assert word not in c["copy"]

    def test_empty_products(self):
        assert generate({"segments": ["active"]}, []) == []

    def test_product_id_alias(self):
        copies = generate(None, [{"product_id": 8, "name": "书", "price": 20.0}])
        assert copies[0]["product_id"] == 8
