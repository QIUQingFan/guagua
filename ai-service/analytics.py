"""
经营分析模块
"""
from __future__ import annotations

from datetime import datetime, time, timedelta, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import text

from database import engine
from guagua_adapter import ORDER_STATUS_LABELS, PAID_STATUSES, paid_statuses_sql

TZ = timezone(timedelta(hours=8))

RANGE_DAYS = {
    "today": 1,
    "7d": 7,
    "30d": 30,
}


def _to_float(value: Any) -> float:
    if value is None:
        return 0.0
    if isinstance(value, Decimal):
        return float(value)
    return float(value)


def _to_int(value: Any) -> int:
    if value is None:
        return 0
    return int(value)


def _latest_order_time(conn) -> Optional[datetime]:
    """查询 orders 表最新一笔数据的 created_at"""
    row = conn.execute(
        text("SELECT MAX(created_at) AS latest FROM orders WHERE is_deleted = 0")
    ).mappings().first()
    if not row or row["latest"] is None:
        return None
    latest = row["latest"]
    if latest.tzinfo is not None:
        latest = latest.astimezone(TZ).replace(tzinfo=None)
    return latest


def _resolve_range(
    range_key: str = "7d",
    anchor: Optional[datetime] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
) -> Tuple[str, datetime, datetime, Optional[datetime.date]]:
    if start_date and end_date:
        try:
            s = datetime.strptime(start_date, "%Y-%m-%d")
            e = datetime.strptime(end_date, "%Y-%m-%d")
            if e < s:
                s, e = e, s
            end_dt = datetime.combine(e + timedelta(days=1), time.min)
            return "custom", s, end_dt, s.date()
        except ValueError:
            pass

    normalized = range_key if range_key in RANGE_DAYS else "7d"
    days = RANGE_DAYS[normalized]
    anchor_date = (anchor.date() if anchor else datetime.now(TZ).date())
    start_date = anchor_date - timedelta(days=days - 1)
    start_dt = datetime.combine(start_date, time.min)
    end_dt = datetime.combine(anchor_date + timedelta(days=1), time.min)
    return normalized, start_dt, end_dt, anchor_date


def _query_summary(conn, start_dt: datetime, end_dt: datetime) -> Dict[str, Any]:
    paid_str = paid_statuses_sql()

    row = conn.execute(
        text(f"""
            SELECT
                COUNT(*) AS total_orders,
                SUM(CASE WHEN status IN ({paid_str}) THEN 1 ELSE 0 END) AS paid_orders,
                SUM(CASE WHEN status = 'pending_payment' THEN 1 ELSE 0 END) AS pending_orders,
                COALESCE(SUM(CASE WHEN status IN ({paid_str}) THEN pay_amount ELSE 0 END), 0) AS total_revenue
            FROM orders
            WHERE is_deleted = 0
              AND created_at >= :start_dt
              AND created_at < :end_dt
        """),
        {"start_dt": start_dt, "end_dt": end_dt},
    ).mappings().one()

    new_users = conn.execute(
        text("""
            SELECT COUNT(*) AS cnt
            FROM users
            WHERE created_at >= :start_dt
              AND created_at < :end_dt
        """),
        {"start_dt": start_dt, "end_dt": end_dt},
    ).scalar()

    repeat_buyers = conn.execute(
        text(f"""
            SELECT COUNT(*) FROM (
                SELECT user_id
                FROM orders
                WHERE is_deleted = 0
                  AND status IN ({paid_str})
                  AND created_at >= :start_dt
                  AND created_at < :end_dt
                GROUP BY user_id
                HAVING COUNT(*) >= 2
            ) t
        """),
        {"start_dt": start_dt, "end_dt": end_dt},
    ).scalar()

    total_orders = _to_int(row["total_orders"])
    paid_orders = _to_int(row["paid_orders"])
    total_revenue = _to_float(row["total_revenue"])

    return {
        "totalOrders": total_orders,
        "paidOrders": paid_orders,
        "pendingOrders": _to_int(row["pending_orders"]),
        "totalRevenue": total_revenue,
        "payRate": round(paid_orders / total_orders, 4) if total_orders else 0,
        "avgOrderValue": round(total_revenue / paid_orders, 2) if paid_orders else 0,
        "newUsers": _to_int(new_users),
        "repeatBuyers": _to_int(repeat_buyers),
    }


