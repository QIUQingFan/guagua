from __future__ import annotations

import json
import re
from typing import Any, List, Optional

from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from sqlalchemy import text

from analytics import get_dashboard_snapshot
from config import settings
from database import engine
from rag import search_knowledge

llm = ChatOpenAI(
    model=settings.OPENAI_MODEL,
    openai_api_key=settings.OPENAI_API_KEY,
    openai_api_base=settings.OPENAI_BASE_URL,
    temperature=0.3,
)


CATEGORY_HINT_MAP = {
    "文创周边": ["文创", "帆布包", "明信片", "徽章", "周边", "礼盒", "贴纸", "手账", "书签"],
    "学习用品": ["教材", "笔记", "文具", "书本", "考研", "课程", "资料", "笔", "习题"],
    "二手数码": ["二手", "手机", "电脑", "耳机", "平板", "相机", "数码", "电子", "配件", "充电器"],
    "生活服务": ["代购", "跑腿", "打印", "洗衣", "维修", "代办", "服务", "复印"],
}


@tool
def search_products(
    query: str = "",
    category: str = "",
    brand: str = "",
    budget_min: Optional[float] = None,
    budget_max: Optional[float] = None,
    limit: int = 5,
) -> str:
    """
    Search for live products based on query criteria (瓜呱 products 表).

    Args:
        query: Product name or keywords to search
        category: Product category hint (e.g., 文创周边, 学习用品, 二手数码, 生活服务)
        brand: Brand/keyword to filter (瓜呱无 brand 字段，按 title 模糊匹配)
        budget_min: Minimum price
        budget_max: Maximum price
        limit: Number of results to return

    Returns:
        Formatted string of matched products with details
    """
    from guagua_adapter import PRODUCT_STATUS_ON_SALE

    base_clauses = [
        "p.is_deleted = 0",
        "p.status = :status",
        "COALESCE(p.stock, 0) > 0",
    ]
    params: dict[str, Any] = {"status": PRODUCT_STATUS_ON_SALE, "limit": limit}

    if budget_min is not None:
        base_clauses.append("p.price >= :budget_min")
        params["budget_min"] = budget_min
    if budget_max is not None:
        base_clauses.append("p.price <= :budget_max")
        params["budget_max"] = budget_max
    if brand:
        base_clauses.append("p.title LIKE :brand")
        params["brand"] = f"%{brand}%"
    if category:
        base_clauses.append("COALESCE(c.name, '') LIKE :category")
        params["category"] = f"%{category}%"

    order_clause = "COALESCE(p.sales, 0) DESC, p.price ASC"

    def run_query(extra_clauses: List[str], query_params: dict[str, Any]) -> List[dict]:
        sql = f"""
        SELECT
            p.id,
            p.title AS name,
            COALESCE(p.subtitle, '') AS subtitle,
            COALESCE(p.description, '') AS description,
            p.price,
            COALESCE(p.original_price, p.price) AS original_price,
            COALESCE(p.stock, 0) AS stock,
            COALESCE(p.cover_image, '') AS cover_image,
            COALESCE(p.sales, 0) AS sales,
            COALESCE(c.name, '') AS category_name
        FROM products p
        LEFT JOIN shop_categories c ON p.category_id = c.id
        WHERE {' AND '.join(base_clauses + extra_clauses)}
        ORDER BY {order_clause}
        LIMIT :limit
        """
        with engine.connect() as conn:
            rows = conn.execute(text(sql), query_params).mappings().all()

        return [
            {
                "id": row["id"],
                "name": row["name"],
                "subtitle": row["subtitle"],
                "description": row["description"],
                "price": float(row["price"] or 0),
                "originalPrice": float(row["original_price"] or 0),
                "stock": int(row["stock"] or 0),
                "coverImage": row["cover_image"],
                "sales": int(row["sales"] or 0),
                "categoryName": row["category_name"],
            }
            for row in rows
        ]

    products: List[dict] = []
    if query:
        params["product_query"] = f"%{query}%"
        precise_clauses = [
            "("
            "p.title LIKE :product_query OR "
            "COALESCE(p.subtitle, '') LIKE :product_query OR "
            "COALESCE(p.description, '') LIKE :product_query OR "
            "COALESCE(c.name, '') LIKE :product_query"
            ")"
        ]
        products = run_query(precise_clauses, params)

    if not products and category:
        products = run_query([], params)

    if not products and query:
        token_params = dict(params)
        token_clauses = []
        token_index = 0
        for token in re.split(r"[\s,，/]+", query):
            token = token.strip()
            if not token or len(token) <= 1:
                continue
            param_key = f"token_{token_index}"
            token_index += 1
            token_params[param_key] = f"%{token}%"
            token_clauses.append(
                "("
                f"p.title LIKE :{param_key} OR "
                f"COALESCE(p.subtitle, '') LIKE :{param_key} OR "
                f"COALESCE(p.description, '') LIKE :{param_key} OR "
                f"COALESCE(c.name, '') LIKE :{param_key}"
                ")"
            )
        if token_clauses:
            products = run_query(token_clauses, token_params)

    if not products:
        return "No matched live products were found."

    lines = []
    for index, item in enumerate(products, start=1):
        lines.append(
            f"{index}. #{item['id']} {item['name']} | "
            f"category: {item['categoryName'] or '-'} | "
            f"price: CNY {item['price']:.2f} | "
            f"sales: {item['sales']} | stock: {item['stock']}\n"
            f"   description: {item['description'] or '-'}"
        )
    return "\n".join(lines)


