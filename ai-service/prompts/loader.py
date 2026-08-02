"""
Prompt 模板加载与渲染器

设计目标：
- 把内联在 agent.py 里的 prompt 字符串外置到 prompts/*.st 文件，便于版本管理与调优
- 轻量渲染：用 str.format，{{ }} 转义为字面量 { }，避免引入新依赖
- 模板内容首次读取后常驻内存缓存，避免每次 IO

模板变量约定：
- intent-classifier.st          : {user_input}
- task-decomposition.st         : {task_description}
- agent-recommend.st            : （无变量，静态系统提示）
- agent-analysis.st             : （无变量）
- admin-analysis.st             : {snapshot_text}
- agent-customer-service.st     : （无变量）
- stream-analysis.st            : {snapshot}
- stream-recommend.st           : {sections}, {action_guidance}
- stream-cs-product.st          : {products_text}, {action_guidance}
- stream-cs-knowledge.st        : {context}, {order_hint}, {action_guidance}
- fallback-customer-service.st  : {user_input}, {context}
- fallback-recommend.st         : {user_input}, {hot_text}
- fallback-analysis.st          : {user_input}, {snapshot}
- conversation-summary.st       : {summary_max_chars}, {content}
- conversation-title.st         : {title_max_chars}, {question}
- recommended-questions.st      : {count}, {chunks}, {question}, {answer}
- answer-citation-rules.st      : （无变量，追加到系统提示）
- user-question-rewrite.st      : {question}, {history}
"""
from __future__ import annotations

from pathlib import Path
from typing import Dict

_TEMPLATE_DIR = Path(__file__).parent
_TEMPLATE_CACHE: Dict[str, str] = {}


def _load_raw(name: str) -> str:
    """读取模板原始文本（带缓存）。文件名自动补 .st 后缀。"""
    if name not in _TEMPLATE_CACHE:
        filename = name if name.endswith(".st") else f"{name}.st"
        path = _TEMPLATE_DIR / filename
        if not path.exists():
            raise FileNotFoundError(f"Prompt 模板不存在: {path}")
        _TEMPLATE_CACHE[name] = path.read_text(encoding="utf-8")
    return _TEMPLATE_CACHE[name]


def render(name: str, **kwargs) -> str:
    """
    渲染模板：用 str.format 替换 {var} 占位符。
    模板中的 {{ }} 会被转义为字面量 { }（用于 JSON 示例等场景）。

    :param name: 模板名（不带 .st 后缀），如 "intent-classifier"
    :param kwargs: 模板变量。不传任何变量时返回原始文本（不调用 format，
                   避免含占位符的模板报 KeyError，便于自测与预览）
    :return: 渲染后的字符串
    """
    raw = _load_raw(name)
    if not kwargs:
        return raw
    return raw.format(**kwargs)


def load_prompt(name: str, **kwargs) -> str:
    """
    加载并渲染 Prompt 模板（对外主入口）。
    若模板无占位符，可不传 kwargs。

    示例：
        load_prompt("intent-classifier", user_input="推荐个耳机")
        load_prompt("agent-recommend")  # 无变量
    """
    return render(name, **kwargs)


def list_templates() -> list:
    """列出所有可用模板名（不含 .st 后缀），便于排查与自测"""
    return sorted(p.stem for p in _TEMPLATE_DIR.glob("*.st"))