def _query_trends(conn, start_dt: datetime, end_dt: datetime) -> List[Dict[str, Any]]:
    paid_str = paid_statuses_sql()
    rows = conn.execute(
        text(f"""
            SELECT
                DATE(created_at) AS stat_date,
                COUNT(*) AS total_orders,
                SUM(CASE WHEN status IN ({paid_str}) THEN 1 ELSE 0 END) AS paid_orders,
                COALESCE(SUM(CASE WHEN status IN ({paid_str}) THEN pay_amount ELSE 0 END), 0) AS total_revenue
            FROM orders
            WHERE is_deleted = 0
              AND created_at >= :start_dt
              AND created_at < :end_dt
            GROUP BY DATE(created_at)
            ORDER BY stat_date
        """),
        {"start_dt": start_dt, "end_dt": end_dt},
    ).mappings().all()

    indexed = {
        row["stat_date"].isoformat(): {
            "date": row["stat_date"].isoformat(),
            "totalOrders": _to_int(row["total_orders"]),
            "paidOrders": _to_int(row["paid_orders"]),
            "totalRevenue": _to_float(row["total_revenue"]),
        }
        for row in rows
    }

    trends: List[Dict[str, Any]] = []
    cursor = start_dt.date()
    end_date = end_dt.date()
    while cursor < end_date:
        key = cursor.isoformat()
        item = indexed.get(
            key,
            {"date": key, "totalOrders": 0, "paidOrders": 0, "totalRevenue": 0.0},
        )
        paid_orders = item["paidOrders"]
        item["avgOrderValue"] = round(item["totalRevenue"] / paid_orders, 2) if paid_orders else 0
        trends.append(item)
        cursor += timedelta(days=1)
    return trends


def _query_status_distribution(conn, start_dt: datetime, end_dt: datetime) -> List[Dict[str, Any]]:
    rows = conn.execute(
        text("""
            SELECT status, COUNT(*) AS cnt
            FROM orders
            WHERE is_deleted = 0
              AND created_at >= :start_dt
              AND created_at < :end_dt
            GROUP BY status
        """),
        {"start_dt": start_dt, "end_dt": end_dt},
    ).mappings().all()

    distribution = []
    for status, label in ORDER_STATUS_LABELS.items():
        count = next((_to_int(row["cnt"]) for row in rows if row["status"] == status), 0)
        distribution.append({"status": status, "label": label, "count": count})
    return distribution


def _query_hot_products(conn, start_dt: datetime, end_dt: datetime, limit: int = 5) -> List[Dict[str, Any]]:
    paid_str = paid_statuses_sql()
    rows = conn.execute(
        text(f"""
            SELECT
                p.id,
                p.title AS name,
                p.cover_image,
                p.stock,
                p.price,
                COALESCE(SUM(oi.quantity), 0) AS total_quantity,
                COALESCE(SUM(oi.subtotal), 0) AS total_revenue
            FROM order_items oi
            JOIN orders o ON oi.order_id = o.id
            JOIN products p ON oi.product_id = p.id
            WHERE o.is_deleted = 0
              AND oi.product_id IS NOT NULL
              AND o.status IN ({paid_str})
              AND o.created_at >= :start_dt
              AND o.created_at < :end_dt
            GROUP BY p.id, p.title, p.cover_image, p.stock, p.price
            ORDER BY total_quantity DESC, total_revenue DESC
            LIMIT :limit
        """),
        {"start_dt": start_dt, "end_dt": end_dt, "limit": limit},
    ).mappings().all()

    return [
        {
            "id": row["id"],
            "name": row["name"],
            "coverImage": row["cover_image"] or "",
            "stock": _to_int(row["stock"]),
            "price": _to_float(row["price"]),
            "quantity": _to_int(row["total_quantity"]),
            "revenue": _to_float(row["total_revenue"]),
        }
        for row in rows
    ]