@tool
def query_user_orders(user_id: int, keyword: str = "", limit: int = 5) -> str:
    """
    查询当前登录用户的订单。

    【何时必须调用】当用户询问以下任一情况时**必须调用本工具**，不要用知识库或猜测回答：
    - 我的订单 / 订单查询 / 订单列表 / 订单到哪了
    - 物流 / 快递 / 发货状态 / 运单 / 快递单号
    - 收货 / 签收 / 配送
    - 订单号（如 SO20 开头）/ 某笔订单详情
    - 退款 / 退换货 / 售后进度（涉及具体订单时）

    Args:
        user_id: 用户ID（由网关注入，非用户输入）
        keyword: 订单号或商品标题关键词
        limit: 返回条数

    Returns:
        格式化的订单列表字符串（含订单号/状态/商品/金额/物流）
    """
    from validation import record_tool_call
    record_tool_call("query_user_orders")

    from guagua_adapter import ORDER_STATUS_LABELS

    if not user_id:
        return "未登录，无法查询订单。"

    sql = """
        SELECT o.id, o.order_no, o.status, o.pay_amount, o.tracking_company,
               o.tracking_no, o.created_at,
               GROUP_CONCAT(CONCAT(oi.product_title, '×', oi.quantity) SEPARATOR '; ') AS items
        FROM orders o
        LEFT JOIN order_items oi ON o.id = oi.order_id
        WHERE o.user_id = :user_id AND o.is_deleted = 0
    """
    params: dict[str, Any] = {"user_id": user_id, "limit": limit}

    if keyword:
        sql += " AND (o.order_no LIKE :kw_no OR oi.product_title LIKE :kw_title)"
        params["kw_no"] = f"%{keyword}%"
        params["kw_title"] = f"%{keyword}%"

    sql += " GROUP BY o.id ORDER BY o.created_at DESC LIMIT :limit"

    with engine.connect() as conn:
        rows = conn.execute(text(sql), params).fetchall()

    if not rows:
        return "您暂时没有订单记录。"

    lines = []
    for r in rows:
        status_label = ORDER_STATUS_LABELS.get(r.status, r.status)
        line = (
            f"- 订单号 {r.order_no}（{status_label}）\n"
            f"  商品：{r.items or '-'}\n"
            f"  金额：¥{r.pay_amount}\n"
            f"  下单时间：{r.created_at}"
        )
        if r.tracking_no:
            line += f"\n  物流：{r.tracking_company or ''} {r.tracking_no}"
        lines.append(line)
    return "\n".join(lines)


