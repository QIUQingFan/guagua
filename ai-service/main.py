from __future__ import annotations

import asyncio
import json
import threading
import warnings
from contextlib import asynccontextmanager
from typing import List, Optional, Tuple
import os as _os
import importlib as _importlib

_os.environ.setdefault("LANGGRAPH__ALLOWED_OBJECTS", "messages")

try:
    _lc_load_mod = _importlib.import_module("langchain_core.load.load")
    if hasattr(_lc_load_mod, "Reviver"):
        _orig_reviver_init = _lc_load_mod.Reviver.__init__
        def _patched_reviver_init(self, *args, **kwargs):
            if len(args) < 1 and "allowed_objects" not in kwargs:
                kwargs["allowed_objects"] = "messages"
            return _orig_reviver_init(self, *args, **kwargs)
        _lc_load_mod.Reviver.__init__ = _patched_reviver_init
except Exception as _exc:
    import warnings as _w
    _w.warn(f"[启动期] 无法 patch langchain Reviver 默认 allowed_objects，退化为告警抑制：{_exc}")

warnings.filterwarnings(
    "ignore",
    message=r"The default value of `allowed_objects` will change in a future version.*",
    category=Warning,
    module=r"langchain_core\.load\.(load|dumps)",
)

from fastapi import BackgroundTasks, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from agent import run_admin_analysis, run_agent_with_meta, stream_agent, stream_admin_analysis
from analytics import get_dashboard_snapshot
from ai_usage import get_ai_usage_snapshot
from behavior import get_behavior_snapshot, report_behavior
from config import settings
from conversation_store import (
    ensure_sources_column,
    ensure_summary_table,
    is_enabled as persist_enabled,
    load_recent_messages,
    maybe_summarize,
    save_turn,
)
from rag import build_knowledge_base, ensure_documents_table, ingest_document, get_knowledge_stats
from ingestion import (
    ensure_ingestion_tables,
    get_recent_tasks,
    get_task_detail,
    run_incremental,
    run_pipeline,
)
from ingestion.scheduler import start_ingestion_scheduler, stop_ingestion_scheduler


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        from retrieval import build_default_engine
        build_default_engine()
    except Exception as exc:
        print(f"[Startup] 多路检索引擎装配失败（检索路径将在请求时重试）: {exc}")
    try:
        from model_router import build_default_router
        router = build_default_router()
        print(f"[Startup] 模型路由器已装配：候选 {len(router.candidates_info())} 个")
    except Exception as exc:
        print(f"[Startup] 模型路由器装配失败（LLM 路径将在请求时重试）: {exc}")
    try:
        if settings.RATE_LIMIT_ENABLED in ("true", "1", "yes"):
            from rate_limiter import health_check
            import asyncio
            hc = asyncio.get_event_loop().run_until_complete(health_check())
            if hc.get("ok"):
                print(f"[Startup] Redis 限流器已就绪：并发 {hc['concurrent']} / 排队 {hc['queue']}")
            else:
                print(f"[Startup] Redis 限流器连通失败（限流降级为直通）: {hc.get('error')}")
    except Exception as exc:
        print(f"[Startup] Redis 限流器初始化失败（限流降级为直通）: {exc}")
    try:
        from trace import _ensure_tables
        _ensure_tables()
    except Exception as exc:
        print(f"[Startup] Trace 建表失败（Trace 功能将降级）: {exc}")
    try:
        ensure_sources_column()
    except Exception as exc:
        print(f"[Startup] ai_messages.sources 列装配失败: {exc}")
    try:
        ensure_summary_table()
    except Exception as exc:
        print(f"[Startup] conversation_summary 建表失败（摘要功能降级）: {exc}")
    try:
        ensure_documents_table()
    except Exception as exc:
        print(f"[Startup] ai_documents 建表失败（文档持久化降级）: {exc}")
    try:
        ensure_ingestion_tables()
        start_ingestion_scheduler()
    except Exception as exc:
        print(f"[Startup] 入库 Pipeline 初始化失败（调度器不启动）: {exc}")
    try:
        from query import ensure_query_term_mapping_table
        ensure_query_term_mapping_table()
    except Exception as exc:
        print(f"[Startup] query_term_mapping 建表失败（查询词映射功能降级）: {exc}")
    try:
        from intent import ensure_intent_tables, seed_intent_tree
        ensure_intent_tables()
        seed_intent_tree()
        from intent import build_default_router as build_intent_router
        ir = build_intent_router()
        print(f"[Startup] 意图路由器已装配：{len(ir._index)} 个节点")
    except Exception as exc:
        print(f"[Startup] 意图树初始化失败（意图路由降级为传统分类）: {exc}")
    print("[Startup] 瓜呱 AI 服务已启动")
    yield
    stop_ingestion_scheduler()
    print("[Shutdown] 瓜呱 AI 服务已停止")


