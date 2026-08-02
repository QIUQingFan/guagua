"""工具调用合法性校验层"""
from __future__ import annotations

import contextvars
import logging
from dataclasses import dataclass, field
from typing import Any, List, Optional

logger = logging.getLogger("validation")

TOOL_METADATA: dict[str, dict] = {
    "execute_aftersales_action": {
        "required": ["user_id", "order_id", "action_type", "reason"],
        "prerequisites": ["query_user_orders"],
        "placeholder_blacklist": ["null", "none", "待补充", "未知", "[user_reason]"],
        "param_rules": {
            "reason": {"non_empty": True, "not_in": {"不想要了", "无", "随便"}},
        },
    },
    "system_transfer_human": {
        "required": ["user_id", "reason"],
        "prerequisites": ["search_knowledge_base"],
        "placeholder_blacklist": ["null", "none", "待补充", "[user_reason]"],
        "param_rules": {
            "reason": {"non_empty": True, "not_in": {"转人工", "人工", "转人工客服"}},
        },
    },
    "execute_update_address": {
        "required": ["user_id", "order_id", "new_address"],
        "prerequisites": ["query_user_orders"],
        "placeholder_blacklist": ["null", "none", "待补充", "未知", "[user_address]"],
        "param_rules": {
            "new_address": {"non_empty": True},
        },
    },
}

VALIDATABLE_TOOLS = set(TOOL_METADATA.keys())

GENERIC_PLACEHOLDERS = {"", "null", "none", "nan", "待补充", "未知", "undefined", "string", "int"}


_injected_user_id: contextvars.ContextVar = contextvars.ContextVar("injected_user_id", default=None)
_tool_call_seq: contextvars.ContextVar = contextvars.ContextVar("tool_call_seq", default=None)


def set_injected_user_id(uid: Optional[int]) -> None:
    """由 customer_service_node 在 invoke react_agent 前设置网关注入的 user_id。"""
    _injected_user_id.set(uid)


def get_injected_user_id() -> Optional[int]:
    return _injected_user_id.get()


def reset_tool_sequence() -> None:
    """每次客服 Agent 推理开始前重置工具调用序列。"""
    _tool_call_seq.set([])


def record_tool_call(name: str) -> None:
    """工具执行时登记自身，供后续工具的序列合法性校验。"""
    seq = _tool_call_seq.get() or []
    seq.append(name)
    _tool_call_seq.set(seq)


def get_prior_tools() -> list:
    seq = _tool_call_seq.get()
    return list(seq) if seq else []


@dataclass
class Violation:
    dimension: str
    code: str
    message: str


@dataclass
class ValidationContext:
    injected_user_id: Optional[int] = None
    prior_tool_names: list = field(default_factory=list)


@dataclass
class ValidationResult:
    passed: bool
    violations: List[Violation] = field(default_factory=list)

    @property
    def guidance(self) -> str:
        """违规时生成引导话术，作为 Observation 回给 LLM 促其自修正。"""
        if self.passed:
            return ""
        prefix = "⚠ 操作未通过合规校验，请调整后重试："
        return prefix + "；".join(v.message for v in self.violations)


def validate_tool_call(tool_name: str, args: dict, context: ValidationContext) -> ValidationResult:
    """对一次工具调用做维度校验"""
    violations: List[Violation] = []

    meta = TOOL_METADATA.get(tool_name)
    if not meta:
        return ValidationResult(passed=True)

    for prereq in meta.get("prerequisites", []):
        if prereq not in context.prior_tool_names:
            violations.append(Violation(
                dimension="序列",
                code="MISSING_PREREQUISITE",
                message=f"执行 {tool_name} 前需先调用 {prereq} 确认信息（先查后动）",
            ))

    placeholder_set = {p.lower() for p in meta.get("placeholder_blacklist", [])}
    for param in meta.get("required", []):
        val = args.get(param)
        if val is None:
            violations.append(Violation(
                dimension="必填",
                code="MISSING_PARAM",
                message=f"缺少必填参数: {param}",
            ))
            continue
        val_str = str(val).strip()
        val_lower = val_str.lower()
        if val_lower in GENERIC_PLACEHOLDERS or val_lower in placeholder_set:
            violations.append(Violation(
                dimension="参数",
                code="PLACEHOLDER_PARAM",
                message=f"参数 {param} 为占位符（{val_str}），请向用户确认真实值",
            ))

    for param, rule in meta.get("param_rules", {}).items():
        val = args.get(param)
        if val is None:
            continue
        val_str = str(val).strip()
        if rule.get("non_empty") and not val_str:
            violations.append(Violation(
                dimension="参数",
                code="EMPTY_PARAM",
                message=f"参数 {param} 不能为空",
            ))
        if rule.get("not_in") and val_str in rule["not_in"]:
            violations.append(Violation(
                dimension="语义",
                code="INVALID_VALUE",
                message=f"参数 {param} 的值「{val_str}」无效，请提供具体内容",
            ))

    if "user_id" in args and context.injected_user_id is not None:
        uid = args.get("user_id")
        try:
            if int(uid) != int(context.injected_user_id):
                violations.append(Violation(
                    dimension="安全",
                    code="USER_ID_MISMATCH",
                    message="user_id 与登录身份不符，禁止越权操作",
                ))
        except (TypeError, ValueError):
            violations.append(Violation(
                dimension="安全",
                code="USER_ID_INVALID",
                message="user_id 参数非法，禁止越权操作",
            ))

    return ValidationResult(passed=len(violations) == 0, violations=violations)


def log_violations(tool_name: str, violations: List[Violation], phase: str = "inline") -> None:
    for v in violations:
        logger.warning(
            "[validation/%s] tool=%s dim=%s code=%s msg=%s",
            phase, tool_name, v.dimension, v.code, v.message,
        )


def extract_tool_calls_from_messages(messages: list) -> list:
    """
    从 create_react_agent 的 result messages 提取工具调用序列。

    Returns:
        [{"name": str, "args": dict, "output_preview": str}, ...]
    """
    from langchain_core.messages import AIMessage, ToolMessage

    trace: list = []
    tool_output_map: dict[str, str] = {}
    for msg in messages:
        if isinstance(msg, ToolMessage):
            tool_output_map[msg.tool_call_id] = str(msg.content)[:200]

    for msg in messages:
        if isinstance(msg, AIMessage) and getattr(msg, "tool_calls", None):
            for tc in msg.tool_calls:
                trace.append({
                    "name": tc.get("name", ""),
                    "args": tc.get("args", {}) or {},
                    "output_preview": tool_output_map.get(tc.get("id", ""), ""),
                })
    return trace


def audit_tool_calls(trace: list, injected_user_id: Optional[int]) -> dict:
    prior: list = []
    details: list = []
    violation_count = 0
    validatable_count = 0

    for call in trace:
        name = call.get("name", "")
        args = call.get("args", {})
        if name in VALIDATABLE_TOOLS:
            validatable_count += 1
            ctx = ValidationContext(injected_user_id=injected_user_id, prior_tool_names=prior)
            vr = validate_tool_call(name, args, ctx)
            if not vr.passed:
                violation_count += len(vr.violations)
                log_violations(name, vr.violations, phase="audit")
                details.append({
                    "tool": name,
                    "violations": [{"dim": v.dimension, "code": v.code} for v in vr.violations],
                })
        prior.append(name)

    return {
        "total": len(trace),
        "validatable": validatable_count,
        "violations": violation_count,
        "details": details,
    }
