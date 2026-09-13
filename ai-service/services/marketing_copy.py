"""营销文案子能力：模板库 × 用户分群 + 广告法合规过滤。"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

_TEMPLATES = {
    "new_user": "新客专属：{name} 现价 ¥{price:.0f}，首单立享优惠。",
    "active": "根据您的浏览偏好，为您精选 {name}，好评率 98%。",
    "high_value": "尊享会员精选：{name} ¥{price:.0f}，品质之选。",
    "price_sensitive": "限时好价：{name} 仅 ¥{price:.0f}，库存不多，快入手。",
    "churn_risk": "好久不见！{name} 为您保留特惠价 ¥{price:.0f}。",
}

_GENERIC_TEMPLATE = _TEMPLATES["active"]

_BANNED_WORDS = ["最好", "第一", "最便宜", "绝对", "100%"]


def _comply(text: str) -> str:
    for word in _BANNED_WORDS:
        text = text.replace(word, "")
    return text


def _segment_of(profile: Optional[Dict[str, Any]]) -> str:
    segments = (profile or {}).get("segments") or ["active"]
    for s in segments:
        if s in _TEMPLATES:
            return s
    return "active"


def template_for(segment: str) -> str:
    return _TEMPLATES.get(segment, _GENERIC_TEMPLATE)


def generate(profile: Optional[Dict[str, Any]], products: List[Dict[str, Any]], personalized: bool = True) -> List[Dict[str, Any]]:
    """按用户分群为商品列表生成文案，返回 [{product_id, copy, segment}]。

    personalized=False 时统一使用通用模板（对应 A-B 对照组）。
    """
    segment = _segment_of(profile) if personalized else "active"
    template = _TEMPLATES[segment] if personalized else _GENERIC_TEMPLATE
    copies = []
    for p in products:
        name = p.get("name") or f"商品#{p.get('id') or p.get('product_id')}"
        price = float(p.get("price") or 0)
        text = _comply(template.format(name=name, price=price))
        copies.append({
            "product_id": p.get("id") or p.get("product_id"),
            "copy": text,
            "segment": segment,
        })
    return copies