@tool
def get_business_snapshot(range_key: str = "7d") -> str:
    """
    Get business analytics snapshot including sales, orders, revenue, and trends.

    Args:
        range_key: Time range. One of: today, 7d, 30d

    Returns:
        Formatted business snapshot report
    """
    snapshot = get_dashboard_snapshot(range_key)
    summary = snapshot.get("summary", {})
    comparison = snapshot.get("comparison", {})
    funnel = snapshot.get("funnel", {})
    hot_products = snapshot.get("hotProducts", [])
    alerts = snapshot.get("alerts", [])

    lines = [
        f"Range: {snapshot.get('range', '7d')}",
        f"Generated at: {snapshot.get('generatedAt', '-')}",
        "",
        "Core metrics:",
        f"- total orders: {summary.get('totalOrders', 0)}",
        f"- paid orders: {summary.get('paidOrders', 0)}",
        f"- pending orders: {summary.get('pendingOrders', 0)}",
        f"- total revenue: CNY {summary.get('totalRevenue', 0):.2f}",
        f"- pay rate: {summary.get('payRate', 0) * 100:.1f}%",
        f"- average order value: CNY {summary.get('avgOrderValue', 0):.2f}",
        f"- new users: {summary.get('newUsers', 0)}",
        f"- repeat buyers: {summary.get('repeatBuyers', 0)}",
        "",
        "Comparison versus previous period:",
        f"- orders delta: {comparison.get('ordersDelta', 0):+d}",
        f"- revenue delta: CNY {comparison.get('revenueDelta', 0):+.2f}",
        f"- pay rate delta: {comparison.get('payRateDelta', 0) * 100:+.1f}%",
        f"- average order value delta: CNY {comparison.get('avgOrderValueDelta', 0):+.2f}",
        "",
        "Conversion funnel:",
        f"- views: {funnel.get('views', 0)}",
        f"- carts: {funnel.get('carts', 0)}",
        f"- purchases: {funnel.get('purchases', 0)}",
        f"- view to cart rate: {funnel.get('viewToCartRate', 0) * 100:.1f}%",
        f"- cart to purchase rate: {funnel.get('cartToPurchaseRate', 0) * 100:.1f}%",
    ]

    if hot_products:
        lines.extend(["", "Top products:"])
        for index, item in enumerate(hot_products[:5], start=1):
            lines.append(
                f"- {index}. {item['name']}, quantity {item['quantity']}, "
                f"revenue CNY {item['revenue']:.2f}, stock {item['stock']}"
            )

    if alerts:
        lines.extend(["", "Alerts:"])
        lines.extend(f"- {alert}" for alert in alerts)

    return "\n".join(lines)


@tool
def search_knowledge_base(query: str, top_k: int = 4) -> str:
    """
    Search knowledge base for FAQ and product information.

    Args:
        query: Search query
        top_k: Number of results to return

    Returns:
        Formatted search results from knowledge base
    """
    from validation import record_tool_call
    record_tool_call("search_knowledge_base")

    docs = search_knowledge(query, top_k=top_k)
    if not docs:
        return "(no relevant content found)"
    return "\n\n---\n\n".join([content for content, _ in docs])


@tool
def get_hot_products(limit: int = 5, range_key: str = "30d") -> str:
    """
    Get the current best-selling products sorted by sales.

    【何时调用】用户询问热销/畅销/爆款/推荐商品，或需要热门商品上下文时调用。

    Args:
        limit: 返回商品数量（默认5）
        range_key: 时间范围占位（默认30d，当前按全量销量排序）

    Returns:
        热销商品列表（含名称、价格、库存、销量、分类）
    """
    from guagua_adapter import PRODUCT_STATUS_ON_SALE

    sql = """
        SELECT
            p.id,
            p.title AS name,
            p.price,
            COALESCE(p.stock, 0) AS stock,
            COALESCE(p.sales, 0) AS sales,
            COALESCE(p.subtitle, '') AS subtitle,
            COALESCE(c.name, '') AS category_name
        FROM products p
        LEFT JOIN shop_categories c ON p.category_id = c.id
        WHERE p.is_deleted = 0
          AND p.status = :status
          AND p.stock > 0
        ORDER BY p.sales DESC, p.created_at DESC
        LIMIT :limit
    """
    params: dict[str, Any] = {"status": PRODUCT_STATUS_ON_SALE, "limit": limit}

    with engine.connect() as conn:
        rows = conn.execute(text(sql), params).mappings().all()

    if not rows:
        return "No hot product data available."

    lines = ["Recent hot products:"]
    for index, item in enumerate(rows, start=1):
        lines.append(
            f"{index}. #{item['id']} {item['name']} | "
            f"category: {item['category_name'] or '-'} | "
            f"price: CNY {float(item['price'] or 0):.2f} | "
            f"sales: {int(item['sales'] or 0)} | stock: {int(item['stock'] or 0)}"
        )
    return "\n".join(lines)


