"""
入库 Pipeline 表结构
"""
from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import text

from database import engine, SessionLocal


def ensure_ingestion_tables() -> None:
    """幂等建入库 Pipeline 相关表。失败不阻断启动（调度器降级为不运行）。"""
    db = SessionLocal()
    try:
        db.execute(text(
            """
            CREATE TABLE IF NOT EXISTS ingestion_pipeline (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                name VARCHAR(64) NOT NULL COMMENT 'Pipeline 名称（唯一）',
                enabled TINYINT(1) NOT NULL DEFAULT 1 COMMENT '是否启用',
                description VARCHAR(255) NOT NULL DEFAULT '',
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                    ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uk_name (name)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            COMMENT='入库 Pipeline 定义'
            """
        ))
        db.execute(text(
            """
            CREATE TABLE IF NOT EXISTS ingestion_pipeline_node (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                pipeline_id BIGINT UNSIGNED NOT NULL,
                node_key VARCHAR(64) NOT NULL COMMENT '节点标识，如 fetcher/chunker/embedder/vector_write/keyword_sync',
                node_order INT NOT NULL DEFAULT 0 COMMENT '执行顺序（小→大）',
                config JSON NOT NULL COMMENT '节点配置 JSON（条件执行等）',
                enabled TINYINT(1) NOT NULL DEFAULT 1,
                PRIMARY KEY (id),
                UNIQUE KEY uk_pipe_node (pipeline_id, node_key),
                KEY idx_pipeline (pipeline_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            COMMENT='入库 Pipeline 节点定义'
            """
        ))
        db.execute(text(
            """
            CREATE TABLE IF NOT EXISTS ingestion_task (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                pipeline_id BIGINT UNSIGNED NOT NULL,
                task_type VARCHAR(16) NOT NULL DEFAULT 'full'
                    COMMENT 'full=全量重建 / incremental=增量更新',
                status VARCHAR(16) NOT NULL DEFAULT 'pending'
                    COMMENT 'pending/running/success/failed',
                trigger_by VARCHAR(32) NOT NULL DEFAULT 'manual'
                    COMMENT 'manual/api/scheduler',
                error TEXT NULL,
                started_at DATETIME NULL,
                finished_at DATETIME NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_status (status),
                KEY idx_created (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            COMMENT='入库任务执行记录'
            """
        ))
        db.execute(text(
            """
            CREATE TABLE IF NOT EXISTS ingestion_task_node (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                task_id BIGINT UNSIGNED NOT NULL,
                node_key VARCHAR(64) NOT NULL,
                node_order INT NOT NULL DEFAULT 0,
                status VARCHAR(16) NOT NULL DEFAULT 'pending'
                    COMMENT 'pending/running/success/failed/skipped',
                latency_ms INT NOT NULL DEFAULT 0,
                error TEXT NULL,
                output_summary VARCHAR(255) NOT NULL DEFAULT '',
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_task (task_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            COMMENT='入库节点执行明细'
            """
        ))
        db.execute(text(
            """
            CREATE TABLE IF NOT EXISTS ingestion_watermark (
                source_key VARCHAR(64) NOT NULL COMMENT '数据源标识，如 product/faq/document',
                last_run_at DATETIME NOT NULL COMMENT '上次扫描水位线',
                PRIMARY KEY (source_key)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            COMMENT='入库增量同步水位线（定时刷新用）'
            """
        ))
        db.commit()
        print("[Ingestion] 入库 Pipeline 表已就绪")
    except Exception as exc:
        db.rollback()
        print(f"[Ingestion] 建表失败（入库调度降级）: {exc}")
    finally:
        db.close()



DEFAULT_PIPELINE_NODES = [
    {"node_key": "fetcher", "node_order": 1, "config": {}},
    {"node_key": "chunker", "node_order": 2, "config": {}},
    {"node_key": "embedder", "node_order": 3, "config": {}},
    {"node_key": "vector_write", "node_order": 4, "config": {}},
    {"node_key": "keyword_sync", "node_order": 5, "config": {}},
]