def _query_recent_orders(conn, start_dt: datetime, end_dt: datetime, limit: int = 10) -> List[Dict[str, Any]]:
    rows = conn.execute(
        text("""
            SELECT order_no, receiver, status, pay_amount, total_amount, created_at
            FROM orders
            WHERE is_deleted = 0
              AND created_at >= :start_dt
              AND created_at < :end_dt
            ORDER BY created_at DESC
            LIMIT :limit
        """),
        {"start_dt": start_dt, "end_dt": end_dt, "limit": limit},
    ).mappings().all()

    return [
        {
            "orderNo": row["order_no"],
            "receiverName": row["receiver"],
            "status": row["status"],
            "statusLabel": ORDER_STATUS_LABELS.get(row["status"], "未知"),
            "payAmount": _to_float(row["pay_amount"]),
            "totalAmount": _to_float(row["total_amount"]),
            "createTime": row["created_at"].strftime("%Y-%m-%d %H:%M") if row["created_at"] else "-",
        }
        for row in rows
    ]


def _query_funnel(conn, start_dt: datetime, end_dt: datetime) -> Dict[str, Any]:
    views = conn.execute(
        text("""
            SELECT COUNT(DISTINCT CONCAT(user_id, '-', product_id))
            FROM ai_user_behaviors
            WHERE action = 'view'
              AND created_at >= :start_dt
              AND created_at < :end_dt
        """),
        {"start_dt": start_dt, "end_dt": end_dt},
    ).scalar()

    carts = conn.execute(
        text("""
            SELECT COUNT(DISTINCT CONCAT(user_id, '-', product_id))
            FROM ai_user_behaviors
            WHERE action = 'cart'
              AND created_at >= :start_dt
              AND created_at < :end_dt
        """),
        {"start_dt": start_dt, "end_dt": end_dt},
    ).scalar()

    paid_str = paid_statuses_sql()
    purchases = conn.execute(
        text(f"""
            SELECT COUNT(DISTINCT CONCAT(o.user_id, '-', oi.product_id))
            FROM order_items oi
            JOIN orders o ON oi.order_id = o.id
            WHERE o.is_deleted = 0
              AND o.status IN ({paid_str})
              AND o.created_at >= :start_dt
              AND o.created_at < :end_dt
        """),
        {"start_dt": start_dt, "end_dt": end_dt},
    ).scalar()

    view_count = _to_int(views)
    cart_count = _to_int(carts)
    purchase_count = _to_int(purchases)

    return {
        "views": view_count,
        "carts": cart_count,
        "purchases": purchase_count,
        "viewToCartRate": round(cart_count / view_count, 4) if view_count else 0,
        "cartToPurchaseRate": round(purchase_count / cart_count, 4) if cart_count else 0,
    }


def _build_alerts(summary: Dict[str, Any], hot_products: List[Dict[str, Any]], funnel: Dict[str, Any]) -> List[str]:
    alerts: List[str] = []

    if summary["totalOrders"] and summary["payRate"] < 0.5:
        alerts.append("支付转化率偏低，待付款订单占比偏高，需要关注支付链路或价格竞争力。")

    if summary["pendingOrders"] > summary["paidOrders"] and summary["totalOrders"] >= 5:
        alerts.append("当前待付款订单多于已付款订单，建议检查结算体验与营销承接效果。")

    low_stock_hot = [item for item in hot_products if item["quantity"] > 0 and item["stock"] <= 10]
    if low_stock_hot:
        names = "、".join(item["name"] for item in low_stock_hot[:3])
        alerts.append(f"热销商品库存偏低：{names}，建议优先补货，避免断货影响成交。")

    if funnel["views"] >= 20 and funnel["viewToCartRate"] < 0.1:
        alerts.append("浏览到加购转化偏低，建议优化商品详情页卖点、价格展示和活动刺激。")

    if funnel["carts"] >= 5 and funnel["cartToPurchaseRate"] < 0.35:
        alerts.append("加购到支付转化偏低，建议检查结算流程、支付方式和优惠门槛设置。")

    return alerts


