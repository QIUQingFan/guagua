from __future__ import annotations

import json
import logging
import re
import uuid
from typing import Any, Generator, List, Optional, TypedDict

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from langgraph.graph import END, StateGraph
from langgraph.prebuilt import create_react_agent

from analytics import get_dashboard_snapshot
from config import settings
from model_router import get_default_router
from prompts import load_prompt
from query import prepare_retrieval_query
from retrieval import build_default_engine
from trace import trace_node, trace_run, update_current_run_route
from tools import (
    RECOMMEND_TOOLS,
    ANALYSIS_TOOLS,
    CUSTOMER_SERVICE_TOOLS,
    search_products,
    get_hot_products,
    extract_procurement_intent,
)
from agents.user_profile import UserProfile, analyze_user_profile, get_cached_profile

logger = logging.getLogger("agent")


llm = ChatOpenAI(
    model=settings.OPENAI_MODEL,
    openai_api_key=settings.OPENAI_API_KEY,
    openai_api_base=settings.OPENAI_BASE_URL,
    temperature=0.3,
    streaming=False,
)

streaming_llm = ChatOpenAI(
    model=settings.OPENAI_MODEL,
    openai_api_key=settings.OPENAI_API_KEY,
    openai_api_base=settings.OPENAI_BASE_URL,
    temperature=0.3,
    streaming=True,
)


@trace_node("llm_invoke", "model")
def _route_invoke(messages: List, tier: str = "standard"):
    """
    通过模型路由器调用 LLM
    - 多候选 failover：主候选失败自动切备选
    - 熔断保护：OPEN 状态候选直接跳过，不消耗配额
    - 返回 AIMessage
    """
    return get_default_router().invoke(messages, tier=tier)


def _route_stream(messages: List, tier: str = "standard"):
    """
    通过模型路由器流式调用 LLM
    - 首包探测：首个 token 未在 timeout 内到达即切候选
    - 多候选 failover：首包超时/异常自动切下一候选重试
    - 生成 chunk
    """
    return get_default_router().stream(messages, tier=tier)


_retrieval_engine = None


def _retrieve_contents(query: str, top_k: Optional[int] = None) -> List[str]:
    """
    多路检索：向量 + 关键词 + 热销三通道并行召回，RRF 融合后返回文本内容列表。
    替代原 search_knowledge 单路向量检索，提升召回率与精确匹配能力。
    """
    global _retrieval_engine
    if _retrieval_engine is None:
        _retrieval_engine = build_default_engine()
    chunks = _retrieval_engine.search(query, top_k=top_k)
    return [c.content for c in chunks]


def _retrieve_with_citations(query: str, top_k: Optional[int] = None) -> tuple:
    """
    多路检索 + 引用溯源：返回 (带编号的上下文文本, 来源列表)。

    - 上下文文本格式：``[1] {content}``\\n\\n``[2] {content}``\\n\\n...
      注入 stream-cs-knowledge 的 {context}，配合 answer-citation-rules 让 LLM 产出 [N](#cite-N) 角标。
    - 来源列表：``[{n, source_type, source_id, title, content, metadata}, ...]``
      在流末 yield {"sources": sources}，供前端渲染来源面板 + 持久化到 ai_messages.sources。

    title 取值：product/hot → metadata.name；faq → metadata.question；其余 → source_id。
    content 截断 300 字，避免来源面板过长。
    """
    global _retrieval_engine
    if _retrieval_engine is None:
        _retrieval_engine = build_default_engine()
    chunks = _retrieval_engine.search(query, top_k=top_k)
    if not chunks:
        return "", []
    context_parts: List[str] = []
    sources: List[dict] = []
    for idx, c in enumerate(chunks, 1):
        context_parts.append(f"[{idx}] {c.content}")
        meta = c.metadata or {}
        if c.source_type in ("product", "hot"):
            title = meta.get("name") or str(c.source_id or "")
        elif c.source_type == "faq":
            title = meta.get("question") or str(c.source_id or "")
        else:
            title = str(c.source_id or c.source_type)
        sources.append({
            "n": idx,
            "source_type": c.source_type,
            "source_id": c.source_id,
            "title": title,
            "content": (c.content or "")[:300],
            "metadata": meta,
        })
    return "\n\n".join(context_parts), sources


class TaskStatus:
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    RETRYING = "retrying"


class SubTaskState(TypedDict):
    task_id: str
    name: str
    agent_name: str
    status: str
    input: str
    output: Optional[str]
    action: Optional[dict]
    retry_count: int
    error: Optional[str]


class TaskSnapshot(TypedDict):
    task_id: str
    step: int
    state: dict
    timestamp: str


class AgentState(TypedDict):
    task_id: str
    user_input: str
    history: List[dict]
    route: Optional[str]
    retrieved_docs: List[str]
    response: str
    action: Optional[dict]
    user_id: Optional[int]
    current_step: int
    max_steps: int
    task_status: str
    sub_tasks: List[SubTaskState]
    task_history: List[dict]
    last_agent_result: Optional[dict]
    retry_attempts: int
    max_retries: int
    snapshot: Optional[TaskSnapshot]
    tool_calls_trace: List[dict]
    validation: Optional[dict]
    token_usage: Optional[dict]
    retrieval_query: Optional[str]
    intent_result: Optional[dict]
    user_profile: Optional[dict]


