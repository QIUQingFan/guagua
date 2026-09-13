"""全链路 Trace"""
from __future__ import annotations

import contextvars
import functools
import json
import logging
import time
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from sqlalchemy import text

logger = logging.getLogger("trace")


def _get_engine():
    from database import engine
    return engine

_current_run_id: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar(
    "rag_trace_run_id", default=None
)
_current_seq: contextvars.ContextVar[int] = contextvars.ContextVar(
    "rag_trace_seq", default=0
)

_SUMMARY_MAX = 500


def _ensure_tables() -> None:
    ddl = """
    CREATE TABLE IF NOT EXISTS rag_trace_run (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        run_id VARCHAR(64) NOT NULL UNIQUE,
        user_id BIGINT NULL,
        question TEXT NULL,
        route VARCHAR(32) NULL,
        status VARCHAR(16) NOT NULL DEFAULT 'running',
        latency_ms INT NULL,
        token_input INT NULL,
        token_output INT NULL,
        error TEXT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        finished_at DATETIME NULL,
        INDEX idx_run_created (created_at),
        INDEX idx_run_route (route),
        INDEX idx_run_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

    CREATE TABLE IF NOT EXISTS rag_trace_node (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        run_id VARCHAR(64) NOT NULL,
        seq INT NOT NULL,
        node_name VARCHAR(64) NOT NULL,
        node_type VARCHAR(32) NULL,
        input TEXT NULL,
        output TEXT NULL,
        latency_ms INT NULL,
        status VARCHAR(16) NOT NULL DEFAULT 'ok',
        error TEXT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_node_run (run_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    """
    try:
        with _get_engine().begin() as conn:
            for stmt in ddl.strip().split(";"):
                stmt = stmt.strip()
                if stmt:
                    conn.execute(text(stmt))
        logger.info("Trace 表已就绪（rag_trace_run / rag_trace_node）")
    except Exception as exc:
        logger.warning("Trace 建表失败（Trace 功能将降级为无记录）：%s", exc)

    # token 列
    for col, ctype in (("token_input", "INT NULL"), ("token_output", "INT NULL")):
        try:
            with _get_engine().begin() as conn:
                conn.execute(text(f"ALTER TABLE rag_trace_run ADD COLUMN {col} {ctype}"))
            logger.info("Trace 补齐列：%s", col)
        except Exception:
            pass


def _summarize_state(state: Any) -> str:
    if state is None:
        return ""
    if not isinstance(state, dict):
        s = str(state)
        return s[:_SUMMARY_MAX] + ("…" if len(s) > _SUMMARY_MAX else "")
    keys = ("user_input", "route", "current_step", "task_status", "action", "response")
    parts: Dict[str, Any] = {}
    for k in keys:
        if k in state and state[k] is not None:
            v = state[k]
            if k == "response" and isinstance(v, str):
                v = v[:200] + ("…" if len(v) > 200 else "")
            parts[k] = v
    try:
        s = json.dumps(parts, ensure_ascii=False, default=str)
    except Exception:
        s = str(parts)
    return s[:_SUMMARY_MAX] + ("…" if len(s) > _SUMMARY_MAX else "")


def _summarize_value(v: Any) -> str:
    if v is None:
        return ""
    if isinstance(v, str):
        return v[:_SUMMARY_MAX] + ("…" if len(v) > _SUMMARY_MAX else "")
    try:
        s = json.dumps(v, ensure_ascii=False, default=str)
    except Exception:
        s = str(v)
    return s[:_SUMMARY_MAX] + ("…" if len(s) > _SUMMARY_MAX else "")


def _create_run(user_id: Optional[int], question: str) -> str:
    run_id = str(uuid.uuid4())
    with _get_engine().begin() as conn:
        conn.execute(
            text(
                "INSERT INTO rag_trace_run (run_id, user_id, question, status, created_at) "
                "VALUES (:run_id, :user_id, :question, 'running', :now)"
            ),
            {
                "run_id": run_id,
                "user_id": user_id,
                "question": (question or "")[:2000],
                "now": datetime.now(),
            },
        )
    return run_id


def _finish_run(run_id: str, status: str, latency_ms: int, error: Optional[str] = None) -> None:
    try:
        with _get_engine().begin() as conn:
            conn.execute(
                text(
                    "UPDATE rag_trace_run SET status=:status, latency_ms=:latency_ms, "
                    "error=:error, finished_at=:now WHERE run_id=:run_id"
                ),
                {
                    "status": status,
                    "latency_ms": latency_ms,
                    "error": (error or "")[:2000] if error else None,
                    "now": datetime.now(),
                    "run_id": run_id,
                },
            )
    except Exception as exc:
        logger.warning("Trace finish_run 写入失败: %s", exc)


