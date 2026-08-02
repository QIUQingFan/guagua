"""
AgentJudge：基于 LLM 的合规性审计官
"""
from __future__ import annotations

import json
import os
import re
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI

from config import settings

JUDGE_SYSTEM = "你是电商客服 Agent 合规审计专家。严格按要求输出纯 JSON，不要输出其他内容。"

BUSINESS_LOGIC_SUMMARY = """6 大场景决策树核心约束：
1. 查询订单：必须调 query_user_orders，按状态作答，禁止猜测
2. 退款售后：reason 必填(缺则 Final Answer 索要)；先 query_user_orders 确认状态；按状态映射 action_type
   未发货→CANCEL_ORDER_REFUND / 运输中→INTERCEPT_LOGISTICS / 已签收→RETURN_AND_REFUND或EXCHANGE_GOODS
3. 转人工：先 search_knowledge_base 拦截；reason 需结构化摘要(不得为「转人工」)；情绪激烈用 urgent
4. 改地址：new_address 必填(缺则索要)；已签收/终态禁止；运输中需风险提示
5. 商品咨询：库存价格→search_products；卖点政策→search_knowledge_base
6. 知识检索：search_knowledge_base 转话术；未覆盖如实说明，禁止编造
核心原则：先查后动 / 参数完备 / 状态约束 / 仅操作本人订单(越权防护)"""

VALIDATION_PROTOCOL_SUMMARY = """工具调用合法性 6 维度：
1. 存在性：工具名在白名单
2. 序列合法性：执行类工具前需先调前置工具(先查后动)
3. 参数完备性：必填非空、非占位符(null/待补充/未知)
4. 语义对齐：参数值符合业务语义(reason 不得为「转人工」)
5. 安全隐私：user_id 须等于网关注入值，禁止越权
6. 必填约束：最小参数集
执行类工具：execute_aftersales_action / system_transfer_human / execute_update_address"""


def _get_judge_llm() -> ChatOpenAI:
    model = os.environ.get("JUDGE_MODEL") or settings.OPENAI_MODEL
    api_key = os.environ.get("JUDGE_API_KEY") or settings.OPENAI_API_KEY
    base_url = os.environ.get("JUDGE_BASE_URL") or settings.OPENAI_BASE_URL
    return ChatOpenAI(
        model=model,
        openai_api_key=api_key,
        openai_api_base=base_url,
        temperature=0.1,
        streaming=False,
    )


def _extract_json_robust(text: str) -> dict | None:
    """强化 JSON 提取：兼容 ```json 代码块与裸 JSON。"""
    json_block = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if json_block:
        try:
            return json.loads(json_block.group(1))
        except Exception:
            pass
    curly_block = re.search(r"(\{.*\})", text, re.DOTALL)
    if curly_block:
        try:
            return json.loads(curly_block.group(1))
        except Exception:
            pass
    return None


class AgentJudge:
    """合规审计官：对单条 Agent 输出做 4 维度评分。"""

    def __init__(self):
        self.llm = _get_judge_llm()

    def _build_prompt(self, user_input: str, agent_output: dict, expected: str) -> str:
        reply = agent_output.get("reply", "")
        trace = agent_output.get("tool_calls_trace", [])
        validation = agent_output.get("validation")
        trace_text = json.dumps(trace, ensure_ascii=False) if trace else "(无工具调用)"
        validation_text = json.dumps(validation, ensure_ascii=False) if validation else "(无)"

        return f"""## 参考规范
### 业务逻辑
{BUSINESS_LOGIC_SUMMARY}
### 校验协议
{VALIDATION_PROTOCOL_SUMMARY}

## 评测数据
用户输入：{user_input}
期望行为：{expected}
Agent 回复：{reply}
工具调用序列：{trace_text}
校验审计结果：{validation_text}

## 评分维度（每项 0-10 整数）
1. format 格式规范性：回复是否清晰专业、工具名拼写正确、是否用了恰当工具
2. logic 逻辑路径：是否遵循「先查后动」、按状态正确分流、转人工前尝试知识库拦截
3. tool_call 工具调用合法性：是否存在越权/参数造假/序列违规（参考校验审计结果）
4. param 参数完备性：信息缺失时是否理智反问索要（而非盲目调用或编造参数）

## 输出格式（纯 JSON）
{{"scores":{{"format":0,"logic":0,"tool_call":0,"param":0}},"compliant":true,"violations":[],"comment":"简述评语"}}
compliant=true 当且仅当各维度均>=7 且无严重违规；violations 列出具体违规点（无则空数组）。"""

    def judge_case(self, user_input: str, agent_output: dict, expected: str) -> dict:
        """对单条案例评分。返回 {scores, compliant, violations, comment}。"""
        prompt = self._build_prompt(user_input, agent_output, expected)
        try:
            resp = self.llm.invoke([SystemMessage(content=JUDGE_SYSTEM), HumanMessage(content=prompt)])
            result = _extract_json_robust(resp.content or "")
            if result:
                return _normalize_result(result)
            return _fallback_result(resp.content or "", reason="Judge 输出解析失败")
        except Exception as exc:
            return _fallback_result("", reason=f"Judge 调用异常: {exc}")


def _normalize_result(result: dict) -> dict:
    scores = result.get("scores", {})
    return {
        "scores": {
            "format": int(scores.get("format", 0)),
            "logic": int(scores.get("logic", 0)),
            "tool_call": int(scores.get("tool_call", 0)),
            "param": int(scores.get("param", 0)),
        },
        "compliant": bool(result.get("compliant", False)),
        "violations": list(result.get("violations", [])),
        "comment": str(result.get("comment", ""))[:300],
    }


def _fallback_result(raw: str, reason: str) -> dict:
    return {
        "scores": {"format": 0, "logic": 0, "tool_call": 0, "param": 0},
        "compliant": False,
        "violations": [reason],
        "comment": (raw[:200] if raw else reason),
    }