CATEGORY_HINT_MAP = {
    "文创周边": ["文创", "帆布包", "明信片", "徽章", "周边", "礼盒", "校徽", "纪念"],
    "学习用品": ["教材", "笔记", "文具", "书本", "考研", "课程", "资料", "题库"],
    "二手数码": ["二手", "手机", "电脑", "耳机", "平板", "相机", "数码", "电子", "笔记本"],
    "生活服务": ["代购", "跑腿", "打印", "洗衣", "维修", "外卖", "快递代取"],
}

ORDER_KEYWORDS = [
    "我的订单", "订单到哪", "订单号", "物流", "快递", "发货", "收货",
    "运单", "签收", "退换", "退款", "售后", "so20", "order",
]


def _format_history(history: List[dict]) -> List:
    messages = []
    system_entries = [item for item in history if item.get("role") == "system" and item.get("content")]
    turns = [item for item in history if item.get("role") in ("user", "assistant")]
    for item in system_entries + turns[-8:]:
        role = item.get("role")
        content = item.get("content", "")
        if not content:
            continue
        if role == "system":
            messages.append(SystemMessage(content=content))
        elif role == "user":
            messages.append(HumanMessage(content=content))
        else:
            messages.append(AIMessage(content=content))
    return messages


def _history_as_text(history: List[dict]) -> str:
    lines = []
    for item in history[-8:]:
        role = item.get("role", "assistant")
        content = item.get("content", "").strip()
        if content:
            lines.append(f"{role}: {content}")
    return "\n".join(lines)


def _extract_json_object(text_content: str, default: dict) -> dict:
    if not text_content:
        return default
    text_content = text_content.strip()
    try:
        return json.loads(text_content)
    except Exception:
        pass
    match = re.search(r"\{.*\}", text_content, re.S)
    if not match:
        return default
    try:
        return json.loads(match.group(0))
    except Exception:
        return default


def _detect_route(user_input: str) -> str:
    lowered = user_input.lower()

    if any(kw in lowered for kw in ORDER_KEYWORDS):
        return "customer_service"

    prompt = load_prompt("intent-classifier", user_input=user_input)
    try:
        result = _route_invoke([HumanMessage(content=prompt)], tier="fast")
        route = (result.content or "").strip().lower()
    except Exception:
        route = ""

    if route in {"recommend", "analysis", "customer_service"}:
        return route

    analysis_keywords = [
        "analysis", "dashboard", "report", "trend", "sales", "revenue",
        "data", "metric", "kpi", "销量", "销售", "营收", "趋势", "分析", "数据", "经营",
    ]
    if any(keyword in lowered for keyword in analysis_keywords):
        return "analysis"

    recommend_keywords = [
        "recommend", "buy", "worth", "budget", "procurement",
        "推荐", "性价比", "值得买", "买什么", "代购", "帮我买", "购买", "下单",
    ]
    if any(keyword in lowered for keyword in recommend_keywords):
        return "recommend"

    return "customer_service"


def _parse_task_decomposition(task_description: str) -> dict:
    default = {"tasks": [], "strategy": "sequential"}
    prompt = load_prompt("task-decomposition", task_description=task_description)
    try:
        result = _route_invoke([HumanMessage(content=prompt)], tier="fast")
        parsed = _extract_json_object(result.content, default)
    except Exception:
        parsed = default
    return parsed


def _assess_task_completion(state: AgentState) -> str:
    last_result = state.get("last_agent_result")
    response = state.get("response", "")

    if not response or not last_result:
        return "continue"

    if state["current_step"] >= state["max_steps"]:
        return "complete"

    if "查不到数据" in response or "没有找到" in response or "No matched" in response:
        return "failed"

    if state.get("action"):
        return "complete"

    completed_subtasks = [t for t in state["sub_tasks"] if t["status"] == TaskStatus.COMPLETED]
    if len(state["sub_tasks"]) > 0 and len(completed_subtasks) == len(state["sub_tasks"]):
        return "complete"

    if last_result.get("status") == TaskStatus.COMPLETED and state["current_step"] >= 3:
        return "complete"

    return "continue"


def _decide_next_agent(state: AgentState) -> str:
    last_result = state.get("last_agent_result")
    route = state.get("route")

    if state["retry_attempts"] > 0 and route == "analysis":
        return "customer_service"

    if last_result and last_result.get("agent_name") == "analysis":
        response = last_result.get("output", "")
        if "查不到数据" in response or "没有找到" in response or "No data" in response:
            return "customer_service"

    return route or "customer_service"


def _format_agent_result(agent_name: str, response: str, action: Optional[dict]) -> dict:
    return {
        "agent_name": agent_name,
        "output": response,
        "action": action,
        "status": TaskStatus.COMPLETED if response else TaskStatus.FAILED,
        "timestamp": str(uuid.uuid1()),
    }