def update_run_route(run_id: str, route: str) -> None:
    try:
        with _get_engine().begin() as conn:
            conn.execute(
                text("UPDATE rag_trace_run SET route=:route WHERE run_id=:run_id"),
                {"route": route, "run_id": run_id},
            )
    except Exception as exc:
        logger.warning("Trace update_run_route 写入失败: %s", exc)


def update_run_token(run_id: str, token_input: Optional[int], token_output: Optional[int]) -> None:
    try:
        with _get_engine().begin() as conn:
            conn.execute(
                text("UPDATE rag_trace_run SET token_input=:ti, token_output=:to WHERE run_id=:run_id"),
                {"ti": token_input, "to": token_output, "run_id": run_id},
            )
    except Exception as exc:
        logger.warning("Trace update_run_token 写入失败: %s", exc)


def update_current_run_route(route: str) -> None:
    run_id = _current_run_id.get()
    if run_id:
        update_run_route(run_id, route)


@contextmanager
def trace_run(user_id: Optional[int], question: str, route: Optional[str] = None):
    try:
        run_id = _create_run(user_id, question)
    except Exception as exc:
        logger.warning("Trace 创建 Run 失败，本次不记录: %s", exc)
        run_id = None

    token = _current_run_id.set(run_id)
    _current_seq.set(0)
    start = time.time()
    status = "ok"
    error_msg: Optional[str] = None
    try:
        yield run_id
    except Exception as exc:
        status = "error"
        error_msg = str(exc)[:2000]
        raise
    finally:
        latency_ms = int((time.time() - start) * 1000)
        if run_id is not None:
            _finish_run(run_id, status, latency_ms, error_msg)
        _current_run_id.reset(token)


def _insert_node(
    run_id: str,
    seq: int,
    name: str,
    node_type: Optional[str],
    input_summary: str,
    output_summary: str,
    latency_ms: int,
    status: str,
    error: Optional[str],
) -> None:
    try:
        with _get_engine().begin() as conn:
            conn.execute(
                text(
                    "INSERT INTO rag_trace_node "
                    "(run_id, seq, node_name, node_type, input, output, latency_ms, status, error, created_at) "
                    "VALUES (:run_id, :seq, :name, :ntype, :inp, :outp, :lat, :status, :err, :now)"
                ),
                {
                    "run_id": run_id,
                    "seq": seq,
                    "name": name,
                    "ntype": node_type,
                    "inp": input_summary or None,
                    "outp": output_summary or None,
                    "lat": latency_ms,
                    "status": status,
                    "err": (error[:2000] if error else None),
                    "now": datetime.now(),
                },
            )
    except Exception as exc:
        logger.warning("Trace insert_node 写入失败: %s", exc)