app = FastAPI(
    title="瓜呱 AI 服务",
    description="基于 LangGraph 与 RAG 的瓜呱商城 AI 服务",
    version="1.0.0",
    lifespan=lifespan,
)

origins = [origin.strip() for origin in settings.CORS_ORIGINS.split(",") if origin.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _extract_user(request: Request) -> Tuple[Optional[int], str]:
    """
    从网关注入的 header 读取用户身份。

    - X-User-Id:   登录用户 ID（未登录为 None）
    - X-User-Role: 角色，默认 guest

    注意：这两个 header 由 Express 网关在 JWT 鉴权后写入，
    Python 服务不直接解析 token，避免密钥耦合与越权风险。
    """
    raw_uid = request.headers.get("X-User-Id")
    user_id: Optional[int] = None
    if raw_uid:
        try:
            user_id = int(raw_uid)
        except (TypeError, ValueError):
            user_id = None
    user_role = request.headers.get("X-User-Role", "guest") or "guest"
    return user_id, user_role


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    message: str
    history: List[ChatMessage] = []
    conversation_id: Optional[int] = None


class ChatResponse(BaseModel):
    reply: str
    route: Optional[str] = None
    action: Optional[dict] = None
    task_id: Optional[str] = None
    task_status: Optional[str] = None
    step: Optional[int] = None
    sub_tasks: Optional[List[dict]] = None
    conversation_id: Optional[int] = None
    message_id: Optional[int] = None


class AdminAnalysisRequest(BaseModel):
    message: str
    range: str = "7d"


class AdminAnalysisResponse(BaseModel):
    reply: str
    snapshot: dict
    llm_error: Optional[str] = None


class KnowledgeBuildResponse(BaseModel):
    status: str
    message: str


class DocumentUploadRequest(BaseModel):
    title: str
    content: str
    source_type: str = "document"
    category: str = ""


class DocumentUploadResponse(BaseModel):
    status: str
    chunks: int
    title: str
    message: str


@app.get("/ai/health")
async def health():
    return {"status": "ok", "service": "瓜呱 AI 服务"}


@app.get("/ai/rate-limit/health")
async def rate_limit_health():
    if settings.RATE_LIMIT_ENABLED not in ("true", "1", "yes"):
        return {"enabled": False, "message": "限流未启用"}
    from rate_limiter import health_check
    return {"enabled": True, **await health_check()}


@app.post("/ai/chat", response_model=ChatResponse)
async def chat(req: ChatRequest, request: Request):
    if not req.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    user_id, _ = _extract_user(request)
    history = [{"role": item.role, "content": item.content} for item in req.history]

    if persist_enabled() and req.conversation_id and not history:
        loaded = load_recent_messages(req.conversation_id, limit=8)
        if loaded:
            history = loaded

    import time
    start_ts = time.time()
    try:
        loop = asyncio.get_event_loop()
        reply = await loop.run_in_executor(
            None,
            lambda: run_agent_with_meta(req.message, history, user_id),
        )
    except Exception as exc:
        print(f"[Chat Error] {exc}")
        raise HTTPException(status_code=500, detail=f"AI service error: {exc}")

    latency_ms = int((time.time() - start_ts) * 1000)

    conversation_id = req.conversation_id
    message_id = None
    if persist_enabled():
        try:
            token_usage = reply.get("token_usage") or {}
            persist_ret = await loop.run_in_executor(
                None,
                lambda: save_turn(
                    req.conversation_id,
                    user_id,
                    req.message,
                    reply.get("reply", ""),
                    route=reply.get("route"),
                    action=reply.get("action"),
                    latency_ms=latency_ms,
                    token_input=token_usage.get("token_input"),
                    token_output=token_usage.get("token_output"),
                    sources=reply.get("sources"),
                ),
            )
            conversation_id = persist_ret.get("conversation_id", conversation_id)
            message_id = persist_ret.get("message_id")
            if conversation_id:
                loop.run_in_executor(None, lambda: maybe_summarize(conversation_id))
        except Exception as exc:
            print(f"[Chat Persist Error] {exc}")

    return ChatResponse(**reply, conversation_id=conversation_id, message_id=message_id)


@app.post("/ai/chat/stream")
async def chat_stream(req: ChatRequest, request: Request):
    if not req.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    user_id, _ = _extract_user(request)
    history = [{"role": item.role, "content": item.content} for item in req.history]
    if persist_enabled() and req.conversation_id and not history:
        loaded = load_recent_messages(req.conversation_id, limit=8)
        if loaded:
            history = loaded
    loop = asyncio.get_event_loop()

    if settings.RATE_LIMIT_ENABLED in ("true", "1", "yes"):
        from rate_limiter import RateLimitAcquire
        import uuid
        request_id = f"stream:{uuid.uuid4().hex}"
        try:
            acquired = await RateLimitAcquire(request_id=request_id).__aenter__()
            if not acquired:
                raise HTTPException(
                    status_code=429,
                    detail=f"系统繁忙，请稍后再试（排队超时 {settings.RATE_LIMIT_MAX_WAIT_SECONDS}s）",
                )
        except HTTPException:
            raise
        except Exception as exc:
            print(f"[Rate Limit] Redis 限流降级（直通）: {exc}")
            request_id = None
            acquired = False
    else:
        request_id = None
        acquired = False

    async def generate():
        import time

        token_queue: asyncio.Queue = asyncio.Queue()
        _released = False

        async def _release():
            nonlocal _released
            if acquired and not _released:
                _released = True
                from rate_limiter import release
                await release(request_id)

        def produce():
            try:
                for event in stream_agent(req.message, history, user_id):
                    asyncio.run_coroutine_threadsafe(token_queue.put(event), loop)
            except Exception as exc:
                asyncio.run_coroutine_threadsafe(token_queue.put(exc), loop)
            finally:
                asyncio.run_coroutine_threadsafe(token_queue.put(None), loop)

        threading.Thread(target=produce, daemon=True).start()

        reply_parts: List[str] = []
        action_payload: Optional[dict] = None
        sources_payload: Optional[list] = None
        meta_payload: dict = {"route": None, "token_usage": None, "sources": None}
        had_error = False
        start_ts = time.time()

        while True:
            item = await token_queue.get()
            if item is None:
                break
            if isinstance(item, Exception):
                had_error = True
                yield f"data: {json.dumps({'error': str(item)}, ensure_ascii=False)}\n\n"
                break
            if isinstance(item, dict):
                if "meta" in item:
                    meta_payload = item["meta"]
                    continue
                if item.get("sources") is not None:
                    sources_payload = item.get("sources")
                if item.get("action") is not None:
                    action_payload = item.get("action")
                yield f"data: {json.dumps(item, ensure_ascii=False)}\n\n"
            else:
                reply_parts.append(item)
                yield f"data: {json.dumps({'token': item}, ensure_ascii=False)}\n\n"

        if persist_enabled() and not had_error:
            full_reply = "".join(reply_parts)
            if full_reply:
                try:
                    latency_ms = int((time.time() - start_ts) * 1000)
                    token_usage = meta_payload.get("token_usage") or {}
                    final_sources = sources_payload or meta_payload.get("sources")
                    persist_ret = await loop.run_in_executor(
                        None,
                        lambda: save_turn(
                            req.conversation_id,
                            user_id,
                            req.message,
                            full_reply,
                            route=meta_payload.get("route"),
                            action=action_payload,
                            latency_ms=latency_ms,
                            token_input=token_usage.get("token_input"),
                            token_output=token_usage.get("token_output"),
                            sources=final_sources,
                        ),
                    )
                    if persist_ret and persist_ret.get("conversation_id"):
                        yield f"data: {json.dumps({'conversation_id': persist_ret['conversation_id'], 'message_id': persist_ret.get('message_id')}, ensure_ascii=False)}\n\n"
                        loop.run_in_executor(
                            None,
                            lambda: maybe_summarize(persist_ret["conversation_id"]),
                        )
                except Exception as exc:
                    print(f"[Chat Stream Persist Error] {exc}")

        yield "data: [DONE]\n\n"
        await _release()

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


@app.post("/ai/admin/analysis", response_model=AdminAnalysisResponse)
async def admin_analysis(req: AdminAnalysisRequest, request: Request):
    if not req.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")

    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            lambda: run_admin_analysis(req.message, req.range),
        )
        return AdminAnalysisResponse(**result)
    except Exception as exc:
        print(f"[Admin Analysis Error] {exc}")
        raise HTTPException(status_code=500, detail=f"AI service error: {exc}")