def _extract_token_usage(messages: List) -> Optional[dict]:
    """从 LangGraph ReAct agent 的 messages 列表里提取最后一条 AIMessage 的 token usage。

    LangChain AIMessage.usage_metadata 形如
    {'input_tokens': 123, 'output_tokens': 456, 'total_tokens': 579}。
    多步 ReAct 会产生多条 AIMessage，这里累加所有 AIMessage 的 usage，覆盖工具调用中间步。
    """
    total_in = 0
    total_out = 0
    found = False
    for msg in messages:
        if not isinstance(msg, AIMessage):
            continue
        usage = getattr(msg, "usage_metadata", None)
        if not usage:
            continue
        found = True
        total_in += int(usage.get("input_tokens") or 0)
        total_out += int(usage.get("output_tokens") or 0)
    if not found:
        return None
    return {"token_input": total_in, "token_output": total_out}


def _parse_products(products_text: str) -> List[dict]:
    """解析 search_products 的文本结果，返回 [{id, name, price, stock}, ...]（按行顺序）。"""
    items: List[dict] = []
    for line in products_text.splitlines():
        m = re.search(r"#(\d+)\s+(.+?)\|\s*category:", line)
        if not m:
            continue
        price_m = re.search(r"price:\s*CNY\s*([\d.]+)", line)
        stock_m = re.search(r"stock:\s*(\d+)", line)
        items.append({
            "id": int(m.group(1)),
            "name": m.group(2).strip(),
            "price": float(price_m.group(1)) if price_m else 0.0,
            "stock": int(stock_m.group(1)) if stock_m else 0,
        })
    return items


def _build_procurement_action(intent: dict, products_text: str) -> Optional[dict]:
    if intent.get("action_type") not in {"add_to_cart", "buy_now"}:
        return None
    items = _parse_products(products_text)
    if not items:
        return None
    query = (intent.get("product_query") or "").strip().lower()
    pick = items[0]
    if query:
        # 优先选择标题与用户指定商品精确一致的条目，避免「立即购买」按钮指向与推荐不符的商品
        for it in items:
            if it["name"].strip().lower() == query:
                pick = it
                break
        else:
            contains = [it for it in items if query in it["name"].lower()]
            if contains:
                pick = contains[0]
    return {
        "type": intent["action_type"],
        "productId": pick["id"],
        "productName": pick["name"],
        "quantity": max(1, int(intent.get("quantity") or 1)),
        "price": pick["price"],
        "stock": pick["stock"],
    }


def _last_product_from_history(history: List[dict]) -> Optional[str]:
    """
    从最近对话历史中提取最后被推荐/提到的商品名。

    用于用户表达购买/下单意愿但未指明具体商品时（如「下单」「就这个」），
    自动定位上一轮 AI 推荐的商品，以便搜索并构建购买按钮。
    """
    for item in reversed(history[-8:]):
        if item.get("role") != "assistant":
            continue
        content = (item.get("content") or "").strip()
        if not content:
            continue
        m = re.search(r"#(\d+)\s+([^\n|]+?)(?:\s*\||\n|$)", content)
        if not m:
            continue
        name = m.group(2).strip()
        name = re.sub(r"[\s*#、，。；：:]+$", "", name).strip()
        if len(name) > 1:
            return name
    return None


def _resolve_purchase_intent(user_input: str, history: List[dict], intent: dict) -> dict:
    """
    完善购买意图：当用户表达购买/下单意愿但当前消息未指明具体商品时，
    从对话历史中最近推荐的商品补充 product_query，确保能定位商品并下发购买按钮。
    """
    intent = dict(intent)
    if intent.get("action_type") in {"add_to_cart", "buy_now"}:
        intent["needs_product_help"] = True
        has_filter = bool(
            (intent.get("product_query") or "").strip()
            or (intent.get("category_hint") or "").strip()
            or intent.get("budget_min") is not None
            or intent.get("budget_max") is not None
        )
        if not has_filter:
            fallback = _last_product_from_history(history)
            if fallback:
                intent["product_query"] = fallback
    return intent


def _purchase_action_guidance(action: Optional[dict], wants_purchase: bool) -> str:
    """
    生成「下单能力」指引，拼接到流式对话 system_content 末尾。

    - action 已构建：明确告知已为某商品准备好「立即购买/加入购物车」按钮，
      并要求 LLM 在回复中如实告知（前端会真实渲染该按钮）。
    - action 未构建：无论用户是否表达购买意愿，都明确声明【没有】下发按钮，
      禁止 LLM 声称「已为您生成按钮/点击下方按钮即可下单」，杜绝按钮幻觉。
    """
    if action:
        is_buy_now = action.get("type") == "buy_now"
        action_desc = "立即购买" if is_buy_now else "加入购物车"
        return (
            "\n\n[下单能力]你是瓜呱商城 AI 助手，具备直接下单能力。系统已为商品 "
            f"#{action['productId']} {action['productName']} 准备好「{action_desc}」操作，"
            f"前端会在本条回复下方显示对应按钮供用户一键完成。请在回复中明确告知用户："
            f"已为其准备好该商品，点击下方「{action_desc}」按钮即可完成"
            f"{'下单' if is_buy_now else '加购'}（价格 ¥{action['price']:.2f}、库存 {action['stock']} 件）。"
            "【一致性要求】本条回复【只能推荐并介绍这一款商品】（即按钮对应的商品，含价格与特点），"
            "不得再推荐或罗列热销榜、匹配列表中的其它商品，也不得让用户前往商城页面自行搜索下单，"
            "避免用户看到的推荐商品与「立即购买」按钮指向的商品不一致。"
            "切勿声称无法处理订单——你具备此能力。"
        )
    if wants_purchase:
        return (
            "\n\n[下单能力]你是瓜呱商城 AI 助手，具备直接下单能力：当用户表达购买/下单意愿且能定位到可售商品时，"
            "系统会自动下发「立即购买/加入购物车」按钮。"
            "【重要】本条回复系统【没有】下发任何按钮：若你声称「已为您生成按钮/点击下方按钮即可下单」，"
            "前端将无按钮可点、用户将无法完成下单。请先向用户确认要下单的具体商品（可结合最近推荐过或用户提到过的商品），"
            "例如回复「好的，请问您想下单哪一款呢？」。不要一律让用户「前往商城页面」，也不要声称无法下单。"
        )
    return (
        "\n\n[下单能力]你是瓜呱商城 AI 助手，具备直接下单能力：当用户明确表达购买/下单意愿时，"
        "系统会自动下发「立即购买/加入购物车」按钮。"
        "【重要】本条回复系统【没有】下发任何按钮：请勿提及「点击下方按钮」「已为您生成按钮」等说法，"
        "否则用户将找不到按钮、无法完成下单。若用户表示想购买推荐的商品，请直接告知其回复想购买的商品即可，"
        "系统会自动生成下单按钮；不要声称存在按钮，也不要引导用户前往商城页面自行下单。"
    )


