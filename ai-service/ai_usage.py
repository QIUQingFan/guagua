"""AI 调用量统计模块"""
from __future__ import annotations

from datetime import datetime, time, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import text

from database import engine

TZ = timezone(timedelta(hours=8))

RANGE_DAYS = {"today": 1, "7d": 7, "30d": 30}


def _to_int(value: Any) -> int:
    if value is None:
        return 0
    return int(value)


def _to_float(value: Any) -> float:
    if value is None:
        return 0.0
    return float(value)


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


def _latest_message_time(conn) -> Optional[datetime]:
    row = conn.execute(
        text("SELECT MAX(created_at) AS latest FROM ai_messages WHERE role = 'assistant'")
    ).mappings().first()
    if not row or row["latest"] is None:
        return None
    latest = row["latest"]
    if latest.tzinfo is not None:
        latest = latest.astimezone(TZ).replace(tzinfo=None)
    return latest


def _query_summary(conn, start_dt: datetime, end_dt: datetime) -> Dict[str, Any]:
    row = conn.execute(
        text(
            """
            SELECT
                COUNT(*) AS total_calls,
                COALESCE(SUM(token_input), 0) AS total_token_input,
                COALESCE(SUM(token_output), 0) AS total_token_output,
                COALESCE(AVG(latency_ms), 0) AS avg_latency_ms,
                COALESCE(MAX(latency_ms), 0) AS max_latency_ms,
                SUM(CASE WHEN token_input IS NOT NULL THEN 1 ELSE 0 END) AS calls_with_token
            FROM ai_messages
            WHERE role = 'assistant'
              AND created_at >= :s
              AND created_at < :e
            """
        ),
        {"s": start_dt, "e": end_dt},
    ).mappings().one()

    total_calls = _to_int(row["total_calls"])
    calls_with_token = _to_int(row["calls_with_token"])
    return {
        "totalCalls": total_calls,
        "totalTokenInput": _to_int(row["total_token_input"]),
        "totalTokenOutput": _to_int(row["total_token_output"]),
        "totalTokens": _to_int(row["total_token_input"]) + _to_int(row["total_token_output"]),
        "avgLatencyMs": round(_to_float(row["avg_latency_ms"]), 1),
        "maxLatencyMs": _to_int(row["max_latency_ms"]),
        "tokenCoverage": round(calls_with_token / total_calls, 4) if total_calls else 0,
    }


def _query_p95_latency(conn, start_dt: datetime, end_dt: datetime) -> int:
    """近似 p95：按 latency_ms 升序，取第 95% 位置的值。

    MySQL 8 无原生 PERCENTILE_CONT，用子查询 + LIMIT OFFSET 近似。
    数据量小（< 100 行）时退化为取最大值，足够看板展示。
    """
    total = conn.execute(
        text(
            """
            SELECT COUNT(*) AS n
            FROM ai_messages
            WHERE role = 'assistant'
              AND latency_ms IS NOT NULL
              AND created_at >= :s
              AND created_at < :e
            """
        ),
        {"s": start_dt, "e": end_dt},
    ).scalar()
    total = _to_int(total)
    if total == 0:
        return 0
    if total < 20:
        return _to_int(
            conn.execute(
                text(
                    """
                    SELECT COALESCE(MAX(latency_ms), 0) AS v
                    FROM ai_messages
                    WHERE role = 'assistant' AND latency_ms IS NOT NULL
                      AND created_at >= :s AND created_at < :e
                    """
                ),
                {"s": start_dt, "e": end_dt},
            ).scalar()
        )
    offset = max(0, int(total * 0.95) - 1)
    return _to_int(
        conn.execute(
            text(
                """
                SELECT latency_ms AS v
                FROM ai_messages
                WHERE role = 'assistant' AND latency_ms IS NOT NULL
                  AND created_at >= :s AND created_at < :e
                ORDER BY latency_ms ASC
                LIMIT 1 OFFSET :off
                """
            ),
            {"s": start_dt, "e": end_dt, "off": offset},
        ).scalar()
    )


def _query_route_distribution(conn, start_dt: datetime, end_dt: datetime) -> List[Dict[str, Any]]:
    rows = conn.execute(
        text(
            """
            SELECT
                COALESCE(NULLIF(route, ''), 'unknown') AS route,
                COUNT(*) AS calls,
                COALESCE(AVG(latency_ms), 0) AS avg_latency_ms,
                COALESCE(SUM(token_input + token_output), 0) AS total_tokens
            FROM ai_messages
            WHERE role = 'assistant'
              AND created_at >= :s
              AND created_at < :e
            GROUP BY COALESCE(NULLIF(route, ''), 'unknown')
            ORDER BY calls DESC
            """
        ),
        {"s": start_dt, "e": end_dt},
    ).mappings().all()
    return [
        {
            "route": r["route"],
            "calls": _to_int(r["calls"]),
            "avgLatencyMs": round(_to_float(r["avg_latency_ms"]), 1),
            "totalTokens": _to_int(r["total_tokens"]),
        }
        for r in rows
    ]