@tool
def extract_procurement_intent(user_input: str) -> str:
    """
    Extract procurement intent from user input, including product query, budget, category, etc.

    Args:
        user_input: User's message

    Returns:
        JSON string containing extracted intent information
    """
    default = {
        "needs_product_help": False,
        "action_type": "none",
        "product_query": "",
        "category_hint": "",
        "brand_hint": "",
        "budget_min": None,
        "budget_max": None,
        "quantity": 1,
        "sort": "sales_desc",
    }

    prompt = (
        "你是瓜呱商城的购物意图解析器。分析用户输入，返回**仅 JSON**（无其它文字）：\n"
        "{\n"
        '  "needs_product_help": boolean,  // 是否需要商品帮助/推荐/购买\n'
        '  "action_type": "none" | "recommend" | "add_to_cart" | "buy_now",\n'
        '  "product_query": string,        // 商品关键词\n'
        '  "category_hint": string,        // 品类：文创周边/学习用品/二手数码/生活服务\n'
        '  "brand_hint": string,\n'
        '  "budget_min": number | null,\n'
        '  "budget_max": number | null,\n'
        '  "quantity": integer,\n'
        '  "sort": "sales_desc" | "price_asc" | "price_desc"\n'
        "}\n\n"
        "action_type 判定规则（重要）：\n"
        '- "buy_now": 用户表达「立即购买」「现在下单」「直接买」「马上下单」「秒杀」「下单」「买」「来一份」「帮我下单」「我要下单」等即时成交意愿。'
        '关键：只要用户提到具体商品并含「下单/买」等成交动词，即为 buy_now（系统会下发「立即购买」按钮，前端跳转结算页完成下单）。\n'
        '- "add_to_cart": 用户表达「加购」「加入购物车」「加到购物车」「想要」「来一个」「买这个」「来份」「要这个」等明确指向某商品、但强调加入购物车而非立即成交的意愿\n'
        '- "recommend": 用户表达「推荐」「有什么」「选哪个」「性价比」「值得买」等寻求建议（未指明要下单）\n'
        '- "none": 仅咨询、查订单、查政策等非购物意图\n'
        "注意：只要用户提到具体商品并表达购买/下单意愿，needs_product_help=true 且 action_type 为 buy_now 或 add_to_cart；"
        "「下单」默认归为 buy_now。务必从用户输入中提取 product_query（商品名/关键词），否则无法定位商品。\n\n"
        f"用户输入: {user_input}\n"
    )

    try:
        result = llm.invoke([{"role": "user", "content": prompt}])
        content = result.content or ""
        try:
            parsed = json.loads(content)
        except Exception:
            match = re.search(r"\{.*\}", content, re.S)
            if match:
                parsed = json.loads(match.group(0))
            else:
                parsed = default
    except Exception:
        parsed = default

    parsed["needs_product_help"] = bool(parsed.get("needs_product_help"))
    parsed["action_type"] = str(parsed.get("action_type") or "none")
    parsed["product_query"] = str(parsed.get("product_query") or "").strip()
    parsed["category_hint"] = str(parsed.get("category_hint") or "").strip()
    parsed["brand_hint"] = str(parsed.get("brand_hint") or "").strip()
    parsed["sort"] = str(parsed.get("sort") or "sales_desc")

    try:
        parsed["quantity"] = max(1, int(parsed.get("quantity") or 1))
    except Exception:
        parsed["quantity"] = 1

    for key in ("budget_min", "budget_max"):
        value = parsed.get(key)
        if value in ("", None):
            parsed[key] = None
            continue
        try:
            parsed[key] = float(value)
        except Exception:
            parsed[key] = None

    if parsed["action_type"] not in {"none", "recommend", "add_to_cart", "buy_now"}:
        parsed["action_type"] = "none"
    if parsed["sort"] not in {"sales_desc", "price_asc", "price_desc"}:
        parsed["sort"] = "sales_desc"

    text_content = user_input.strip()
    range_match = re.search(r"(\d+(?:\.\d+)?)\s*(?:-|到|至)\s*(\d+(?:\.\d+)?)\s*(?:元|块)?", text_content)
    if range_match:
        parsed["budget_min"] = float(range_match.group(1))
        parsed["budget_max"] = float(range_match.group(2))
    else:
        max_match = re.search(r"(\d+(?:\.\d+)?)\s*(?:元|块)?\s*(?:以内|以下|之内|不超过|最多|封顶)", text_content)
        if max_match:
            parsed["budget_max"] = float(max_match.group(1))
        min_match = re.search(r"(\d+(?:\.\d+)?)\s*(?:元|块)?\s*(?:以上|起|及以上|至少)", text_content)
        if min_match:
            parsed["budget_min"] = float(min_match.group(1))

    if not parsed.get("category_hint"):
        lowered = text_content.lower()
        for category, keywords in CATEGORY_HINT_MAP.items():
            if any(keyword.lower() in lowered for keyword in keywords):
                parsed["category_hint"] = category
                break

    return json.dumps(parsed, ensure_ascii=False)