RECOMMEND_SYSTEM_PROMPT = load_prompt("agent-recommend")

ANALYSIS_SYSTEM_PROMPT = load_prompt("agent-analysis")

CUSTOMER_SERVICE_SYSTEM_PROMPT = load_prompt("agent-customer-service")

recommend_react_agent = create_react_agent(llm, RECOMMEND_TOOLS, prompt=RECOMMEND_SYSTEM_PROMPT)
analysis_react_agent = create_react_agent(llm, ANALYSIS_TOOLS, prompt=ANALYSIS_SYSTEM_PROMPT)
customer_service_react_agent = create_react_agent(llm, CUSTOMER_SERVICE_TOOLS, prompt=CUSTOMER_SERVICE_SYSTEM_PROMPT)


@trace_node("supervisor", "router")
def supervisor_node(state: AgentState) -> AgentState:
    new_state = dict(state)
    new_state["current_step"] = state["current_step"] + 1

    if state["current_step"] == 0:
        route = _detect_route(state["user_input"])
        new_state["route"] = route
        new_state["task_status"] = TaskStatus.RUNNING

        try:
            from intent import build_default_router as build_intent_router
            ir = build_intent_router()
            intent_result = ir.route(state["user_input"])
            new_state["intent_result"] = {
                "intent_code": intent_result.intent_code,
                "confidence": intent_result.confidence,
                "full_path": intent_result.full_path,
                "kind": intent_result.kind.name,
                "collection_name": intent_result.collection_name,
                "is_high_confidence": intent_result.is_high_confidence,
            }
        except Exception as exc:
            logger.warning("意图路由失败（降级）: %s", exc)
            new_state["intent_result"] = None
        update_current_run_route(route)

        decomposition = _parse_task_decomposition(state["user_input"])
        for i, task in enumerate(decomposition.get("tasks", [])):
            sub_task: SubTaskState = {
                "task_id": f"{state['task_id']}_{i}",
                "name": task.get("name", f"subtask_{i}"),
                "agent_name": task.get("agent", route),
                "status": TaskStatus.PENDING,
                "input": task.get("description", state["user_input"]),
                "output": None,
                "action": None,
                "retry_count": 0,
                "error": None,
            }
            new_state["sub_tasks"].append(sub_task)

        if not new_state["sub_tasks"]:
            new_state["sub_tasks"].append({
                "task_id": f"{state['task_id']}_0",
                "name": "main_task",
                "agent_name": route,
                "status": TaskStatus.PENDING,
                "input": state["user_input"],
                "output": None,
                "action": None,
                "retry_count": 0,
                "error": None,
            })
        return new_state

    last_result = state.get("last_agent_result")
    if last_result:
        agent_name = last_result.get("agent_name")
        for sub_task in new_state["sub_tasks"]:
            if sub_task["agent_name"] == agent_name and sub_task["status"] == TaskStatus.RUNNING:
                sub_task["status"] = last_result.get("status", TaskStatus.COMPLETED)
                sub_task["output"] = last_result.get("output")
                sub_task["action"] = last_result.get("action")
                break

        new_state["task_history"].append({
            "step": state["current_step"],
            "agent": agent_name,
            "input": state["user_input"],
            "output": last_result.get("output"),
            "action": last_result.get("action"),
        })

    completion_status = _assess_task_completion(new_state)

    if completion_status == "complete":
        new_state["task_status"] = TaskStatus.COMPLETED
        return new_state

    if completion_status == "failed":
        new_state["retry_attempts"] = state["retry_attempts"] + 1
        if new_state["retry_attempts"] >= new_state["max_retries"]:
            new_state["route"] = "customer_service"
        else:
            new_state["task_status"] = TaskStatus.RETRYING

    new_state["route"] = _decide_next_agent(new_state)

    pending_tasks = [t for t in new_state["sub_tasks"] if t["status"] == TaskStatus.PENDING]
    if pending_tasks:
        pending_tasks[0]["status"] = TaskStatus.RUNNING
        new_state["user_input"] = pending_tasks[0]["input"]

    return new_state