def ensure_default_pipeline() -> int:
    """幂等创建默认 Pipeline（guagua_knowledge）及其节点定义，返回 pipeline_id。"""
    db = SessionLocal()
    try:
        db.execute(text(
            """
            INSERT IGNORE INTO ingestion_pipeline (name, enabled, description)
            VALUES ('guagua_knowledge', 1, '瓜呱知识库全量/增量入库 Pipeline')
            """
        ))
        row = db.execute(text(
            "SELECT id FROM ingestion_pipeline WHERE name = 'guagua_knowledge'"
        )).mappings().first()
        pipeline_id = int(row["id"])
        for node in DEFAULT_PIPELINE_NODES:
            db.execute(
                text(
                    """
                    INSERT IGNORE INTO ingestion_pipeline_node
                        (pipeline_id, node_key, node_order, config, enabled)
                    VALUES (:pid, :key, :order, :cfg, 1)
                    """
                ),
                {
                    "pid": pipeline_id,
                    "key": node["node_key"],
                    "order": node["node_order"],
                    "cfg": json.dumps(node["config"], ensure_ascii=False),
                },
            )
        db.commit()
        return pipeline_id
    except Exception as exc:
        db.rollback()
        print(f"[Ingestion] 默认 Pipeline 初始化失败: {exc}")
        return 0
    finally:
        db.close()



def create_task(pipeline_id: int, task_type: str, trigger_by: str = "manual") -> Optional[int]:
    db = SessionLocal()
    try:
        result = db.execute(
            text(
                """
                INSERT INTO ingestion_task (pipeline_id, task_type, status, trigger_by, started_at)
                VALUES (:pid, :type, 'running', :trigger, NOW())
                """
            ),
            {"pid": pipeline_id, "type": task_type, "trigger": trigger_by},
        )
        db.commit()
        return int(result.lastrowid)
    except Exception as exc:
        db.rollback()
        print(f"[Ingestion] 创建任务失败: {exc}")
        return None
    finally:
        db.close()


def finish_task(task_id: int, status: str, error: str = "") -> None:
    db = SessionLocal()
    try:
        db.execute(
            text(
                """
                UPDATE ingestion_task
                SET status = :status, error = :error, finished_at = NOW()
                WHERE id = :tid
                """
            ),
            {"tid": task_id, "status": status, "error": error or None},
        )
        db.commit()
    except Exception as exc:
        db.rollback()
        print(f"[Ingestion] 任务收尾失败: {exc}")
    finally:
        db.close()


def log_node_start(task_id: int, node_key: str, node_order: int) -> Optional[int]:
    db = SessionLocal()
    try:
        result = db.execute(
            text(
                """
                INSERT INTO ingestion_task_node (task_id, node_key, node_order, status)
                VALUES (:tid, :key, :order, 'running')
                """
            ),
            {"tid": task_id, "key": node_key, "order": node_order},
        )
        db.commit()
        return int(result.lastrowid)
    except Exception as exc:
        db.rollback()
        print(f"[Ingestion] 节点日志写入失败: {exc}")
        return None
    finally:
        db.close()


def log_node_finish(node_log_id: int, status: str, latency_ms: int, error: str = "", summary: str = "") -> None:
    db = SessionLocal()
    try:
        db.execute(
            text(
                """
                UPDATE ingestion_task_node
                SET status = :status, latency_ms = :latency,
                    error = :error, output_summary = :summary
                WHERE id = :nid
                """
            ),
            {
                "nid": node_log_id,
                "status": status,
                "latency": latency_ms,
                "error": error or None,
                "summary": summary[:255],
            },
        )
        db.commit()
    except Exception as exc:
        db.rollback()
        print(f"[Ingestion] 节点日志收尾失败: {exc}")
    finally:
        db.close()