def trace_node(name: str, node_type: Optional[str] = None):
    def deco(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            run_id = _current_run_id.get()
            if run_id is None:
                return fn(*args, **kwargs)

            seq = _current_seq.get()
            _current_seq.set(seq + 1)

            input_summary = _summarize_state(args[0]) if args else ""

            start = time.time()
            status = "ok"
            error_msg: Optional[str] = None
            try:
                output = fn(*args, **kwargs)
                return output
            except Exception as exc:
                status = "error"
                error_msg = str(exc)[:2000]
                raise
            finally:
                latency_ms = int((time.time() - start) * 1000)
                output_summary = _summarize_state(output) if output is not None else ""
                _insert_node(
                    run_id, seq, name, node_type,
                    input_summary, output_summary, latency_ms, status, error_msg,
                )

        return wrapper

    return deco


def _row_to_dict(row) -> dict:
    return {col: getattr(row, col) for col in row._mapping.keys()}


def list_runs(
    limit: int = 50,
    offset: int = 0,
    route: Optional[str] = None,
    status: Optional[str] = None,
    days: Optional[int] = None,
) -> dict:
    conditions = []
    params: Dict[str, Any] = {"limit": limit, "offset": offset}
    if route:
        conditions.append("route = :route")
        params["route"] = route
    if status:
        conditions.append("status = :status")
        params["status"] = status
    if days and days > 0:
        conditions.append("created_at >= :since")
        params["since"] = datetime.now() - timedelta(days=days)

    where = (" WHERE " + " AND ".join(conditions)) if conditions else ""

    with _get_engine().connect() as conn:
        total_row = conn.execute(text(f"SELECT COUNT(*) AS c FROM rag_trace_run{where}"), params).fetchone()
        total = total_row.c if total_row else 0

        rows = conn.execute(
            text(
                f"SELECT run_id, user_id, question, route, status, latency_ms, error, created_at, finished_at "
                f"FROM rag_trace_run{where} ORDER BY created_at DESC LIMIT :limit OFFSET :offset"
            ),
            params,
        ).fetchall()

    items = []
    for r in rows:
        d = _row_to_dict(r)
        d["created_at"] = d["created_at"].strftime("%Y-%m-%d %H:%M:%S") if d.get("created_at") else None
        d["finished_at"] = d["finished_at"].strftime("%Y-%m-%d %H:%M:%S") if d.get("finished_at") else None
        d["question"] = (d.get("question") or "")[:120]
        items.append(d)
    return {"items": items, "total": total}


def get_run_with_nodes(run_id: str) -> Optional[dict]:
    with _get_engine().connect() as conn:
        run_row = conn.execute(
            text(
                "SELECT run_id, user_id, question, route, status, latency_ms, token_input, token_output, error, created_at, finished_at "
                "FROM rag_trace_run WHERE run_id = :run_id"
            ),
            {"run_id": run_id},
        ).fetchone()
        if not run_row:
            return None
        run = _row_to_dict(run_row)
        run["created_at"] = run["created_at"].strftime("%Y-%m-%d %H:%M:%S") if run.get("created_at") else None
        run["finished_at"] = run["finished_at"].strftime("%Y-%m-%d %H:%M:%S") if run.get("finished_at") else None

        node_rows = conn.execute(
            text(
                "SELECT seq, node_name, node_type, input, output, latency_ms, status, error, created_at "
                "FROM rag_trace_node WHERE run_id = :run_id ORDER BY seq ASC"
            ),
            {"run_id": run_id},
        ).fetchall()

    nodes = []
    for r in node_rows:
        d = _row_to_dict(r)
        d["created_at"] = d["created_at"].strftime("%Y-%m-%d %H:%M:%S") if d.get("created_at") else None
        nodes.append(d)
    run["nodes"] = nodes
    return run


def get_trace_stats(days: int = 7) -> dict:
    """统计聚合：总数/平均耗时/错误率/按日趋势/状态分布。"""
    since = datetime.now() - timedelta(days=days)
    with _get_engine().connect() as conn:
        overview = conn.execute(
            text(
                "SELECT COUNT(*) AS total, "
                "COALESCE(AVG(latency_ms), 0) AS avg_latency, "
                "SUM(CASE WHEN status='error' THEN 1 ELSE 0 END) AS error_count "
                "FROM rag_trace_run WHERE created_at >= :since"
            ),
            {"since": since},
        ).fetchone()
        total = overview.total if overview else 0
        avg_latency = round(float(overview.avg_latency), 1) if overview else 0
        error_count = overview.error_count if overview else 0
        error_rate = round(error_count / total * 100, 1) if total else 0

        daily_rows = conn.execute(
            text(
                "SELECT DATE(created_at) AS d, COUNT(*) AS cnt, COALESCE(AVG(latency_ms), 0) AS lat "
                "FROM rag_trace_run WHERE created_at >= :since "
                "GROUP BY DATE(created_at) ORDER BY d ASC"
            ),
            {"since": since},
        ).fetchall()
        daily = [
            {"date": str(r.d), "count": r.cnt, "avg_latency": round(float(r.lat), 1)}
            for r in daily_rows
        ]

        status_rows = conn.execute(
            text(
                "SELECT status, COUNT(*) AS cnt FROM rag_trace_run "
                "WHERE created_at >= :since GROUP BY status"
            ),
            {"since": since},
        ).fetchall()
        status_dist = [{ "name": r.status, "value": r.cnt } for r in status_rows]

        route_rows = conn.execute(
            text(
                "SELECT COALESCE(route, 'unknown') AS route, COUNT(*) AS cnt FROM rag_trace_run "
                "WHERE created_at >= :since GROUP BY route ORDER BY cnt DESC"
            ),
            {"since": since},
        ).fetchall()
        route_dist = [{ "name": r.route, "value": r.cnt } for r in route_rows]

    return {
        "days": days,
        "total": total,
        "avg_latency_ms": avg_latency,
        "error_count": error_count,
        "error_rate": error_rate,
        "daily_trend": daily,
        "status_distribution": status_dist,
        "route_distribution": route_dist,
    }
