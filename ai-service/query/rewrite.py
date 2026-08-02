"""
问题重写（LLM 改写）

## 解决什么问题
多轮对话中用户常带省略、指代、礼貌语，直接拿原句检索会漏召回：
- "怎么申请" → 缺主语，检索不到"退货退款申请流程"
- "它多少钱" → "它"指代不清，向量检索不知所云
- "请帮我详细介绍一下降噪耳机" → 礼貌语+回答指令干扰语义匹配

检索前用 LLM 把问题改写成"适合检索的自然语言查询"：
- 删礼貌语/回答指令/无关描述
- 结合历史消解指代（"它"→具体商品名）
- 补全省略主语（"怎么申请"→"怎么申请退货"）

## 流程
1. 术语归一化（query.term_mapping.normalize）：先把"耳机"→"蓝牙耳机"等简称归一
2. LLM 改写（user-question-rewrite.st，fast 档）：去噪 + 指代消解 + 补全
3. 解析 JSON {rewrite, should_split, sub_questions}，取 rewrite 作为检索查询
4. 任何失败（LLM 异常/解析失败）回退到归一化后的原句（降级安全）

## 与查询词映射的顺序
先归一化再改写：归一化把术语对齐到知识库标准用语，LLM 在标准用语基础上做语义改写，
避免 LLM 改写后再被术语替换破坏语义（如 LLM 把"耳机"改写进"蓝牙耳机"后又被二次替换）。

## 拆分能力
prompt 支持输出 sub_questions（多问句拆分）。当前检索引擎 search() 接受单查询，
故使用 rewrite 字段（拆分场景下 prompt 会合并为一句，如"订单流程和支付环节"）。
多查询并行检索留作后续扩展（需检索引擎支持多查询融合）。
"""
from __future__ import annotations

import json
import logging
import re
from typing import Any, List, Optional

from langchain_core.messages import HumanMessage

from prompts import load_prompt
from query.term_mapping import normalize

logger = logging.getLogger("query.rewrite")


def _rewrite_enabled() -> bool:
    """读取 LLM 重写开关（QUERY_REWRITE_ENABLED）。"""
    from config import settings
    return str(getattr(settings, "QUERY_REWRITE_ENABLED", "true")).lower() in (
        "true", "1", "yes", "on",
    )


def _rewrite_tier() -> str:
    """重写用的 LLM 档位（默认 fast，省成本——重写是简单任务）。"""
    from config import settings
    return str(getattr(settings, "QUERY_REWRITE_TIER", "fast")) or "fast"


def _format_history_for_rewrite(history: Optional[List[dict]]) -> str:
    """
    把历史消息格式化为 prompt 所需的文本

    只保留最近 2 轮
    无历史或历史为空时返回 "（无）"。
    """
    if not history:
        return "（无）"
    turns = [
        item for item in history
        if item.get("role") in ("user", "assistant") and item.get("content")
    ][-4:]
    if not turns:
        return "（无）"
    lines = []
    for item in turns:
        role = item.get("role", "assistant")
        content = item.get("content", "").strip()
        if content:
            lines.append(f"{role}: {content}")
    return "\n".join(lines) if lines else "（无）"


def _parse_rewrite_response(raw: str, fallback: str) -> str:
    """
    解析 LLM 返回的 JSON {rewrite, should_split, sub_questions}。

    - 容错：去 markdown 代码块标记 → 提取首个 JSON 对象 → 取 rewrite 字段
    - 解析失败或 rewrite 为空 → 返回 fallback
    """
    if not raw:
        return fallback
    cleaned = raw.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned)
        cleaned = re.sub(r"\s*```$", "", cleaned)

    try:
        obj = json.loads(cleaned)
    except Exception:
        match = re.search(r"\{.*\}", cleaned, re.S)
        if not match:
            return fallback
        try:
            obj = json.loads(match.group(0))
        except Exception:
            return fallback

    rewrite = (obj.get("rewrite") or "").strip() if isinstance(obj, dict) else ""
    if not rewrite:
        return fallback
    return rewrite


def rewrite_query(question: str, history: Optional[List[dict]] = None) -> str:
    """
    问题重写主入口：术语归一化 + LLM 改写。

    流程：
      question → normalize(术语归一化) → LLM 改写 → 返回检索用查询

    降级链：
      - QUERY_REWRITE_ENABLED=false → 只做术语归一化，跳过 LLM
      - LLM 调用失败/解析失败 → 返回归一化后的原句
      - 术语归一化失败 → 返回原句

    :param question: 用户原始问题
    :param history:  对话历史（最近轮次，用于指代消解），可为 None
    :return: 适合检索的查询字符串
    """
    if not question or not question.strip():
        return question

    try:
        normalized = normalize(question)
    except Exception as exc:
        logger.warning("术语归一化失败，使用原句: %s", exc)
        normalized = question

    if not _rewrite_enabled():
        return normalized

    history_text = _format_history_for_rewrite(history)
    prompt = load_prompt("user-question-rewrite", question=normalized, history=history_text)

    try:
        from model_router import get_default_router
        result = get_default_router().invoke(
            [HumanMessage(content=prompt)], tier=_rewrite_tier()
        )
        raw = getattr(result, "content", "") or ""
    except Exception as exc:
        logger.warning("问题重写 LLM 调用失败，使用归一化结果兜底: %s", exc)
        return normalized

    rewritten = _parse_rewrite_response(raw, fallback=normalized)
    if rewritten != normalized:
        logger.info("问题重写：'%s' → '%s'", question, rewritten)
    return rewritten


def prepare_retrieval_query(question: str, history: Optional[List[dict]] = None) -> str:
    """
    检索前预处理：术语归一化 + LLM 改写。

    供 rag_retrieve_node / stream_agent 在调用检索引擎前使用。
    是 rewrite_query 的语义别名（明确"为检索准备查询"的意图）。
    """
    return rewrite_query(question, history)
