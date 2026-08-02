"""
入库 Pipeline 引擎
"""
from __future__ import annotations

import time
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from ingestion.nodes import (
    ChunkingNode,
    DocumentFetcherNode,
    EmbeddingNode,
    IngestionContext,
    IngestionNode,
    KeywordIndexSyncNode,
    VectorWriteNode,
)
from ingestion.tables import (
    acquire_lock,
    create_task,
    ensure_default_pipeline,
    finish_task,
    get_watermark,
    load_pipeline_nodes,
    log_node_finish,
    log_node_start,
    release_lock,
    set_watermark,
)

_NODE_REGISTRY: Dict[str, type] = {
    "fetcher": DocumentFetcherNode,
    "chunker": ChunkingNode,
    "embedder": EmbeddingNode,
    "vector_write": VectorWriteNode,
    "keyword_sync": KeywordIndexSyncNode,
}


def _build_node(node_key: str, config: dict) -> Optional[IngestionNode]:
    cls = _NODE_REGISTRY.get(node_key)
    if not cls:
        return None
    return cls(config=config)


class IngestionEngine:
    """入库 Pipeline 执行引擎。"""

    def __init__(self, pipeline_id: int, task_type: str = "full", trigger_by: str = "manual",
                 node_config_overrides: Optional[Dict[str, dict]] = None):
        self.pipeline_id = pipeline_id
        self.task_type = task_type
        self.trigger_by = trigger_by
        self._overrides = node_config_overrides or {}

    def run(self) -> dict:
        """执行一次 Pipeline：顺序跑节点并记录日志，返回任务摘要。"""
        task_id = create_task(self.pipeline_id, self.task_type, self.trigger_by)
        if not task_id:
            return {"ok": False, "error": "创建任务失败"}

        ctx = IngestionContext(task_type=self.task_type)
        node_defs = load_pipeline_nodes(self.pipeline_id)
        if not node_defs:
            finish_task(task_id, "failed", "Pipeline 无启用节点")
            return {"ok": False, "error": "Pipeline 无启用节点", "task_id": task_id}

        failed = False
        for node_def in node_defs:
            node_key = node_def["node_key"]
            config = dict(node_def.get("config") or {})
            config.update(self._overrides.get(node_key) or {})
            node = _build_node(node_key, config)
            if not node:
                continue

            log_id = log_node_start(task_id, node_key, node_def.get("node_order", 0))
            start = time.time()
            try:
                if not node.should_run(ctx):
                    log_node_finish(log_id, "skipped", 0, summary="条件执行跳过（前置无数据）")
                    continue
                node.execute(ctx)
                latency = int((time.time() - start) * 1000)
                summary = self._summarize(ctx, node_key)
                log_node_finish(log_id, "success", latency, summary=summary)
            except Exception as exc:
                latency = int((time.time() - start) * 1000)
                log_node_finish(log_id, "failed", latency, error=str(exc))
                failed = True
                print(f"[Ingestion] 节点 {node_key} 执行失败: {exc}")
                break

        status = "failed" if failed else "success"
        finish_task(task_id, status)
        result = {
            "ok": not failed,
            "task_id": task_id,
            "task_type": self.task_type,
            "status": status,
            "stats": ctx.stats,
        }
        print(f"[Ingestion] Pipeline 完成: type={self.task_type} status={status} stats={ctx.stats}")
        return result

    @staticmethod
    def _summarize(ctx: IngestionContext, node_key: str) -> str:
        if node_key == "fetcher":
            return f"拉取数据 {ctx.stats.get('fetched', 0)} 条"
        if node_key == "chunker":
            return f"切分文本块 {ctx.stats.get('chunked', 0)} 条"
        if node_key == "embedder":
            return f"向量化 {ctx.stats.get('embedded', 0)} 条"
        if node_key == "vector_write":
            return f"写入 ChromaDB {ctx.stats.get('written', 0)} 条"
        if node_key == "keyword_sync":
            counts = ctx.stats.get("keyword_synced") or {}
            return f"关键词索引同步完成: {counts}"
        return ""



def run_pipeline(task_type: str = "full", trigger_by: str = "manual") -> dict:
    """运行默认 Pipeline（全量或增量）。"""
    pipeline_id = ensure_default_pipeline()
    if not pipeline_id:
        return {"ok": False, "error": "默认 Pipeline 初始化失败"}
    return IngestionEngine(pipeline_id, task_type, trigger_by).run()


def run_incremental(trigger_by: str = "scheduler") -> dict:
    """增量更新：扫描 updated_at 变更的商品并 reindex。
    水位线记录上次扫描时间；商品 updated_at > 水位线即触发单商品 reindex。
    """
    lock_name = "ingestion:incremental"
    if not acquire_lock(lock_name, timeout_sec=900):
        print("[Ingestion] 增量更新跳过：分布式锁被占用（另一实例/线程正在执行）")
        return {"ok": False, "error": "分布式锁被占用"}

    try:
        since = get_watermark("product")
        if since is None:
            since = datetime.now() - timedelta(days=7)

        set_watermark("product")

        engine = IngestionEngine(
            ensure_default_pipeline(),
            task_type="incremental",
            trigger_by=trigger_by,
            node_config_overrides={"fetcher": {"since": since}},
        )
        result = engine.run()
        return result
    finally:
        release_lock(lock_name)