@trace_node("query_rewrite", "rewrite")
def rewrite_node(state: AgentState) -> AgentState:
    retrieval_query = prepare_retrieval_query(state["user_input"], state.get("history"))
    return {**state, "retrieval_query": retrieval_query or state["user_input"]}


@trace_node("rag_retrieve", "retrieve")
def rag_retrieve_node(state: AgentState) -> AgentState:
    query = state.get("retrieval_query") or state["user_input"]
    contents = _retrieve_contents(query)
    return {**state, "retrieved_docs": contents}


@trace_node("customer_service", "agent")
def customer_service_node(state: AgentState) -> AgentState:
    from validation import extract_tool_calls_from_messages, reset_tool_sequence, set_injected_user_id

    set_injected_user_id(state.get("user_id"))
    reset_tool_sequence()

    input_messages = _format_history(state["history"])
    input_messages.append(HumanMessage(content=state["user_input"]))

    try:
        result = customer_service_react_agent.invoke({"messages": input_messages})
        response = result["messages"][-1].content if result["messages"] else ""
        trace = extract_tool_calls_from_messages(result.get("messages", []))

        intent = {}
        try:
            intent_text = extract_procurement_intent.invoke({
                "user_input": state["user_input"],
                "history": _history_as_text(state["history"]),
            })
            intent = json.loads(intent_text)
        except Exception:
            pass
        intent = _resolve_purchase_intent(state["user_input"], state["history"], intent)

        action = None
        if intent.get("needs_product_help") and intent.get("action_type") in {"add_to_cart", "buy_now"}:
            products_text = search_products.invoke({
                "query": intent.get("product_query", ""),
                "category": intent.get("category_hint", ""),
                "brand": intent.get("brand_hint", ""),
                "budget_min": intent.get("budget_min"),
                "budget_max": intent.get("budget_max"),
            })
            action = _build_procurement_action(intent, products_text)

        agent_result = _format_agent_result("customer_service", response, action)
        token_usage = _extract_token_usage(result.get("messages", []))
        return {**state, "response": response, "action": action, "last_agent_result": agent_result, "tool_calls_trace": trace, "token_usage": token_usage}
    except Exception:
        context = "\n\n---\n\n".join(state.get("retrieved_docs", []))
        system_prompt = load_prompt(
            "fallback-customer-service",
            user_input=state["user_input"],
            context=context if context else "(暂无相关内容)",
        )
        messages = [SystemMessage(content=system_prompt)] + _format_history(state["history"]) + [HumanMessage(content=state["user_input"])]
        fallback = "暂时没有找到相关信息，换个说法试试，或联系人工客服。"
        response = _invoke_llm(messages, fallback)
        return {**state, "response": response, "action": None, "last_agent_result": _format_agent_result("customer_service", response, None), "tool_calls_trace": []}


@trace_node("tool_validation", "audit")
def tool_validation_node(state: AgentState) -> AgentState:
    """对客服 Agent 的工具调用序列做 6 维度校验，记录违规日志供评估层使用。

    注：工具内联校验已在执行点拦截违规并返回引导话术（Observation）；本节点做后置审计与统计，
    不阻断流程。灰度期可仅 observe，正式期接入评估层回归基线。
    """
    from validation import audit_tool_calls

    trace = state.get("tool_calls_trace") or []
    if not trace:
        return {**state, "validation": None}
    audit = audit_tool_calls(trace, state.get("user_id"))
    return {**state, "validation": audit}


@trace_node("recommend", "agent")
def recommend_node(state: AgentState) -> AgentState:
    from validation import extract_tool_calls_from_messages

    input_messages = _format_history(state["history"])
    input_messages.append(HumanMessage(content=state["user_input"]))

    try:
        result = recommend_react_agent.invoke({"messages": input_messages})
        response = result["messages"][-1].content if result["messages"] else ""
        trace = extract_tool_calls_from_messages(result.get("messages", []))

        intent = {}
        try:
            intent_text = extract_procurement_intent.invoke({
                "user_input": state["user_input"],
                "history": _history_as_text(state["history"]),
            })
            intent = json.loads(intent_text)
        except Exception:
            pass
        intent = _resolve_purchase_intent(state["user_input"], state["history"], intent)

        action = None
        if intent.get("needs_product_help") and intent.get("action_type") in {"add_to_cart", "buy_now"}:
            products_text = search_products.invoke({
                "query": intent.get("product_query", ""),
                "category": intent.get("category_hint", ""),
                "brand": intent.get("brand_hint", ""),
                "budget_min": intent.get("budget_min"),
                "budget_max": intent.get("budget_max"),
            })
            action = _build_procurement_action(intent, products_text)

        agent_result = _format_agent_result("recommend", response, action)
        token_usage = _extract_token_usage(result.get("messages", []))
        return {**state, "response": response, "action": action, "last_agent_result": agent_result, "tool_calls_trace": trace, "token_usage": token_usage}
    except Exception:
        retrieval_query = prepare_retrieval_query(state["user_input"], state.get("history"))
        product_context = "\n\n".join(_retrieve_contents(retrieval_query))
        hot_data = get_dashboard_snapshot("30d").get("hotProducts", [])[:5]
        hot_lines = [f"{i+1}. {p['name']} (¥{p['price']:.2f})" for i, p in enumerate(hot_data)] if hot_data else ["暂无热销商品"]

        system_prompt = load_prompt(
            "fallback-recommend",
            user_input=state["user_input"],
            hot_text=chr(10).join(hot_lines),
        )
        messages = [SystemMessage(content=system_prompt)] + _format_history(state["history"]) + [HumanMessage(content=state["user_input"])]
        fallback = "请告诉我你的预算、品类和主要用途，我来帮你推荐。"
        response = _invoke_llm(messages, fallback)
        return {**state, "response": response, "action": None, "last_agent_result": _format_agent_result("recommend", response, None), "tool_calls_trace": []}


