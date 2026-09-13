"""库存/限购/预警共享服务：纯规则，供购物顾问与客服助手共用。"""
from __future__ import annotations

from typing import Any, Dict, List

MIN_ALERT_STOCK = 2
LIMIT_THRESHOLD = 5
LIMIT_QUANTITY = 2


def decide(products: List[Dict[str, Any]]) -> Dict[str, Any]:
    """输入候选商品，输出可用 ids、限购策略、预警。"""
    available: List[int] = []
    limits: Dict[int, int] = {}
    alerts: List[Dict[str, Any]] = []
    for p in products:
        pid = p.get("id") or p.get("product_id")
        stock = int(p.get("stock") or 0)
        if pid is None or stock <= 0:
            continue
        available.append(pid)
        if stock < LIMIT_THRESHOLD:
            limits[pid] = LIMIT_QUANTITY
        if stock <= MIN_ALERT_STOCK:
            alerts.append({"product_id": pid, "stock": stock})
    return {"available": available, "limits": limits, "alerts": alerts}
