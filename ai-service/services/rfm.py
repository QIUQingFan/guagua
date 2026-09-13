"""RFM 分位分箱：将归一化 RFM 分数映射到 1-5 档，并推导用户分群。"""
from __future__ import annotations

from typing import Dict

_QUANTILES = (0.2, 0.4, 0.6, 0.8)


def level(value: float) -> int:
    value = max(0.0, min(1.0, float(value)))
    for i, q in enumerate(_QUANTILES, start=1):
        if value < q:
            return i
    return 5


def levels(rfm: Dict[str, float]) -> Dict[str, int]:
    return {
        "recency": level(rfm.get("recency", 0.0)),
        "frequency": level(rfm.get("frequency", 0.0)),
        "monetary": level(rfm.get("monetary", 0.0)),
    }


def segment(rfm: Dict[str, float], has_purchase: bool) -> str:
    lv = levels(rfm)
    r, f, m = lv["recency"], lv["frequency"], lv["monetary"]
    if not has_purchase:
        return "new_user"
    if r <= 2:
        return "churn_risk"
    if r >= 4 and m >= 4:
        return "high_value"
    if m <= 2 and f >= 3:
        return "price_sensitive"
    return "active"
