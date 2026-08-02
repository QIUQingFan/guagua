"""
MCP 工具发现层
"""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, get_type_hints

from langchain_core.tools import BaseTool
from langchain_core.messages import HumanMessage
from pydantic import BaseModel

from config import settings
from model_router import get_default_router
from prompts import load_prompt

logger = logging.getLogger("mcp_tools")


@dataclass
class ToolParam:
    """工具参数定义"""
    name: str
    type: str
    description: str = ""
    required: bool = False
    default: Any = None
    enum: Optional[List[str]] = None


@dataclass
class ToolDef:
    """MCP 工具定义"""
    name: str
    description: str
    parameters: List[ToolParam] = field(default_factory=list)

    def to_openai_schema(self) -> dict:
        """转换为 OpenAI function calling Schema。"""
        properties = {}
        required = []
        for p in self.parameters:
            prop: Dict[str, Any] = {"type": p.type, "description": p.description}
            if p.enum:
                prop["enum"] = p.enum
            if p.default is not None:
                prop["default"] = p.default
            properties[p.name] = prop
            if p.required:
                required.append(p.name)
        schema: Dict[str, Any] = {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": {
                    "type": "object",
                    "properties": properties,
                },
            },
        }
        if required:
            schema["function"]["parameters"]["required"] = required
        return schema

    def to_mcp_tool(self) -> dict:
        """转换为 MCP Tool 格式（JSON Schema）。"""
        return {
            "name": self.name,
            "description": self.description,
            "inputSchema": {
                "type": "object",
                "properties": {
                    p.name: {
                        "type": p.type,
                        "description": p.description,
                    }
                    for p in self.parameters
                },
                "required": [p.name for p in self.parameters if p.required],
            },
        }


@dataclass
class ToolExecutor:
    """MCP 工具执行器"""
    tool_id: str
    name: str
    description: str
    fn: Callable
    parameters: List[ToolParam] = field(default_factory=list)

    def to_tool_def(self) -> ToolDef:
        return ToolDef(
            name=self.name,
            description=self.description,
            parameters=self.parameters,
        )

    async def execute(self, params: Dict[str, Any]) -> str:
        """执行工具（异步包装同步函数）。"""
        try:
            if hasattr(self.fn, "arun"):
                result = await self.fn.arun(**params)
            else:
                result = self.fn(**params)
            return str(result) if result is not None else ""
        except Exception as exc:
            logger.error("MCP 工具 %s 执行失败: %s", self.name, exc)
            return f"工具执行错误: {exc}"


class McpToolRegistry:
    """
    MCP 工具注册表

    支持：
    - 注册工具执行器
    - 注销工具
    - 按 ID 获取执行器
    - 列出所有工具定义
    - 列出所有执行器
    - 参数 Schema 校验
    - 参数提取（LLM 从用户输入中提取参数）
    """

    def __init__(self):
        self._executors: Dict[str, ToolExecutor] = {}

    def register(self, executor: ToolExecutor):
        """注册工具执行器。"""
        self._executors[executor.tool_id] = executor
        logger.debug("MCP 工具已注册: %s (%s)", executor.name, executor.tool_id)

    def register_from_langchain(self, tool: BaseTool, tool_id: Optional[str] = None):
        """从 LangChain @tool 注册。"""
        tid = tool_id or tool.name
        params = []
        if hasattr(tool, "args_schema") and tool.args_schema:
            schema = tool.args_schema
            for field_name, field_info in schema.model_fields.items():
                param_type = "string"
                if field_info.annotation:
                    type_map = {
                        str: "string",
                        int: "integer",
                        float: "number",
                        bool: "boolean",
                        list: "array",
                        dict: "object",
                    }
                    param_type = type_map.get(field_info.annotation, "string")
                params.append(ToolParam(
                    name=field_name,
                    type=param_type,
                    description=field_info.description or "",
                    required=field_info.is_required() if hasattr(field_info, "is_required") else True,
                    default=field_info.default if hasattr(field_info, "default") else None,
                ))
        executor = ToolExecutor(
            tool_id=tid,
            name=tool.name,
            description=tool.description or "",
            fn=tool.func if hasattr(tool, "func") else tool._run,
            parameters=params,
        )
        self.register(executor)

    def unregister(self, tool_id: str):
        """注销工具。"""
        self._executors.pop(tool_id, None)
        logger.debug("MCP 工具已注销: %s", tool_id)

    def get_executor(self, tool_id: str) -> Optional[ToolExecutor]:
        """按 ID 获取执行器。"""
        return self._executors.get(tool_id)

    def list_all_tools(self) -> List[ToolDef]:
        """获取所有已注册的工具定义。"""
        return [e.to_tool_def() for e in self._executors.values()]

    def list_all_executors(self) -> List[ToolExecutor]:
        """获取所有已注册的工具执行器。"""
        return list(self._executors.values())

    def contains(self, tool_id: str) -> bool:
        """检查工具是否已注册。"""
        return tool_id in self._executors

    def size(self) -> int:
        """获取已注册工具数量。"""
        return len(self._executors)

    def validate_params(self, tool_id: str, params: Dict[str, Any]) -> List[str]:
        """
        参数 Schema 校验。返回错误信息列表，为空表示校验通过。
        """
        executor = self._executors.get(tool_id)
        if not executor:
            return [f"工具 {tool_id} 未注册"]

        errors = []
        for p in executor.parameters:
            if p.required and p.name not in params:
                errors.append(f"缺少必填参数: {p.name}")
            if p.name in params and params[p.name] is None:
                if p.required:
                    errors.append(f"必填参数不能为空: {p.name}")
        return errors

    def extract_params(
        self, user_input: str, tool_def: ToolDef
    ) -> Dict[str, Any]:
        """
        LLM 参数提取：从用户输入中提取工具参数。
        """
        prompt = load_prompt(
            "mcp-parameter-extract",
            tool_definition=json.dumps(tool_def.to_openai_schema(), ensure_ascii=False, indent=2),
            user_query=user_input,
        )
        try:
            result = get_default_router().invoke(
                [HumanMessage(content=prompt)], tier="fast"
            )
            raw = (result.content or "").strip()
            import re
            match = re.search(r"\{.*\}", raw, re.S)
            if match:
                return json.loads(match.group(0))
            return {}
        except Exception as exc:
            logger.warning("MCP 参数提取失败: %s", exc)
            return {}



_default_registry: Optional[McpToolRegistry] = None


def build_default_registry() -> McpToolRegistry:
    """构建/获取默认 MCP 工具注册表。"""
    global _default_registry
    if _default_registry is not None:
        return _default_registry

    _default_registry = McpToolRegistry()

    try:
        from tools import (
            search_products,
            get_hot_products,
            extract_procurement_intent,
        )
        for tool in [search_products, get_hot_products, extract_procurement_intent]:
            _default_registry.register_from_langchain(tool)
        logger.info(
            "MCP 工具注册表已装配：%d 个工具",
            _default_registry.size(),
        )
    except Exception as exc:
        logger.warning("MCP 工具注册失败: %s", exc)

    return _default_registry


def reset_default_registry():
    """重置默认注册表（用于测试）。"""
    global _default_registry
    _default_registry = None