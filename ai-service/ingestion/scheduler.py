"""
入库定时刷新调度器
"""
from __future__ import annotations

import threading

from config import settings


class IngestionScheduler:
    def __init__(self, interval_sec: int = 600):
        self._interval = max(30, interval_sec)
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, name="ingestion-scheduler", daemon=True)
        self._thread.start()
        print(f"[Ingestion] 定时刷新调度器已启动（间隔 {self._interval}s）")

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)

    def _loop(self) -> None:
        from ingestion.engine import run_incremental

        while not self._stop.is_set():
            try:
                result = run_incremental(trigger_by="scheduler")
                if not result.get("ok"):
                    print(f"[Ingestion] 定时增量执行未完成: {result.get('error')}")
            except Exception as exc:
                print(f"[Ingestion] 定时增量执行异常: {exc}")
            self._stop.wait(self._interval)


_scheduler: IngestionScheduler | None = None


def start_ingestion_scheduler() -> None:
    """启动全局入库定时调度器（幂等）。"""
    global _scheduler
    if _scheduler is None:
        _scheduler = IngestionScheduler(
            interval_sec=int(getattr(settings, "INGESTION_INTERVAL_SECONDS", 600) or 600)
        )
    _scheduler.start()


def stop_ingestion_scheduler() -> None:
    global _scheduler
    if _scheduler:
        _scheduler.stop()