@trace_node("analysis", "agent")
def analysis_node(state: AgentState) -> AgentState:
    from validation import extract_tool_calls_from_messages

    input_messages = _format_history(state["history"])
    input_messages.append(HumanMessage(content=state["user_input"]))

    try:
        result = analysis_react_agent.invoke({"messages": input_messages})
        response = result["messages"][-1].content if result["messages"] else ""
        trace = extract_tool_calls_from_messages(result.get("messages", []))
        agent_result = _format_agent_result("analysis", response, None)
        token_usage = _extract_token_usage(result.get("messages", []))
        return {**state, "response": response, "action": None, "last_agent_result": agent_result, "tool_calls_trace": trace, "token_usage": token_usage}
    except Exception:
        snapshot = get_dashboard_snapshot("7d")
        summary = snapshot.get("summary", {})
        fallback = f"近期订单 {summary.get('totalOrders', 0)} 笔，已支付 {summary.get('paidOrders', 0)} 笔，营收 ¥{summary.get('totalRevenue', 0):.2f}。"
        snapshot_text = "\n".join([
            f"统计区间: {snapshot.get('range', '7d')}",
            f"订单总数: {summary.get('totalOrders', 0)}",
            f"营收: ¥{summary.get('totalRevenue', 0):.2f}",
        ])
        system_prompt = load_prompt("fallback-analysis", user_input=state["user_input"], snapshot=snapshot_text)
        messages = [SystemMessage(content=system_prompt)] + _format_history(state["history"]) + [HumanMessage(content=state["user_input"])]
        response = _invoke_llm(messages, fallback)
        return {**state, "response": response, "action": None, "last_agent_result": _format_agent_result("analysis", response, None), "tool_calls_trace": []}


def _invoke_llm(messages: List, fallback: str) -> str:
    try:
        result = _route_invoke(messages)
        return (result.content or "").strip() or fallback
    except Exception as exc:
        logger.error("LLM 调用失败，返回 fallback。错误: %s", exc, exc_info=True)
        return fallback


@trace_node("user_profile", "agent")
def user_profile_node(state: AgentState) -> AgentState:
    """在推荐/客服前执行用户画像分析"""
    import asyncio

    user_id = state.get("user_id")
    if not user_id:
        return {**state, "user_profile": None}

    try:
        profile = get_cached_profile(str(user_id))
        if profile is None:
            profile = analyze_user_profile(str(user_id), {"history": state.get("history", [])})
        return {**state, "user_profile": profile.model_dump() if profile else None}
    except Exception as exc:
        logger.warning("用户画像分析失败，跳过: %s", exc)
        return {**state, "user_profile": None}


def user_profile_decision(state: AgentState) -> str:
    """画像分析完成后，根据原始路由决定下一步"""
    route = state.get("route", "customer_service")
    if route == "recommend":
        return "recommend"
    return "rewrite"


def supervisor_decision(state: AgentState) -> str:
    if state["task_status"] == TaskStatus.COMPLETED:
        return END
    return state.get("route", "customer_service")


def build_graph():
    graph = StateGraph(AgentState)
    graph.add_node("supervisor", supervisor_node)
    graph.add_node("user_profile", user_profile_node)
    graph.add_node("rewrite", rewrite_node)
    graph.add_node("rag_retrieve", rag_retrieve_node)
    graph.add_node("customer_service", customer_service_node)
    graph.add_node("tool_validation", tool_validation_node)
    graph.add_node("recommend", recommend_node)
    graph.add_node("analysis", analysis_node)

    graph.set_entry_point("supervisor")
    graph.add_conditional_edges("supervisor", supervisor_decision, {
        "customer_service": "user_profile",
        "recommend": "user_profile",
        "analysis": "analysis",
        END: END,
    })
    graph.add_conditional_edges("user_profile", user_profile_decision, {
        "rewrite": "rewrite",
        "recommend": "recommend",
    })
    graph.add_edge("rewrite", "rag_retrieve")
    graph.add_edge("rag_retrieve", "customer_service")
    graph.add_edge("customer_service", "tool_validation")
    graph.add_edge("tool_validation", "supervisor")
    graph.add_edge("recommend", "supervisor")
    graph.add_edge("analysis", "supervisor")

    return graph.compile()


agent_graph = build_graph()


