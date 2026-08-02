"""
用户行为分析模块
"""
from __future__ import annotations

from datetime import datetime, time, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import text

from database import engine
from guagua_adapter import paid_statuses_sql

TZ = timezone(timedelta(hours=8))

RANGE_DAYS = {"today": 1, "7d": 7, "30d": 30}

ALLOWED_ACTIONS = {"view", "cart", "purchase", "recommend_click", "ai_recommend"}


def _to_int(value: Any) -> int:
    if value is None:
        return 0
    return int(value)


def _resolve_range(
    range_key: str = "7d",
    anchor: Optional[datetime] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
) -> Tuple[str, datetime, datetime]:
    if start_date and end_date:
        try:
            s = datetime.strptime(start_date, "%Y-%m-%d")
            e = datetime.strptime(end_date, "%Y-%m-%d")
            if e < s:
                s, e = e, s
            end_dt = datetime.combine(e + timedelta(days=1), time.min)
            return "custom", s, end_dt
        except ValueError:
            pass
    normalized = range_key if range_key in RANGE_DAYS else "7d"
    days = RANGE_DAYS[normalized]
    anchor_date = (anchor.date() if anchor else datetime.now(TZ).date())
    start_date = anchor_date - timedelta(days=days - 1)
    start_dt = datetime.combine(start_date, time.min)
    end_dt = datetime.combine(anchor_date + timedelta(days=1), time.min)
    return normalized, start_dt, end_dt


def _latest_behavior_time(conn) -> Optional[datetime]:
    row = conn.execute(
        text("SELECT MAX(created_at) AS latest FROM ai_user_behaviors")
    ).mappings().first()
    if not row or row["latest"] is None:
        return None
    latest = row["latest"]
    if latest.tzinfo is not None:
        latest = latest.astimezone(TZ).replace(tzinfo=None)
    return latest


def report_behavior(
    user_id: Optional[int],
    session_key: Optional[str],
    product_id: Optional[int],
    action: str,
    source: str = "manual",
    context: Optional[dict] = None,
) -> int:
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"非法行为类型: {action}，允许: {ALLOWED_ACTIONS}")
    if product_id is None:
        raise ValueError("product_id 不能为空")

    import json
    with engine.begin() as conn:
        result = conn.execute(
            text(
                """
                INSERT INTO ai_user_behaviors
                    (user_id, session_key, product_id, action, source, context)
                VALUES
                    (:uid, :sk, :pid, :act, :src, :ctx)
                """
            ),
            {
                "uid": user_id,
                "sk": session_key,
                "pid": product_id,
                "act": action,
                "src": source if source in ("manual", "ai") else "manual",
                "ctx": json.dumps(context, ensure_ascii=False) if context else None,
            },
        )
        return int(result.lastrowid)


def _query_funnel(conn, start_dt: datetime, end_dt: datetime) -> Dict[str, Any]:
    views = conn.execute(
        text("""
            SELECT COUNT(DISTINCT CONCAT(COALESCE(user_id, 0), '-', COALESCE(session_key, ''), '-', product_id))
            FROM ai_user_behaviors
            WHERE action = 'view'
              AND created_at >= :s AND created_at < :e
        """),
        {"s": start_dt, "e": end_dt},
    ).scalar()
    carts = conn.execute(
        text("""
            SELECT COUNT(DISTINCT CONCAT(COALESCE(user_id, 0), '-', COALESCE(session_key, ''), '-', product_id))
            FROM ai_user_behaviors
            WHERE action = 'cart'
              AND created_at >= :s AND created_at < :e
        """),
        {"s": start_dt, "e": end_dt},
    ).scalar()
    paid_str = paid_statuses_sql()
    purchases = conn.execute(
        text(f"""
            SELECT COUNT(DISTINCT CONCAT(o.user_id, '-', oi.product_id))
            FROM order_items oi
            JOIN orders o ON oi.order_id = o.id
            WHERE o.is_deleted = 0
              AND o.status IN ({paid_str})
              AND o.created_at >= :s AND o.created_at < :e
        """),
        {"s": start_dt, "e": end_dt},
    ).scalar()

    v, c, p = _to_int(views), _to_int(carts), _to_int(purchases)
    return {
        "views": v,
        "carts": c,
        "purchases": p,
        "viewToCartRate": round(c / v, 4) if v else 0,
        "cartToPurchaseRate": round(p / c, 4) if c else 0,
        "overallConversionRate": round(p / v, 4) if v else 0,
    }


def _query_behavior_topn(conn, start_dt: datetime, end_dt: datetime, action: str, limit: int = 10) -> List[Dict[str, Any]]:
    """按行为聚合商品 TopN
    """
    rows = conn.execute(
        text("""
            SELECT
                b.product_id,
                p.title AS name,
                p.cover_image,
                p.price,
                p.stock,
                COUNT(*) AS action_count,
                COUNT(DISTINCT CONCAT(COALESCE(b.user_id, 0), '-', COALESCE(b.session_key, ''))) AS user_count
            FROM ai_user_behaviors b
            LEFT JOIN products p ON b.product_id = p.id
            WHERE b.action = :act
              AND b.created_at >= :s AND b.created_at < :e
            GROUP BY b.product_id, p.title, p.cover_image, p.price, p.stock
            ORDER BY action_count DESC
            LIMIT :limit
        """),
        {"act": action, "s": start_dt, "e": end_dt, "limit": limit},
    ).mappings().all()
    return [
        {
            "productId": r["product_id"],
            "name": r["name"] or f"商品#{r['product_id']}",
            "coverImage": r["cover_image"] or "",
            "price": float(r["price"]) if r["price"] is not None else 0,
            "stock": _to_int(r["stock"]),
            "actionCount": _to_int(r["action_count"]),
            "userCount": _to_int(r["user_count"]),
        }
        for r in rows
    ]