def get_dashboard_snapshot(
    range_key: str = "7d",
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
) -> Dict[str, Any]:
    normalized_range, start_dt, end_dt, calendar_anchor = _resolve_range(
        range_key, start_date=start_date, end_date=end_date
    )
    is_custom = normalized_range == "custom"

    with engine.connect() as conn:
        summary = _query_summary(conn, start_dt, end_dt)
        latest_data_at = _latest_order_time(conn)
        range_anchored_at: Optional[str] = None

        if (not is_custom) and summary["totalOrders"] == 0 and latest_data_at is not None:
            in_window = start_dt <= latest_data_at < end_dt
            if not in_window:
                _, start_dt, end_dt, anchor_date = _resolve_range(range_key, anchor=latest_data_at)
                range_anchored_at = anchor_date.isoformat()
                summary = _query_summary(conn, start_dt, end_dt)

        previous_start = start_dt - (end_dt - start_dt)
        previous_end = start_dt
        previous_summary = _query_summary(conn, previous_start, previous_end)

        hot_products = _query_hot_products(conn, start_dt, end_dt)
        funnel = _query_funnel(conn, start_dt, end_dt)

        snapshot = {
            "range": normalized_range,
            "rangeAnchoredAt": range_anchored_at,
            "latestDataAt": latest_data_at.strftime("%Y-%m-%d %H:%M:%S") if latest_data_at else None,
            "generatedAt": datetime.now(TZ).strftime("%Y-%m-%d %H:%M:%S"),
            "summary": summary,
            "comparison": {
                "ordersDelta": summary["totalOrders"] - previous_summary["totalOrders"],
                "revenueDelta": round(summary["totalRevenue"] - previous_summary["totalRevenue"], 2),
                "payRateDelta": round(summary["payRate"] - previous_summary["payRate"], 4),
                "avgOrderValueDelta": round(summary["avgOrderValue"] - previous_summary["avgOrderValue"], 2),
                "previousPeriod": {
                    "start": previous_start.strftime("%Y-%m-%d"),
                    "end": previous_end.strftime("%Y-%m-%d"),
                    "totalOrders": previous_summary["totalOrders"],
                    "totalRevenue": previous_summary["totalRevenue"],
                    "payRate": previous_summary["payRate"],
                },
            },
            "trends": _query_trends(conn, start_dt, end_dt),
            "previousTrends": _query_trends(conn, previous_start, previous_end),
            "statusDistribution": _query_status_distribution(conn, start_dt, end_dt),
            "hotProducts": hot_products,
            "recentOrders": _query_recent_orders(conn, start_dt, end_dt),
            "funnel": funnel,
        }

    alerts = _build_alerts(summary, hot_products, funnel)
    if range_anchored_at:
        alerts.append(
            f"选定日历区间内无订单数据，已自动回退到以最新数据时间（{range_anchored_at}）"
            f"为锚点的近 {RANGE_DAYS[normalized_range]} 天数据。如需查看实时数据，请确认订单是否正常写入。"
        )
    if latest_data_at is None and summary["totalOrders"] == 0:
        alerts.append("数据库中暂无订单数据，看板指标无法计算，请先确认订单数据来源与种子脚本是否执行。")
    snapshot["alerts"] = alerts
    return snapshot
