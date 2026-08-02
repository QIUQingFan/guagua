"""
瓜呱业务适配层
"""

TABLE_MAP = {
    "am_product": "products",
    "am_category": "shop_categories",
    "am_order": "orders",
    "am_order_item": "order_items",
    "am_user": "users",
    "am_user_behavior": "ai_user_behaviors",
}

PRODUCT_FIELD_MAP = {
    "name": "title",
    "deleted": "is_deleted",
    "status": "status",
    "cover_image": "cover_image",
    "original_price": "original_price",
    "create_time": "created_at",
}

ORDER_FIELD_MAP = {
    "order_no": "order_no",
    "receiver_name": "receiver",
    "pay_amount": "pay_amount",
    "total_amount": "total_amount",
    "create_time": "created_at",
}

ORDER_ITEM_FIELD_MAP = {
    "total_price": "subtotal",
}

PRODUCT_STATUS_ON_SALE = "on_sale"
PRODUCT_STATUS_DELETED = 1

ORDER_STATUS_MAP = {
    0: "pending_payment",
    1: "pending_shipment",
    2: "shipped",
    3: "completed",
    4: "cancelled",
    5: "closed",
    6: "closed",
}

ORDER_STATUS_LABELS = {
    "pending_payment": "待付款",
    "pending_shipment": "待发货",
    "shipped": "待收货",
    "completed": "已完成",
    "cancelled": "已取消",
    "closed": "已关闭",
}

PAID_STATUSES = ("pending_shipment", "shipped", "completed")



def paid_statuses_sql(column: str = "status") -> str:
    """
    生成判断「已付款」状态的 SQL 片段（用于 IN 子句）。
    例: paid_statuses_sql() => "'pending_shipment','shipped','completed'"
    """
    return ",".join([f"'{s}'" for s in PAID_STATUSES])


ORDER_STATUS_GROUP = {
    "pending_payment": "UNSHIPPED",
    "pending_shipment": "UNSHIPPED",
    "shipped": "IN_TRANSIT",
    "completed": "RECEIVED",
    "cancelled": "TERMINATED",
    "closed": "TERMINATED",
}

ORDER_STATUS_GROUP_LABELS = {
    "UNSHIPPED": "未发货",
    "IN_TRANSIT": "运输中",
    "RECEIVED": "已签收",
    "TERMINATED": "终态",
}

AFTER_SALES_ACTION_TYPES = {
    "CANCEL_ORDER_REFUND",
    "INTERCEPT_LOGISTICS",
    "RETURN_AND_REFUND",
    "EXCHANGE_GOODS",
}

STATE_ACTION_MATRIX = {
    "UNSHIPPED":  {"CANCEL_ORDER_REFUND"},
    "IN_TRANSIT": {"INTERCEPT_LOGISTICS"},
    "RECEIVED":   {"RETURN_AND_REFUND", "EXCHANGE_GOODS"},
    "TERMINATED": set(),
}

ADDRESS_MODIFIABLE_GROUPS = {"UNSHIPPED", "IN_TRANSIT"}
ADDRESS_RISK_WARNING_GROUPS = {"IN_TRANSIT"}


def get_status_group(status: str) -> str:
    """订单状态 → 语义分组（未发货/运输中/已签收/终态）。未知状态归为终态。"""
    return ORDER_STATUS_GROUP.get(status, "TERMINATED")


def is_address_modifiable(status: str) -> bool:
    """订单状态是否允许修改收货地址。"""
    return get_status_group(status) in ADDRESS_MODIFIABLE_GROUPS


def needs_address_risk_warning(status: str) -> bool:
    """修改地址是否需要额外风险提示（运输中可能产生转寄费用/延时）。"""
    return get_status_group(status) in ADDRESS_RISK_WARNING_GROUPS


def is_aftersales_allowed(status: str, action_type: str) -> bool:
    """订单状态是否允许执行指定售后 action。"""
    return action_type in STATE_ACTION_MATRIX.get(get_status_group(status), set())