def run_agent_with_meta(user_input: str, history: List[dict], user_id: Optional[int] = None) -> dict:
    initial_state: AgentState = {
        "task_id": str(uuid.uuid4()),
        "user_input": user_input,
        "history": history,
        "route": None,
        "retrieved_docs": [],
        "response": "",
        "action": None,
        "user_id": user_id,
        "current_step": 0,
        "max_steps": 20,
        "task_status": TaskStatus.PENDING,
        "sub_tasks": [],
        "task_history": [],
        "last_agent_result": None,
        "retry_attempts": 0,
        "max_retries": 3,
        "snapshot": None,
        "token_usage": None,
        "retrieval_query": None,
        "user_profile": None,
    }
    with trace_run(user_id, user_input) as trace_run_id:
        result = agent_graph.invoke(initial_state)
    return {
        "reply": result["response"],
        "action": result.get("action"),
        "route": result.get("route"),
        "task_id": result.get("task_id"),
        "task_status": result.get("task_status"),
        "step": result.get("current_step"),
        "sub_tasks": result.get("sub_tasks"),
        "tool_calls_trace": result.get("tool_calls_trace", []),
        "validation": result.get("validation"),
        "trace_run_id": trace_run_id,
        "token_usage": result.get("token_usage"),
    }


def run_agent(user_input: str, history: List[dict], user_id: Optional[int] = None) -> str:
    return run_agent_with_meta(user_input, history, user_id)["reply"]


def stream_admin_analysis(user_input: str, range_key: str = "7d"):
    snapshot = get_dashboard_snapshot(range_key)
    yield {"snapshot": snapshot}

    snapshot_text = _format_snapshot(snapshot)
    system_prompt = load_prompt("admin-analysis", snapshot_text=snapshot_text)
    messages = [SystemMessage(content=system_prompt), HumanMessage(content=user_input)]

    produced = False
    try:
        for chunk in _route_stream(messages):
            content = getattr(chunk, "content", None)
            if content:
                produced = True
                yield content
            elif isinstance(chunk, str) and chunk:
                produced = True
                yield chunk
        if not produced:
            logger.warning("经营分析流式无产出，使用数据快照兜底")
            yield f"LLM 未返回内容，以下为当前数据快照供参考：\n\n{snapshot_text}"
            yield {"error": "empty_response"}
    except Exception as exc:
        logger.error("经营分析流式失败: %s", exc, exc_info=True)
        if not produced:
            yield {"error": str(exc)}


def run_admin_analysis(user_input: str, range_key: str = "7d") -> dict:
    snapshot = None
    parts: List[str] = []
    error = None
    try:
        for event in stream_admin_analysis(user_input, range_key):
            if isinstance(event, dict):
                if event.get("snapshot") is not None:
                    snapshot = event["snapshot"]
                elif "error" in event:
                    error = event["error"]
            elif isinstance(event, str):
                parts.append(event)
    except Exception as exc:
        logger.error("经营分析失败: %s", exc, exc_info=True)
        error = str(exc)

    if snapshot is None:
        try:
            snapshot = get_dashboard_snapshot(range_key)
        except Exception:
            snapshot = {}

    reply = "".join(parts).strip()
    if error and not reply:
        snapshot_text = _format_snapshot(snapshot) if snapshot else "(无数据快照)"
        reply = (
            " **LLM 调用失败，无法生成 AI 经营分析。**\n\n"
            f"**错误信息**：{error}\n\n"
            "**排查建议**：\n"
            "1. 检查 `ai-service/.env` 中 `OPENAI_API_KEY` 是否为真实有效密钥\n"
            "2. 确认 `OPENAI_BASE_URL` 指向可达的模型服务\n"
            "3. 确认 `OPENAI_MODEL`在对应平台已开通\n"
            "4. 查看 ai-service 日志获取详细错误堆栈\n\n"
            f"**当前数据快照**（供参考）：\n\n{snapshot_text}"
        )
        return {"reply": reply, "snapshot": snapshot, "llm_error": error}
    return {"reply": reply, "snapshot": snapshot, "llm_error": error}


def _format_snapshot(snapshot: dict) -> str:
    """将运营快照格式化为 LLM 可读的文本摘要。"""
    summary = snapshot.get("summary", {})
    lines = [
        f"统计区间: {snapshot.get('range', '7d')}",
        f"订单总数: {summary.get('totalOrders', 0)}",
        f"已支付订单: {summary.get('paidOrders', 0)}",
        f"营收: ¥{summary.get('totalRevenue', 0):.2f}",
        f"支付转化率: {summary.get('payRate', 0) * 100:.1f}%",
        f"客单价: ¥{summary.get('avgOrderValue', 0):.2f}",
    ]

    dist = snapshot.get("statusDistribution") or snapshot.get("status_distribution") or []
    if dist:
        dist_text = ", ".join(f"{d.get('label', d.get('status', '?'))}: {d.get('count', 0)}" for d in dist if d.get("count", 0) > 0)
        if dist_text:
            lines.append(f"订单状态分布: {dist_text}")

    hot = snapshot.get("hotProducts") or snapshot.get("hot_products") or []
    if hot:
        lines.append("热销商品 Top5:")
        for i, p in enumerate(hot[:5], 1):
            name = p.get("name") or p.get("product_name") or f"商品#{p.get('product_id', '?')}"
            qty = p.get("quantity") or p.get("sales_count") or 0
            rev = p.get("revenue") or 0
            stock = p.get("stock", "?")
            lines.append(f"  {i}. {name} — 销量 {qty}，营收 ¥{float(rev or 0):.2f}，库存 {stock}")

    trends = snapshot.get("trends") or []
    if trends:
        lines.append("每日趋势 (日期: 订单数/营收):")
        for t in trends[-7:]:
            date = (t.get("date") or "")[-5:]
            orders = t.get("totalOrders") or t.get("total_orders") or 0
            rev = t.get("totalRevenue") or t.get("total_revenue") or 0
            lines.append(f"  {date}: {orders} 单 / ¥{float(rev or 0):.2f}")

    alerts = snapshot.get("alerts") or []
    if alerts:
        lines.append("风险预警:")
        for a in alerts:
            lines.append(f"  - {a}")

    return "\n".join(lines)