@app.post("/ai/admin/analysis/stream")
async def admin_analysis_stream(req: AdminAnalysisRequest, request: Request):
    """管理端经营分析（SSE 流式）。
    """
    if not req.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")

    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")

    loop = asyncio.get_event_loop()

    async def generate():
        token_queue: asyncio.Queue = asyncio.Queue()

        def produce():
            try:
                for event in stream_admin_analysis(req.message, req.range):
                    asyncio.run_coroutine_threadsafe(token_queue.put(event), loop)
            except Exception as exc:
                asyncio.run_coroutine_threadsafe(token_queue.put(exc), loop)
            finally:
                asyncio.run_coroutine_threadsafe(token_queue.put(None), loop)

        threading.Thread(target=produce, daemon=True).start()

        while True:
            item = await token_queue.get()
            if item is None:
                break
            if isinstance(item, Exception):
                yield f"data: {json.dumps({'error': str(item)}, ensure_ascii=False)}\n\n"
                break
            if isinstance(item, dict):
                yield f"data: {json.dumps(item, ensure_ascii=False)}\n\n"
            else:
                yield f"data: {json.dumps({'token': item}, ensure_ascii=False)}\n\n"

        yield "data: [DONE]\n\n"

    return StreamingResponse(
        generate(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


@app.get("/ai/dashboard/snapshot")
async def dashboard_snapshot(
    request: Request,
    range: str = "7d",
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
):
    """运营看板快照（REST 直连，不经 LLM）。

    - admin 鉴权（网关注入 X-User-Role=admin）
    - 区间：预设 range=today/7d/30d，或自定义 start_date/end_date（YYYY-MM-DD，闭区间）
    - 返回 analytics.get_dashboard_snapshot 原始结构
    - 锚点回退：仅预设区间生效，当日历窗口无数据时自动以最新数据时间为锚点重算窗口，
      并通过 rangeAnchoredAt / latestDataAt / alerts 字段提示
    - 对比分析：返回 trends + previousTrends（本期 vs 上期叠加折线）+ comparison.previousPeriod
    """
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")

    if range not in ("today", "7d", "30d", "custom"):
        range = "7d"
    try:
        loop = asyncio.get_event_loop()
        snapshot = await loop.run_in_executor(
            None,
            lambda: get_dashboard_snapshot(range, start_date=start_date, end_date=end_date),
        )
        return snapshot
    except Exception as exc:
        print(f"[Dashboard Snapshot Error] {exc}")
        raise HTTPException(status_code=500, detail=f"analytics error: {exc}")


@app.get("/ai/dashboard/ai-usage")
async def dashboard_ai_usage(
    request: Request,
    range: str = "7d",
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
):
    """AI 调用量统计快照（REST 直连，不经 LLM）。

    - admin 鉴权（网关注入 X-User-Role=admin）
    - 区间：预设 range=today/7d/30d，或自定义 start_date/end_date
    - 返回 ai_usage.get_ai_usage_snapshot 原始结构
    - 数据来源：ai_messages / ai_action_logs / ai_feedbacks
    - token 字段为 NULL 时统计做友好降级（COALESCE / NULLIF）
    """
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")

    if range not in ("today", "7d", "30d", "custom"):
        range = "7d"
    try:
        loop = asyncio.get_event_loop()
        snapshot = await loop.run_in_executor(
            None,
            lambda: get_ai_usage_snapshot(range, start_date=start_date, end_date=end_date),
        )
        return snapshot
    except Exception as exc:
        print(f"[Dashboard AI Usage Error] {exc}")
        raise HTTPException(status_code=500, detail=f"ai_usage error: {exc}")


@app.get("/ai/dashboard/behavior")
async def dashboard_behavior(
    request: Request,
    range: str = "7d",
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
):
    """用户行为分析快照

    - admin 鉴权
    - 区间：预设 range=today/7d/30d，或自定义 start_date/end_date
    - 返回 behavior.get_behavior_snapshot：漏斗 / 行为 TopN / 趋势 / AI 推荐点击率
    """
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")

    if range not in ("today", "7d", "30d", "custom"):
        range = "7d"
    try:
        loop = asyncio.get_event_loop()
        snapshot = await loop.run_in_executor(
            None,
            lambda: get_behavior_snapshot(range, start_date=start_date, end_date=end_date),
        )
        return snapshot
    except Exception as exc:
        print(f"[Dashboard Behavior Error] {exc}")
        raise HTTPException(status_code=500, detail=f"behavior error: {exc}")


class BehaviorReport(BaseModel):
    product_id: int
    action: str
    source: str = "manual"
    session_key: Optional[str] = None
    context: Optional[dict] = None


@app.post("/ai/behavior")
async def report_behavior_endpoint(req: BehaviorReport, request: Request):
    """前端用户行为上报（落库 ai_user_behaviors）。

    - 可选登录：登录用户从 X-User-Id 注入 user_id，游客 user_id=None
    - 游客建议传 session_key（前端可用浏览器指纹/随机串，便于会话级分析）
    - action ∈ {view, cart, purchase, recommend_click, ai_recommend}
    - 上报失败不阻断前端业务（路由层兜底 500）
    """
    user_id, _ = _extract_user(request)
    try:
        loop = asyncio.get_event_loop()
        behavior_id = await loop.run_in_executor(
            None,
            lambda: report_behavior(
                user_id=user_id,
                session_key=req.session_key,
                product_id=req.product_id,
                action=req.action,
                source=req.source,
                context=req.context,
            ),
        )
        return {"status": "ok", "id": behavior_id}
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        print(f"[Behavior Report Error] {exc}")
        raise HTTPException(status_code=500, detail=f"behavior report error: {exc}")


_eval_running = False


@app.post("/ai/eval/run")
async def eval_run(background_tasks: BackgroundTasks, request: Request):
    """管理员触发合规评估（后台运行），结果写入 evaluation/reports/latest.json。"""
    global _eval_running
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    if _eval_running:
        raise HTTPException(status_code=409, detail="已有评估任务在运行，请稍后通过 /ai/eval/report 查看")
    _eval_running = True
    background_tasks.add_task(_do_eval)
    return {"status": "accepted", "message": "评估任务已提交，后台运行中，稍后通过 /ai/eval/report 查看结果"}


async def _do_eval():
    global _eval_running
    loop = asyncio.get_event_loop()
    try:
        from evaluation.runner import run_evaluation
        await loop.run_in_executor(None, run_evaluation)
    except Exception as exc:
        print(f"[Eval Error] {exc}")
    finally:
        _eval_running = False


@app.get("/ai/eval/report")
async def eval_report(request: Request):
    """管理员获取最近一次合规评估报告。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from evaluation.runner import load_latest_report
    report = load_latest_report()
    if not report:
        raise HTTPException(status_code=404, detail="暂无评估报告，请先调用 /ai/eval/run")
    return {"running": _eval_running, **report}



@app.get("/ai/admin/trace/runs")
async def trace_runs(
    request: Request,
    limit: int = 50,
    offset: int = 0,
    route: Optional[str] = None,
    status: Optional[str] = None,
    days: Optional[int] = None,
):
    """管理员查询 Trace Run 列表（分页，支持按 route/status/days 筛选）。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from trace import list_runs
    limit = max(1, min(int(limit), 200))
    offset = max(0, int(offset))
    return list_runs(limit=limit, offset=offset, route=route, status=status, days=days)


@app.get("/ai/admin/trace/runs/{run_id}")
async def trace_run_detail(run_id: str, request: Request):
    """管理员查询单个 Trace Run 的完整 Node 明细。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from trace import get_run_with_nodes
    run = get_run_with_nodes(run_id)
    if not run:
        raise HTTPException(status_code=404, detail="Trace Run 不存在")
    return run


@app.get("/ai/admin/trace/stats")
async def trace_stats(request: Request, days: int = 7):
    """管理员查询 Trace 统计聚合（总数/平均耗时/错误率/按日趋势/状态分布/路由分布）。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from trace import get_trace_stats
    days = max(1, min(int(days), 90))
    return get_trace_stats(days=days)


@app.post("/ai/knowledge/build", response_model=KnowledgeBuildResponse)
async def rebuild_knowledge(background_tasks: BackgroundTasks, request: Request):
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")

    background_tasks.add_task(_do_build_knowledge)
    return KnowledgeBuildResponse(
        status="accepted",
        message="知识库重建任务已提交，正在后台运行。",
    )


async def _do_build_knowledge():
    loop = asyncio.get_event_loop()
    try:
        await loop.run_in_executor(None, build_knowledge_base)
    except Exception as exc:
        print(f"[Knowledge Build Error] {exc}")


@app.get("/ai/admin/knowledge/stats")
async def knowledge_stats(request: Request):
    """获取知识库统计信息（向量库 chunk 数、类型分布、FAQ 数量）。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    loop = asyncio.get_event_loop()
    stats = await loop.run_in_executor(None, get_knowledge_stats)
    return stats


@app.post("/ai/admin/knowledge/upload", response_model=DocumentUploadResponse)
async def upload_document(req: DocumentUploadRequest, request: Request):
    """增量入库一篇文档：切分 → 向量化 → 写入 ChromaDB。

    此处简化为文本直接入库，适合管理后台粘贴电商领域文档（退货政策/售后协议等）。
    """
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    if not req.title.strip() or not req.content.strip():
        raise HTTPException(status_code=400, detail="标题和内容不能为空")

    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(
        None,
        lambda: ingest_document(
            title=req.title.strip(),
            content=req.content.strip(),
            source_type=req.source_type or "document",
            category=req.category or "",
        )
    )
    return DocumentUploadResponse(
        status="ok",
        chunks=result["chunks"],
        title=result["title"],
        message=f"文档已入库，生成 {result['chunks']} 个文本块",
    )


class PipelineRunRequest(BaseModel):
    task_type: str = "full"


@app.post("/ai/admin/ingestion/run")
async def ingestion_run(req: PipelineRunRequest, request: Request):
    """【P2 入库 Pipeline】手动触发一次入库任务（节点编排 + 日志）。

    - full:        全量重建（fetcher→chunker→embedder→vector_write→keyword_sync）
    - incremental: 增量更新（扫描 updated_at 变更商品，带分布式锁）
    返回任务 id 与各节点统计，节点明细可查询 /ai/admin/ingestion/tasks/{id}。
    """
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    if req.task_type not in ("full", "incremental"):
        raise HTTPException(status_code=400, detail="task_type 仅支持 full/incremental")

    loop = asyncio.get_event_loop()
    if req.task_type == "incremental":
        result = await loop.run_in_executor(None, lambda: run_incremental(trigger_by="api"))
    else:
        result = await loop.run_in_executor(None, lambda: run_pipeline(task_type="full", trigger_by="api"))
    if not result.get("ok"):
        return {"status": "failed", "task_id": result.get("task_id"), "error": result.get("error"), "stats": result.get("stats")}
    return {"status": "success", "task_id": result.get("task_id"), "task_type": req.task_type, "stats": result.get("stats")}


@app.get("/ai/admin/ingestion/tasks")
async def ingestion_tasks(request: Request, limit: int = 20):
    """【P2 入库 Pipeline】查询最近入库任务列表（状态/触发方式/耗时）。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    loop = asyncio.get_event_loop()
    limit = max(1, min(int(limit), 100))
    tasks = await loop.run_in_executor(None, lambda: get_recent_tasks(limit=limit))
    return {"list": tasks}


@app.get("/ai/admin/ingestion/tasks/{task_id}")
async def ingestion_task_detail(task_id: int, request: Request):
    """【P2 入库 Pipeline】查询单个入库任务详情（含各节点状态/耗时/错误）。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    loop = asyncio.get_event_loop()
    detail = await loop.run_in_executor(None, lambda: get_task_detail(task_id))
    if not detail:
        raise HTTPException(status_code=404, detail="任务不存在")
    return detail




class QueryTermMappingCreate(BaseModel):
    source_term: str
    target_term: str
    domain: Optional[str] = None
    match_type: int = 1
    priority: int = 100
    enabled: bool = True
    remark: Optional[str] = None


class QueryTermMappingUpdate(BaseModel):
    source_term: Optional[str] = None
    target_term: Optional[str] = None
    domain: Optional[str] = None
    match_type: Optional[int] = None
    priority: Optional[int] = None
    enabled: Optional[bool] = None
    remark: Optional[str] = None


@app.get("/ai/admin/query-mappings")
async def list_query_mappings(
    request: Request,
    keyword: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
):
    """【P2 查询词映射】分页查询映射规则（keyword 模糊匹配源词/目标词）。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from query import list_mappings
    loop = asyncio.get_event_loop()
    limit = max(1, min(int(limit), 500))
    offset = max(0, int(offset))
    return await loop.run_in_executor(
        None, lambda: list_mappings(keyword=keyword, limit=limit, offset=offset)
    )


class QueryRewriteTestRequest(BaseModel):
    question: str
    history: List[ChatMessage] = []


@app.post("/ai/admin/query-mappings/test")
async def test_query_rewrite(req: QueryRewriteTestRequest, request: Request):
    """【P2 查询词映射】测试问题重写效果：输入原句，返回归一化+改写后的检索查询。

    供管理后台预览映射规则与重写效果，无需实际发起检索。
    注意：静态路由 /test 须声明在 /{mapping_id} 之前，避免被路径参数吞掉。
    """
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from query.term_mapping import normalize as tm_normalize
    from query import prepare_retrieval_query
    loop = asyncio.get_event_loop()
    history = [{"role": item.role, "content": item.content} for item in req.history]
    normalized = await loop.run_in_executor(None, lambda: tm_normalize(req.question))
    final = await loop.run_in_executor(
        None, lambda: prepare_retrieval_query(req.question, history)
    )
    return {
        "original": req.question,
        "normalized": normalized,
        "final": final,
        "rewrote": normalized != final,
    }


@app.get("/ai/admin/query-mappings/{mapping_id}")
async def get_query_mapping(mapping_id: int, request: Request):
    """【P2 查询词映射】查询单条映射规则详情。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from query import get_mapping
    loop = asyncio.get_event_loop()
    item = await loop.run_in_executor(None, lambda: get_mapping(mapping_id))
    if not item:
        raise HTTPException(status_code=404, detail="映射规则不存在")
    return item


@app.post("/ai/admin/query-mappings")
async def create_query_mapping(req: QueryTermMappingCreate, request: Request):
    """【P2 查询词映射】创建映射规则（源词→目标词，检索前归一化）。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from query import create_mapping
    loop = asyncio.get_event_loop()
    try:
        new_id = await loop.run_in_executor(
            None,
            lambda: create_mapping(
                source_term=req.source_term,
                target_term=req.target_term,
                domain=req.domain,
                match_type=req.match_type,
                priority=req.priority,
                enabled=req.enabled,
                remark=req.remark,
            ),
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return {"status": "ok", "id": new_id}


@app.put("/ai/admin/query-mappings/{mapping_id}")
async def update_query_mapping(mapping_id: int, req: QueryTermMappingUpdate, request: Request):
    """【P2 查询词映射】更新映射规则（仅更新非 None 字段）。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from query import update_mapping
    loop = asyncio.get_event_loop()
    try:
        ok = await loop.run_in_executor(
            None,
            lambda: update_mapping(
                mapping_id,
                source_term=req.source_term,
                target_term=req.target_term,
                domain=req.domain,
                match_type=req.match_type,
                priority=req.priority,
                enabled=req.enabled,
                remark=req.remark,
            ),
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    if not ok:
        raise HTTPException(status_code=404, detail="映射规则不存在")
    return {"status": "ok"}


@app.delete("/ai/admin/query-mappings/{mapping_id}")
async def delete_query_mapping(mapping_id: int, request: Request):
    """【P2 查询词映射】删除映射规则。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from query import delete_mapping
    loop = asyncio.get_event_loop()
    ok = await loop.run_in_executor(None, lambda: delete_mapping(mapping_id))
    if not ok:
        raise HTTPException(status_code=404, detail="映射规则不存在")
    return {"status": "ok"}




@app.get("/ai/admin/intent-tree")
async def list_intent_tree(request: Request):
    """获取意图树（完整树形结构）。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from intent import build_default_router
    ir = build_default_router()
    return {"nodes": ir.list_nodes(), "count": len(ir._index)}


@app.get("/ai/admin/intent-tree/route")
async def test_intent_route(request: Request, q: str = ""):
    """测试意图路由：输入 → 分类 → 树匹配 → 路由决策。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    if not q.strip():
        raise HTTPException(status_code=400, detail="query 参数不能为空")
    from intent import build_default_router
    ir = build_default_router()
    result = ir.route(q)
    return {
        "input": q,
        "intent_code": result.intent_code,
        "intent_name": result.intent_name,
        "full_path": result.full_path,
        "confidence": round(result.confidence, 2),
        "is_high_confidence": result.is_high_confidence,
        "kind": result.kind.name,
        "collection_name": result.collection_name,
        "is_system": result.is_system,
        "is_mcp": result.is_mcp,
        "leaf_node": result.leaf_node.to_dict() if result.leaf_node else None,
    }


@app.post("/ai/admin/intent-tree/refresh")
async def refresh_intent_tree(request: Request):
    """从 DB 重新加载意图树（管理员修改节点后调用）。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from intent import reset_default_router
    reset_default_router()
    from intent import build_default_router
    ir = build_default_router()
    return {"message": "意图树已刷新", "node_count": len(ir._index)}




@app.get("/ai/admin/mcp-tools")
async def list_mcp_tools(request: Request):
    """列出所有已注册的 MCP 工具。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from mcp_tools import build_default_registry
    registry = build_default_registry()
    tools = registry.list_all_tools()
    return {
        "tools": [
            {
                "name": t.name,
                "description": t.description,
                "parameters": [
                    {"name": p.name, "type": p.type, "required": p.required}
                    for p in t.parameters
                ],
            }
            for t in tools
        ],
        "count": len(tools),
    }


@app.post("/ai/admin/mcp-tools/validate")
async def validate_mcp_tool_params(request: Request, body: dict):
    """校验 MCP 工具参数。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from mcp_tools import build_default_registry
    registry = build_default_registry()
    tool_id = body.get("tool_id", "")
    params = body.get("params", {})
    errors = registry.validate_params(tool_id, params)
    return {"tool_id": tool_id, "valid": len(errors) == 0, "errors": errors}


@app.post("/ai/admin/mcp-tools/extract-params")
async def extract_mcp_tool_params(request: Request, body: dict):
    """LLM 参数提取：从用户输入中提取工具参数。"""
    _, user_role = _extract_user(request)
    if user_role != "admin":
        raise HTTPException(status_code=403, detail="需要管理员权限")
    from mcp_tools import build_default_registry
    registry = build_default_registry()
    tool_id = body.get("tool_id", "")
    user_input = body.get("user_input", "")
    executor = registry.get_executor(tool_id)
    if not executor:
        raise HTTPException(status_code=404, detail=f"工具 {tool_id} 未注册")
    params = registry.extract_params(user_input, executor.to_tool_def())
    return {"tool_id": tool_id, "user_input": user_input, "params": params}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=settings.AI_SERVICE_PORT,
        reload=True,
        log_level="info",
    )
