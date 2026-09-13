"""A-B 测试通用引擎"""
from __future__ import annotations

import hashlib
import logging
import random
from typing import Dict, List, Optional

logger = logging.getLogger("ab_test")


class ExperimentGroup:
    def __init__(self, name: str, weight: float = 1.0, config: Optional[dict] = None):
        self.name = name
        self.weight = float(weight)
        self.config = config or {}
        self.successes = 0
        self.failures = 0

    @property
    def alpha(self) -> int:
        return self.successes + 1

    @property
    def beta(self) -> int:
        return self.failures + 1

    def record(self, success: bool) -> None:
        if success:
            self.successes += 1
        else:
            self.failures += 1

    def sample(self) -> float:
        return random.betavariate(self.alpha, self.beta)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "weight": self.weight,
            "config": self.config,
            "successes": self.successes,
            "failures": self.failures,
            "alpha": self.alpha,
            "beta": self.beta,
        }


class Experiment:
    def __init__(self, exp_id: str, dim: str, groups: List[ExperimentGroup]):
        self.exp_id = exp_id
        self.dim = dim
        self.groups = groups

    def bucket(self, user_id) -> int:
        return int(hashlib.md5(str(user_id).encode("utf-8")).hexdigest(), 16) % 100

    def assign(self, user_id) -> ExperimentGroup:
        bucket = self.bucket(user_id)
        total = sum(g.weight for g in self.groups)
        acc = 0.0
        for g in self.groups:
            acc += (g.weight / total) * 100
            if bucket < acc:
                return g
        return self.groups[-1]

    def winner(self) -> str:
        return max(self.groups, key=lambda g: g.sample()).name

    def stats(self) -> dict:
        return {
            "exp_id": self.exp_id,
            "dim": self.dim,
            "groups": [g.to_dict() for g in self.groups],
        }


class ABTestEngine:
    def __init__(self):
        self.experiments: Dict[str, Experiment] = {}

    def register_experiment(self, exp_id: str, dim: str, groups: List[dict]) -> "ABTestEngine":
        grp = [ExperimentGroup(g["name"], g.get("weight", 1.0), g.get("config")) for g in groups]
        self.experiments[exp_id] = Experiment(exp_id, dim, grp)
        return self

    def assign(self, exp_id: str, user_id) -> dict:
        exp = self.experiments.get(exp_id)
        if exp is None:
            return {"exp_id": exp_id, "group": "control", "config": {}}
        group = exp.assign(user_id)
        return {"exp_id": exp_id, "group": group.name, "config": group.config}

    def record_outcome(self, exp_id: str, group: str, success: bool) -> bool:
        exp = self.experiments.get(exp_id)
        if exp is None:
            return False
        for g in exp.groups:
            if g.name == group:
                g.record(bool(success))
                return True
        return False

    def get_stats(self, exp_id: Optional[str] = None):
        if exp_id:
            exp = self.experiments.get(exp_id)
            return exp.stats() if exp else None
        return {eid: e.stats() for eid, e in self.experiments.items()}

    def select_winner(self, exp_id: str) -> Optional[str]:
        exp = self.experiments.get(exp_id)
        return exp.winner() if exp else None


_default_engine: Optional[ABTestEngine] = None


def build_default_engine() -> ABTestEngine:
    global _default_engine
    if _default_engine is None:
        engine = ABTestEngine()
        engine.register_experiment(
            "rec-sort",
            dim="排序策略",
            groups=[
                {"name": "sales", "weight": 1.0, "config": {"strategy": "sales_desc"}},
                {"name": "llm_rerank", "weight": 1.0, "config": {"strategy": "llm"}},
                {"name": "price", "weight": 1.0, "config": {"strategy": "price_asc"}},
            ],
        )
        engine.register_experiment(
            "copy-style",
            dim="文案模板",
            groups=[
                {"name": "generic", "weight": 1.0, "config": {"mode": "generic"}},
                {"name": "personalized", "weight": 1.0, "config": {"mode": "personalized"}},
            ],
        )
        _default_engine = engine
    return _default_engine


def get_default_engine() -> ABTestEngine:
    if _default_engine is None:
        return build_default_engine()
    return _default_engine