def _query_daily_trends(conn, start_dt: datetime, end_dt: datetime) -> List[Dict[str, Any]]:
    rows = conn.execute(
        text(
            """
            SELECT
                DATE(created_at) AS stat_date,
                COUNT(*) AS calls,
                COALESCE(SUM(token_input), 0) AS token_input,
                COALESCE(SUM(token_output), 0) AS token_output,
                COALESCE(AVG(latency_ms), 0) AS avg_latency_ms
            FROM ai_messages
            WHERE role = 'assistant'
              AND created_at >= :s
              AND created_at < :e
            GROUP BY DATE(created_at)
            ORDER BY stat_date
            """
        ),
        {"s": start_dt, "e": end_dt},
    ).mappings().all()

    indexed = {
        r["stat_date"].isoformat(): {
            "date": r["stat_date"].isoformat(),
            "calls": _to_int(r["calls"]),
            "tokenInput": _to_int(r["token_input"]),
            "tokenOutput": _to_int(r["token_output"]),
            "avgLatencyMs": round(_to_float(r["avg_latency_ms"]), 1),
        }
        for r in rows
    }

    trends: List[Dict[str, Any]] = []
    cursor = start_dt.date()
    end_date = end_dt.date()
    while cursor < end_date:
        key = cursor.isoformat()
        trends.append(
            indexed.get(
                key,
                {
                    "date": key,
                    "calls": 0,
                    "tokenInput": 0,
                    "tokenOutput": 0,
                    "avgLatencyMs": 0,
                },
            )
        )
        cursor += timedelta(days=1)
    return trends


def _query_action_summary(conn, start_dt: datetime, end_dt: datetime) -> Dict[str, Any]:
    rows = conn.execute(
        text(
            """
            SELECT
                action_type,
                execute_status,
                COUNT(*) AS n
            FROM ai_action_logs
            WHERE created_at >= :s
              AND created_at < :e
            GROUP BY action_type, execute_status
            """
        ),
        {"s": start_dt, "e": end_dt},
    ).mappings().all()
    by_type: Dict[str, int] = {}
    by_status: Dict[str, int] = {}
    total = 0
    for r in rows:
        total += _to_int(r["n"])
        by_type[r["action_type"] or "unknown"] = (
            by_type.get(r["action_type"] or "unknown", 0) + _to_int(r["n"])
        )
        by_status[r["execute_status"] or "unknown"] = (
            by_status.get(r["execute_status"] or "unknown", 0) + _to_int(r["n"])
        )
    return {
        "totalTriggers": total,
        "byType": by_type,
        "byStatus": by_status,
    }


def _query_feedback_summary(conn, start_dt: datetime, end_dt: datetime) -> Dict[str, Any]:
    row = conn.execute(
        text(
            """
            SELECT
                SUM(CASE WHEN rating > 0 THEN 1 ELSE 0 END) AS likes,
                SUM(CASE WHEN rating < 0 THEN 1 ELSE 0 END) AS dislikes
            FROM ai_feedbacks
            WHERE created_at >= :s
              AND created_at < :e
            """
        ),
        {"s": start_dt, "e": end_dt},
    ).mappings().one()
    likes = _to_int(row["likes"])
    dislikes = _to_int(row["dislikes"])
    total = likes + dislikes
    return {
        "likes": likes,
        "dislikes": dislikes,
        "total": total,
        "likeRate": round(likes / total, 4) if total else 0,
    }


def get_ai_usage_snapshot(
    range_key: str = "7d",
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
) -> Dict[str, Any]:
    """生成 AI 调用量统计快照"""
    normalized_range, start_dt, end_dt, calendar_anchor = _resolve_range(
        range_key, start_date=start_date, end_date=end_date
    )
    is_custom = normalized_range == "custom"

    with engine.connect() as conn:
        summary = _query_summary(conn, start_dt, end_dt)
        latest_data_at = _latest_message_time(conn)
        range_anchored_at: Optional[str] = None

        if (not is_custom) and summary["totalCalls"] == 0 and latest_data_at is not None:
            in_window = start_dt <= latest_data_at < end_dt
            if not in_window:
                _, start_dt, end_dt, anchor_date = _resolve_range(range_key, anchor=latest_data_at)
                range_anchored_at = anchor_date.isoformat()
                summary = _query_summary(conn, start_dt, end_dt)

        p95 = _query_p95_latency(conn, start_dt, end_dt)
        route_dist = _query_route_distribution(conn, start_dt, end_dt)
        trends = _query_daily_trends(conn, start_dt, end_dt)
        actions = _query_action_summary(conn, start_dt, end_dt)
        feedback = _query_feedback_summary(conn, start_dt, end_dt)

        snapshot = {
            "range": normalized_range,
            "rangeAnchoredAt": range_anchored_at,
            "latestDataAt": latest_data_at.strftime("%Y-%m-%d %H:%M:%S") if latest_data_at else None,
            "generatedAt": datetime.now(TZ).strftime("%Y-%m-%d %H:%M:%S"),
            "summary": {**summary, "p95LatencyMs": p95},
            "routeDistribution": route_dist,
            "trends": trends,
            "actionSummary": actions,
            "feedbackSummary": feedback,
        }

    alerts: List[str] = []
    if range_anchored_at:
        alerts.append(
            f"选定日历区间内无 AI 调用数据，已自动回退到以最新数据时间（{range_anchored_at}）"
            f"为锚点的近 {RANGE_DAYS[normalized_range]} 天数据。"
        )
    if latest_data_at is None and summary["totalCalls"] == 0:
        alerts.append(
            "ai_messages 表暂无 assistant 消息，请确认：①AI_PERSIST_CONVERSATION=python 已开启；"
            "②已产生过对话；③token 字段在历史数据中可能为 NULL，统计会做友好降级。"
        )
    if summary["totalCalls"] > 0 and summary["tokenCoverage"] < 0.5:
        alerts.append(
            f"token 覆盖率仅 {summary['tokenCoverage'] * 100:.1f}%，多数历史消息未落库 token 用量，"
            "新数据将自动补齐。"
        )
    snapshot["alerts"] = alerts
    return snapshot