@tool
def execute_aftersales_action(
    user_id: int,
    order_id: int,
    action_type: str,
    reason: str,
    amount: Optional[float] = None,
) -> str:
    """
    Execute an after-sales action (refund / exchange / logistics intercept).

    【何时调用】用户申请退款、退货、换货、补发，且已通过 query_user_orders 确认订单状态后调用。

    【前置约束（必须严格遵守）】
    1. 必须先调用 query_user_orders 确认订单存在与状态，禁止跳过「先查后动」。
    2. reason 必填：必须从用户对话中获取真实退款/换货理由，禁止编造（如"不想要了"）。
    3. action_type 必须与订单状态匹配：
       - 未发货（待付款/待发货）→ CANCEL_ORDER_REFUND（极速退款）
       - 运输中（待收货）→ INTERCEPT_LOGISTICS（物流拦截）
       - 已签收（已完成）→ RETURN_AND_REFUND（退货退款）或 EXCHANGE_GOODS（换货）
    4. user_id 由系统注入，禁止操作他人订单。

    Args:
        user_id: 当前登录用户ID（由网关注入）
        order_id: 订单ID
        action_type: 售后动作: CANCEL_ORDER_REFUND/INTERCEPT_LOGISTICS/RETURN_AND_REFUND/EXCHANGE_GOODS
        reason: 售后原因（必填，从用户对话获取，禁止编造）
        amount: 涉及金额（可选）

    Returns:
        工单处理结果字符串
    """
    from validation import (
        ValidationContext, validate_tool_call, record_tool_call,
        get_prior_tools, get_injected_user_id, log_violations,
    )
    _vctx = ValidationContext(
        injected_user_id=get_injected_user_id(),
        prior_tool_names=get_prior_tools(),
    )
    _vres = validate_tool_call("execute_aftersales_action", {
        "user_id": user_id, "order_id": order_id,
        "action_type": action_type, "reason": reason, "amount": amount,
    }, _vctx)
    record_tool_call("execute_aftersales_action")
    if not _vres.passed:
        log_violations("execute_aftersales_action", _vres.violations, phase="inline")
        return _vres.guidance

    import random
    import time

    from guagua_adapter import (
        AFTER_SALES_ACTION_TYPES,
        ORDER_STATUS_GROUP_LABELS,
        get_status_group,
        is_aftersales_allowed,
    )

    if not user_id:
        return "未登录，无法发起售后申请。"
    if action_type not in AFTER_SALES_ACTION_TYPES:
        return f"无效的售后动作: {action_type}。"
    if not reason or not reason.strip():
        return "缺少售后原因。请先向用户确认退款/换货理由后再发起申请。"

    sql = """
        SELECT id, order_no, status, user_id, pay_amount
        FROM orders
        WHERE id = :order_id AND is_deleted = 0
    """
    with engine.connect() as conn:
        row = conn.execute(text(sql), {"order_id": order_id}).mappings().first()

    if not row:
        return f"未找到订单 #{order_id}。"
    if row["user_id"] != user_id:
        return "无权操作该订单。"

    status = row["status"]
    group = get_status_group(status)
    group_label = ORDER_STATUS_GROUP_LABELS.get(group, group)

    if not is_aftersales_allowed(status, action_type):
        return f"订单 {row['order_no']} 当前状态为「{group_label}」，不支持该售后动作。"

    ticket_no = f"AS{time.strftime('%Y%m%d%H%M%S')}{random.randint(1000, 9999)}"
    insert_sql = """
        INSERT INTO ai_aftersales_tickets
            (ticket_no, order_id, user_id, action_type, reason, amount, status, source)
        VALUES
            (:ticket_no, :order_id, :user_id, :action_type, :reason, :amount, 'processing', 'ai')
    """
    with engine.begin() as conn:
        conn.execute(text(insert_sql), {
            "ticket_no": ticket_no,
            "order_id": order_id,
            "user_id": user_id,
            "action_type": action_type,
            "reason": reason.strip(),
            "amount": amount,
        })

    return (
        f"已提交售后申请，工单号 {ticket_no}。\n"
        f"订单 {row['order_no']}（{group_label}）→ 动作: {action_type}\n"
        f"原因: {reason.strip()}\n"
        f"系统正在处理中，预计1-3个工作日反馈。"
    )