def _query_daily_trends(conn, start_dt: datetime, end_dt: datetime) -> List[Dict[str, Any]]:
    rows = conn.execute(
        text("""
            SELECT
                DATE(created_at) AS stat_date,
                SUM(CASE WHEN action = 'view' THEN 1 ELSE 0 END) AS views,
                SUM(CASE WHEN action = 'cart' THEN 1 ELSE 0 END) AS carts,
                SUM(CASE WHEN action = 'recommend_click' THEN 1 ELSE 0 END) AS clicks
            FROM ai_user_behaviors
            WHERE created_at >= :s AND created_at < :e
            GROUP BY DATE(created_at)
            ORDER BY stat_date
        """),
        {"s": start_dt, "e": end_dt},
    ).mappings().all()

    paid_str = paid_statuses_sql()
    purch_rows = conn.execute(
        text(f"""
            SELECT
                DATE(o.created_at) AS stat_date,
                COUNT(DISTINCT CONCAT(o.user_id, '-', oi.product_id)) AS purchases
            FROM order_items oi
            JOIN orders o ON oi.order_id = o.id
            WHERE o.is_deleted = 0
              AND o.status IN ({paid_str})
              AND o.created_at >= :s AND o.created_at < :e
            GROUP BY DATE(o.created_at)
        """),
        {"s": start_dt, "e": end_dt},
    ).mappings().all()
    purch_index = {r["stat_date"].isoformat(): _to_int(r["purchases"]) for r in purch_rows}

    indexed = {
        r["stat_date"].isoformat(): {
            "views": _to_int(r["views"]),
            "carts": _to_int(r["carts"]),
            "clicks": _to_int(r["clicks"]),
        }
        for r in rows
    }

    trends: List[Dict[str, Any]] = []
    cursor = start_dt.date()
    end_date = end_dt.date()
    while cursor < end_date:
        key = cursor.isoformat()
        item = indexed.get(key, {"views": 0, "carts": 0, "clicks": 0})
        item["date"] = key
        item["purchases"] = purch_index.get(key, 0)
        trends.append(item)
        cursor += timedelta(days=1)
    return trends


def _query_ai_recommend(conn, start_dt: datetime, end_dt: datetime) -> Dict[str, Any]:
    exposures = conn.execute(
        text("""
            SELECT COUNT(*) FROM ai_user_behaviors
            WHERE action = 'ai_recommend'
              AND created_at >= :s AND created_at < :e
        """),
        {"s": start_dt, "e": end_dt},
    ).scalar()
    clicks = conn.execute(
        text("""
            SELECT COUNT(*) FROM ai_user_behaviors
            WHERE action = 'recommend_click'
              AND created_at >= :s AND created_at < :e
        """),
        {"s": start_dt, "e": end_dt},
    ).scalar()
    e, c = _to_int(exposures), _to_int(clicks)
    return {
        "exposures": e,
        "clicks": c,
        "ctr": round(c / e, 4) if e else 0,
    }


def get_behavior_snapshot(
    range_key: str = "7d",
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
) -> Dict[str, Any]:
    normalized_range, start_dt, end_dt = _resolve_range(range_key, start_date=start_date, end_date=end_date)
    is_custom = normalized_range == "custom"

    with engine.connect() as conn:
        funnel = _query_funnel(conn, start_dt, end_dt)
        latest_data_at = _latest_behavior_time(conn)
        range_anchored_at: Optional[str] = None

        if (not is_custom) and funnel["views"] == 0 and funnel["carts"] == 0 and latest_data_at is not None:
            in_window = start_dt <= latest_data_at < end_dt
            if not in_window:
                _, start_dt, end_dt = _resolve_range(range_key, anchor=latest_data_at)
                range_anchored_at = latest_data_at.date().isoformat()
                funnel = _query_funnel(conn, start_dt, end_dt)

        top_viewed = _query_behavior_topn(conn, start_dt, end_dt, "view")
        top_carted = _query_behavior_topn(conn, start_dt, end_dt, "cart")
        trends = _query_daily_trends(conn, start_dt, end_dt)
        ai_recommend = _query_ai_recommend(conn, start_dt, end_dt)

        snapshot = {
            "range": normalized_range,
            "rangeAnchoredAt": range_anchored_at,
            "latestDataAt": latest_data_at.strftime("%Y-%m-%d %H:%M:%S") if latest_data_at else None,
            "generatedAt": datetime.now(TZ).strftime("%Y-%m-%d %H:%M:%S"),
            "funnel": funnel,
            "behaviorTopN": {"viewed": top_viewed, "carted": top_carted},
            "trends": trends,
            "aiRecommend": ai_recommend,
        }

    alerts: List[str] = []
    if range_anchored_at:
        alerts.append(
            f"选定日历区间内无行为数据，已自动回退到以最新行为时间（{range_anchored_at}）"
            f"为锚点的近 {RANGE_DAYS[normalized_range]} 天数据。"
        )
    if latest_data_at is None and funnel["views"] == 0 and funnel["carts"] == 0:
        alerts.append(
            "ai_user_behaviors 表暂无行为数据。请确认：①前端 ProductDetail/Cart 已上报 view/cart 行为；"
            "②POST /ai/behavior 接口可达；③历史数据可能为空，新行为将自动落库。"
        )
    if funnel["views"] >= 20 and funnel["viewToCartRate"] < 0.1:
        alerts.append("浏览到加购转化偏低，建议优化商品详情页卖点与价格展示。")
    if ai_recommend["exposures"] >= 10 and ai_recommend["ctr"] < 0.05:
        alerts.append("AI 推荐点击率偏低，建议优化推荐位选品与展示样式。")
    snapshot["alerts"] = alerts
    return snapshot