def load_pipeline_nodes(pipeline_id: int) -> List[Dict[str, Any]]:
    """读取 Pipeline 节点定义（按顺序、仅启用）。"""
    db = SessionLocal()
    try:
        rows = db.execute(
            text(
                """
                SELECT node_key, node_order, config, enabled
                FROM ingestion_pipeline_node
                WHERE pipeline_id = :pid AND enabled = 1
                ORDER BY node_order
                """
            ),
            {"pid": pipeline_id},
        ).mappings().all()
        return [
            {"node_key": r["node_key"], "node_order": r["node_order"],
             "config": json.loads(r["config"]) if r["config"] else {}}
            for r in rows
        ]
    except Exception as exc:
        print(f"[Ingestion] 读取 Pipeline 节点失败: {exc}")
        return []
    finally:
        db.close()


def get_recent_tasks(limit: int = 20) -> List[dict]:
    db = SessionLocal()
    try:
        rows = db.execute(
            text(
                """
                SELECT t.id, t.task_type, t.status, t.trigger_by, t.error,
                       t.started_at, t.finished_at, t.created_at, p.name AS pipeline
                FROM ingestion_task t
                LEFT JOIN ingestion_pipeline p ON t.pipeline_id = p.id
                ORDER BY t.id DESC
                LIMIT :limit
                """
            ),
            {"limit": limit},
        ).mappings().all()
        return [dict(r) for r in rows]
    except Exception as exc:
        print(f"[Ingestion] 任务列表读取失败: {exc}")
        return []
    finally:
        db.close()


def get_task_detail(task_id: int) -> Optional[dict]:
    db = SessionLocal()
    try:
        task = db.execute(
            text(
                """
                SELECT t.id, t.task_type, t.status, t.trigger_by, t.error,
                       t.started_at, t.finished_at, t.created_at, p.name AS pipeline
                FROM ingestion_task t
                LEFT JOIN ingestion_pipeline p ON t.pipeline_id = p.id
                WHERE t.id = :tid
                """
            ),
            {"tid": task_id},
        ).mappings().first()
        if not task:
            return None
        nodes = db.execute(
            text(
                """
                SELECT node_key, node_order, status, latency_ms, error, output_summary
                FROM ingestion_task_node
                WHERE task_id = :tid
                ORDER BY node_order
                """
            ),
            {"tid": task_id},
        ).mappings().all()
        return {**dict(task), "nodes": [dict(n) for n in nodes]}
    except Exception as exc:
        print(f"[Ingestion] 任务详情读取失败: {exc}")
        return None
    finally:
        db.close()



def get_watermark(source_key: str, default: Optional[datetime] = None) -> Optional[datetime]:
    db = SessionLocal()
    try:
        row = db.execute(
            text("SELECT last_run_at FROM ingestion_watermark WHERE source_key = :k"),
            {"k": source_key},
        ).mappings().first()
        return row["last_run_at"] if row else default
    except Exception as exc:
        print(f"[Ingestion] 水位线读取失败: {exc}")
        return default
    finally:
        db.close()


def set_watermark(source_key: str, when: Optional[datetime] = None) -> None:
    db = SessionLocal()
    try:
        db.execute(
            text(
                """
                INSERT INTO ingestion_watermark (source_key, last_run_at)
                VALUES (:k, :when)
                ON DUPLICATE KEY UPDATE last_run_at = VALUES(last_run_at)
                """
            ),
            {"k": source_key, "when": when or datetime.now()},
        )
        db.commit()
    except Exception as exc:
        db.rollback()
        print(f"[Ingestion] 水位线写入失败: {exc}")
    finally:
        db.close()



def acquire_lock(lock_name: str, timeout_sec: int = 900) -> bool:
    """获取 MySQL 命名锁（GET_LOCK），防止多实例/多线程并发入库。"""
    db = SessionLocal()
    try:
        row = db.execute(text("SELECT GET_LOCK(:name, 0) AS ok"), {"name": lock_name}).mappings().first()
        return bool(row and row["ok"])
    except Exception as exc:
        print(f"[Ingestion] 获取分布式锁失败: {exc}")
        return False
    finally:
        db.close()


def release_lock(lock_name: str) -> None:
    db = SessionLocal()
    try:
        db.execute(text("SELECT RELEASE_LOCK(:name)"), {"name": lock_name})
        db.commit()
    except Exception as exc:
        print(f"[Ingestion] 释放分布式锁失败: {exc}")
    finally:
        db.close()
