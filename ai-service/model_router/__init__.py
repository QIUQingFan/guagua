"""
model_router 包：模型路由 + 三态熔断 + 首包探测

核心入口：model_router.build_default_router() -> RoutingLLMService
- router.invoke(messages)   替代 llm.invoke（带候选 failover）
- router.stream(messages)   替代 streaming_llm.stream（带首包探测 + failover）

设计要点：
- 三态熔断器（CLOSED/OPEN/HALF_OPEN）隔离故障模型，避免反复打无效请求消耗配额
- 首包探测：流式下首个 token 未在 timeout 内到达即判定候选故障，比等整段超时快 5~10 倍
- 候选按 priority 排序，按 tier 过滤；OPEN 候选直接跳过
- 与现有 ChatOpenAI 实例共享主候选，保证 ReAct Agent 与路由健康状态一致
"""
from model_router.router import (
    ModelCandidate,
    RoutingLLMService,
    build_default_router,
    get_default_router,
)

__all__ = [
    "ModelCandidate",
    "RoutingLLMService",
    "build_default_router",
    "get_default_router",
]