@tool
def system_transfer_human(user_id: int, reason: str, priority: str = "normal") -> str:
    """
    Transfer to human customer service.

    【何时调用】满足以下任一条件时调用：
    1. 已先调用 search_knowledge_base 尝试自助引导，但知识库无法解决。
    2. 用户情绪激烈（辱骂、强烈投诉）。
    3. 涉及复杂纠纷（多笔订单争议、金额争议）。

    【前置约束】
    1. 转人工前必须先尝试 search_knowledge_base 拦截（降本增效）。
    2. reason 必须是 LLM 总结的结构化问题摘要，不得为「转人工」三个字。
    3. priority: normal/urgent，情绪激烈或时效威胁用 urgent。

    Args:
        user_id: 当前登录用户ID（由网关注入，游客可为空）
        reason: 结构化问题摘要（不得为「转人工」）
        priority: 优先级 normal/urgent

    Returns:
        转接结果字符串
    """
    from validation import (
        ValidationContext, validate_tool_call, record_tool_call,
        get_prior_tools, get_injected_user_id, log_violations,
    )
    _vctx = ValidationContext(
        injected_user_id=get_injected_user_id(),
        prior_tool_names=get_prior_tools(),
    )
    _vres = validate_tool_call("system_transfer_human", {
        "user_id": user_id, "reason": reason,
    }, _vctx)
    record_tool_call("system_transfer_human")
    if not _vres.passed:
        log_violations("system_transfer_human", _vres.violations, phase="inline")
        return _vres.guidance

    if not reason or not reason.strip():
        return "缺少转人工原因。请先总结用户问题。"
    if reason.strip() in ("转人工", "人工", "转人工客服"):
        return "转人工原因不能仅为「转人工」，请总结用户的具体问题。"
    if priority not in ("normal", "urgent"):
        priority = "normal"

    insert_sql = """
        INSERT INTO ai_human_transfer_logs
            (user_id, reason, priority, status)
        VALUES
            (:user_id, :reason, :priority, 'pending')
    """
    with engine.begin() as conn:
        conn.execute(text(insert_sql), {
            "user_id": user_id,
            "reason": reason.strip(),
            "priority": priority,
        })

    if priority == "urgent":
        return "已为您加急转接人工客服，请稍候，客服将尽快接入。"
    return "已为您转接人工客服，当前排队中，请稍候。"


