"""A-B 测试引擎单元测试"""
from __future__ import annotations

import hashlib

from services.ab_test import ABTestEngine


def _bucket(user_id) -> int:
    return int(hashlib.md5(str(user_id).encode("utf-8")).hexdigest(), 16) % 100


def _engine() -> ABTestEngine:
    engine = ABTestEngine()
    engine.register_experiment(
        "test-exp",
        dim="排序策略",
        groups=[
            {"name": "control", "weight": 1.0, "config": {"strategy": "sales"}},
            {"name": "treatment", "weight": 1.0, "config": {"strategy": "llm"}},
        ],
    )
    return engine


class TestAssign:
    def test_known_exp_returns_group(self):
        result = _engine().assign("test-exp", "u001")
        assert result["exp_id"] == "test-exp"
        assert result["group"] in {"control", "treatment"}
        assert "config" in result

    def test_unknown_exp_returns_control(self):
        result = _engine().assign("nope", "u001")
        assert result == {"exp_id": "nope", "group": "control", "config": {}}

    def test_assign_deterministic(self):
        engine = _engine()
        assert engine.assign("test-exp", "u001")["group"] == engine.assign("test-exp", "u001")["group"]

    def test_assign_matches_bucket(self):
        engine = _engine()
        user = "u007"
        group = engine.assign("test-exp", user)["group"]
        expected = "control" if _bucket(user) < 50 else "treatment"
        assert group == expected


class TestDistribution:
    def test_two_groups_roughly_balanced(self):
        engine = _engine()
        counts = {"control": 0, "treatment": 0}
        for i in range(10000):
            g = engine.assign("test-exp", f"user_{i}")["group"]
            counts[g] += 1
        assert counts["control"] > 4500
        assert counts["treatment"] > 4500


class TestRecordOutcome:
    def test_record_updates_stats(self):
        engine = _engine()
        assert engine.record_outcome("test-exp", "control", True) is True
        stats = engine.get_stats("test-exp")
        group = [g for g in stats["groups"] if g["name"] == "control"][0]
        assert group["successes"] == 1
        assert group["failures"] == 0
        assert group["alpha"] == 2
        assert group["beta"] == 1

    def test_record_unknown_group_false(self):
        engine = _engine()
        assert engine.record_outcome("test-exp", "ghost", True) is False

    def test_record_unknown_exp_false(self):
        engine = _engine()
        assert engine.record_outcome("nope", "control", True) is False

    def test_alpha_beta_priors(self):
        stats = _engine().get_stats("test-exp")
        for g in stats["groups"]:
            assert g["alpha"] == 1
            assert g["beta"] == 1


class TestThompson:
    def test_select_winner_returns_group_name(self):
        engine = _engine()
        winner = engine.select_winner("test-exp")
        assert winner in {"control", "treatment"}

    def test_select_winner_unknown_exp_none(self):
        assert _engine().select_winner("nope") is None


class TestDefaultEngine:
    def test_default_engine_has_experiments(self):
        from services.ab_test import build_default_engine
        stats = build_default_engine().get_stats()
        assert "rec-sort" in stats
        assert "copy-style" in stats

    def test_get_stats_shape(self):
        engine = _engine()
        stats = engine.get_stats()
        assert "test-exp" in stats