def stream_agent(user_input: str, history: List[dict], user_id: Optional[int] = None) -> Generator[Any, None, None]:
    with trace_run(user_id, user_input):
        from validation import set_injected_user_id, reset_tool_sequence
        set_injected_user_id(user_id)
        reset_tool_sequence()

        route = _detect_route(user_input)
        update_current_run_route(route)
        action = None
        sources: list = []

        if route == "analysis":
            snapshot = get_dashboard_snapshot("7d")
            system_content = load_prompt("stream-analysis", snapshot=_format_snapshot(snapshot))
        elif route == "recommend":
            intent = {}
            try:
                intent_text = extract_procurement_intent.invoke({
                    "user_input": user_input,
                    "history": _history_as_text(history),
                })
                intent = json.loads(intent_text)
            except Exception:
                pass
            intent = _resolve_purchase_intent(user_input, history, intent)

            hot_text = get_hot_products.invoke({"limit": 5})
            product_query = (intent.get("product_query") or "").strip()
            has_filter = bool(
                product_query
                or intent.get("category_hint")
                or intent.get("budget_min") is not None
                or intent.get("budget_max") is not None
            )

            products_text = ""
            wants_purchase = intent.get("action_type") in {"add_to_cart", "buy_now"}
            if intent.get("needs_product_help") and has_filter:
                products_text = search_products.invoke({
                    "query": product_query,
                    "category": intent.get("category_hint", ""),
                    "budget_min": intent.get("budget_min"),
                    "budget_max": intent.get("budget_max"),
                })
                if wants_purchase:
                    action = _build_procurement_action(intent, products_text)

            sections = [f"[热销商品]\n{hot_text}"]
            if products_text:
                sections.append(f"[匹配商品]\n{products_text}")
            system_content = load_prompt(
                "stream-recommend",
                sections="\n\n".join(sections),
                action_guidance=_purchase_action_guidance(action, wants_purchase),
            )
        else:
            intent = {}
            try:
                intent_text = extract_procurement_intent.invoke({
                    "user_input": user_input,
                    "history": _history_as_text(history),
                })
                intent = json.loads(intent_text)
            except Exception:
                pass
            intent = _resolve_purchase_intent(user_input, history, intent)

            cs_product_query = (intent.get("product_query") or "").strip()
            cs_has_filter = bool(
                cs_product_query
                or intent.get("category_hint")
                or intent.get("budget_min") is not None
                or intent.get("budget_max") is not None
            )
            cs_wants_purchase = intent.get("action_type") in {"add_to_cart", "buy_now"}
            if intent.get("needs_product_help") and cs_has_filter:
                products_text = search_products.invoke({
                    "query": cs_product_query,
                    "category": intent.get("category_hint", ""),
                    "budget_min": intent.get("budget_min"),
                    "budget_max": intent.get("budget_max"),
                })
                if cs_wants_purchase:
                    action = _build_procurement_action(intent, products_text)
                system_content = load_prompt(
                    "stream-cs-product",
                    products_text=products_text,
                    action_guidance=_purchase_action_guidance(action, cs_wants_purchase),
                )
            else:
                retrieval_query = prepare_retrieval_query(user_input, history)
                context, sources = _retrieve_with_citations(retrieval_query)
                order_hint = ""
                lowered_input = user_input.lower()
                if any(kw in lowered_input for kw in ORDER_KEYWORDS):
                    order_hint = "\n\n[提示] 订单/物流查询请使用完整对话模式（非流式）以获取实时订单数据。"
                system_content = load_prompt(
                    "stream-cs-knowledge",
                    context=context or "(暂无相关内容)",
                    order_hint=order_hint,
                    action_guidance=_purchase_action_guidance(action, cs_wants_purchase),
                )
                if sources:
                    system_content += "\n\n" + load_prompt("answer-citation-rules")

        messages = [SystemMessage(content=system_content)] + _format_history(history) + [HumanMessage(content=user_input)]

        token_in = 0
        token_out = 0
        for chunk in _route_stream(messages):
            if hasattr(chunk, "content"):
                if chunk.content:
                    yield chunk.content
            elif chunk:
                yield chunk
            usage = getattr(chunk, "usage_metadata", None) if not isinstance(chunk, str) else None
            if usage:
                token_in += int(usage.get("input_tokens") or 0)
                token_out += int(usage.get("output_tokens") or 0)

        if action:
            yield {"action": action}

        if sources:
            yield {"sources": sources}

        token_usage = {"token_input": token_in, "token_output": token_out} if (token_in or token_out) else None
        yield {"meta": {"route": route, "token_usage": token_usage, "sources": sources or None}}