@tool
def execute_update_address(user_id: int, order_id: int, new_address: str) -> str:
    """
    Update the shipping address of an order.

    【何时调用】用户要求修改收货地址，且已通过 query_user_orders 确认订单状态后调用。

    【前置约束（必须严格遵守）】
    1. 必须先调用 query_user_orders 确认订单状态，禁止跳过「先查后动」。
    2. new_address 必填：若用户未提供具体新地址，必须 Final Answer 索要，禁止调用本工具。
    3. 状态硬约束：
       - 已签收（已完成）/ 终态（已取消/已关闭）→ 禁止修改，直接拒绝
       - 运输中（待收货）→ 可修改，但需提示"可能产生转寄费用或物流延时"
       - 未发货（待付款/待发货）→ 可直接修改
    4. user_id 由系统注入，禁止操作他人订单。

    Args:
        user_id: 当前登录用户ID（由网关注入）
        order_id: 订单ID
        new_address: 新收货地址（必填，非占位符）

    Returns:
        修改结果字符串
    """
    from validation import (
        ValidationContext, validate_tool_call, record_tool_call,
        get_prior_tools, get_injected_user_id, log_violations,
    )
    _vctx = ValidationContext(
        injected_user_id=get_injected_user_id(),
        prior_tool_names=get_prior_tools(),
    )
    _vres = validate_tool_call("execute_update_address", {
        "user_id": user_id, "order_id": order_id, "new_address": new_address,
    }, _vctx)
    record_tool_call("execute_update_address")
    if not _vres.passed:
        log_violations("execute_update_address", _vres.violations, phase="inline")
        return _vres.guidance

    from guagua_adapter import (
        ORDER_STATUS_GROUP_LABELS,
        get_status_group,
        is_address_modifiable,
        needs_address_risk_warning,
    )

    if not user_id:
        return "未登录，无法修改地址。"
    if not new_address or not new_address.strip():
        return "缺少新收货地址。请先向用户确认新地址后再发起修改。"
    placeholder = new_address.strip().lower()
    if placeholder in ("null", "none", "待补充", "[user_address]", "未知", ""):
        return "新地址无效。请向用户索取具体的收货地址。"

    sql = """
        SELECT id, order_no, status, user_id, address
        FROM orders
        WHERE id = :order_id AND is_deleted = 0
    """
    with engine.connect() as conn:
        row = conn.execute(text(sql), {"order_id": order_id}).mappings().first()

    if not row:
        return f"未找到订单 #{order_id}。"
    if row["user_id"] != user_id:
        return "无权操作该订单。"

    status = row["status"]
    group = get_status_group(status)
    group_label = ORDER_STATUS_GROUP_LABELS.get(group, group)

    if not is_address_modifiable(status):
        return f"订单 {row['order_no']} 当前状态为「{group_label}」，商品已到货或已关闭，无法修改收货地址。"

    update_sql = "UPDATE orders SET address = :new_address WHERE id = :order_id"
    with engine.begin() as conn:
        conn.execute(text(update_sql), {
            "new_address": new_address.strip(),
            "order_id": order_id,
        })

    if needs_address_risk_warning(status):
        return (
            f"订单 {row['order_no']} 的收货地址已修改成功。\n"
            f"⚠ 由于订单已在运输中，修改地址可能产生转寄费用或导致物流延时，请知悉。"
        )
    return f"订单 {row['order_no']} 的收货地址已修改成功。"


RECOMMEND_TOOLS = [
    search_products,
    get_hot_products,
    extract_procurement_intent,
]

ANALYSIS_TOOLS = [
    get_business_snapshot,
    get_hot_products,
    search_products,
]

CUSTOMER_SERVICE_TOOLS = [
    search_knowledge_base,
    search_products,
    extract_procurement_intent,
    query_user_orders,
    execute_aftersales_action,
    system_transfer_human,
    execute_update_address,
]
