"""会话持久化"""
from __future__ import annotations

import json
import secrets
import threading
from typing import Any, Optional

from langchain_core.messages import HumanMessage
from sqlalchemy import text

from config import settings
from database import SessionLocal


def is_enabled() -> bool:
    return (getattr(settings, "AI_PERSIST_CONVERSATION", "") or "").strip().lower() == "python"


def _llm_text(prompt: str) -> str:
    try:
        from model_router import get_default_router
        result = get_default_router().invoke([HumanMessage(content=prompt)], tier="fast")
        return (result.content or "").strip()
    except Exception as exc:
        print(f"[ConversationStore] LLM 文本生成失败，返回空串: {exc}")
        return ""



def ensure_summary_table() -> None:
    db = SessionLocal()
    try:
        db.execute(text(
            """
            CREATE TABLE IF NOT EXISTS conversation_summary (
                conversation_id BIGINT PRIMARY KEY,
                summary TEXT NOT NULL COMMENT 'LLM 生成的会话摘要',
                updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                    ON UPDATE CURRENT_TIMESTAMP COMMENT '最后更新时间'
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            COMMENT='会话持久化摘要'
            """
        ))
        db.commit()
        print("[ConversationStore] conversation_summary 表已就绪（会话持久化摘要）")
    except Exception as exc:
        db.rollback()
        print(f"[ConversationStore] conversation_summary 建表失败（摘要功能降级）: {exc}")
    finally:
        db.close()


def get_conversation_summary(conversation_id: int) -> Optional[str]:
    db = SessionLocal()
    try:
        row = db.execute(
            text(
                """
                SELECT summary FROM conversation_summary
                WHERE conversation_id = :cid
                """
            ),
            {"cid": conversation_id},
        ).mappings().first()
        return row["summary"] if row and row["summary"] else None
    except Exception as exc:
        print(f"[ConversationStore] get_conversation_summary failed: {exc}")
        return None
    finally:
        db.close()


def save_conversation_summary(conversation_id: int, summary: str) -> bool:
    if not conversation_id or not summary:
        return False
    db = SessionLocal()
    try:
        db.execute(
            text(
                """
                INSERT INTO conversation_summary (conversation_id, summary)
                VALUES (:cid, :summary)
                ON DUPLICATE KEY UPDATE summary = VALUES(summary)
                """
            ),
            {"cid": conversation_id, "summary": summary},
        )
        db.commit()
        return True
    except Exception as exc:
        db.rollback()
        print(f"[ConversationStore] save_conversation_summary failed: {exc}")
        return False
    finally:
        db.close()


def _load_raw_messages(conversation_id: int, limit: int) -> list[dict[str, str]]:
    db = SessionLocal()
    try:
        rows = db.execute(
            text(
                """
                SELECT role, content
                FROM ai_messages
                WHERE conversation_id = :cid AND is_deleted = 0
                ORDER BY id DESC
                LIMIT :limit
                """
            ),
            {"cid": conversation_id, "limit": limit},
        ).mappings().all()
        return [
            {"role": r["role"], "content": r["content"]}
            for r in reversed(rows)
            if r["role"] in ("user", "assistant") and r["content"]
        ]
    except Exception as exc:
        print(f"[ConversationStore] _load_raw_messages failed: {exc}")
        return []
    finally:
        db.close()


def _count_user_turns(conversation_id: int) -> int:
    db = SessionLocal()
    try:
        row = db.execute(
            text(
                """
                SELECT COUNT(*) AS cnt FROM ai_messages
                WHERE conversation_id = :cid AND role = 'user' AND is_deleted = 0
                """
            ),
            {"cid": conversation_id},
        ).mappings().first()
        return int(row["cnt"]) if row else 0
    except Exception as exc:
        print(f"[ConversationStore] _count_user_turns failed: {exc}")
        return 0
    finally:
        db.close()


def _generate_title(user_message: str) -> str:
    try:
        from prompts import load_prompt
        prompt = load_prompt(
            "conversation-title",
            title_max_chars=str(getattr(settings, "TITLE_MAX_CHARS", 30)),
            question=user_message,
        )
        title = _llm_text(prompt)
        return title[:getattr(settings, "TITLE_MAX_CHARS", 30)]
    except Exception as exc:
        print(f"[ConversationStore] _generate_title failed: {exc}")
        return ""


def _generate_summary(conversation_id: int) -> Optional[str]:
    messages = _load_raw_messages(conversation_id, limit=40)
    if not messages:
        return None
    transcript = "\n".join(f"{m['role']}: {m['content']}" for m in messages)
    try:
        from prompts import load_prompt
        prompt = load_prompt(
            "conversation-summary",
            summary_max_chars=str(getattr(settings, "SUMMARY_MAX_CHARS", 400)),
            content=transcript,
        )
        summary = _llm_text(prompt)
        return summary if summary else None
    except Exception as exc:
        print(f"[ConversationStore] _generate_summary failed: {exc}")
        return None


def maybe_summarize(conversation_id: int) -> None:
    if not conversation_id or not is_enabled():
        return
    start_turns = int(getattr(settings, "SUMMARY_START_TURNS", 9) or 9)
    try:
        turns = _count_user_turns(conversation_id)
        if turns < start_turns or turns % start_turns != 0:
            return

        def _worker():
            summary = _generate_summary(conversation_id)
            if summary:
                save_conversation_summary(conversation_id, summary)
                print(f"[ConversationStore] 会话摘要已生成（第 {turns} 轮）: {summary[:60]}...")

        threading.Thread(target=_worker, daemon=True).start()
    except Exception as exc:
        print(f"[ConversationStore] maybe_summarize failed: {exc}")



def ensure_sources_column() -> None:
    db = SessionLocal()
    try:
        db.execute(text(
            "ALTER TABLE ai_messages ADD COLUMN sources JSON DEFAULT NULL COMMENT '引用来源列表JSON'"
        ))
        db.commit()
        print("[ConversationStore] ai_messages.sources 列已添加（引用溯源）")
    except Exception:
        db.rollback()
    finally:
        db.close()


def _truncate(text: str, limit: int = 50) -> str:
    if not text:
        return ""
    text = text.strip()
    return text if len(text) <= limit else text[:limit] + "..."


def save_turn(
    conversation_id: Optional[int],
    user_id: Optional[int],
    user_message: str,
    assistant_reply: str,
    route: Optional[str] = None,
    action: Optional[dict] = None,
    latency_ms: Optional[int] = None,
    token_input: Optional[int] = None,
    token_output: Optional[int] = None,
    sources: Optional[list] = None,
) -> dict:
    db = SessionLocal()
    try:
        if not conversation_id:
            session_key = f"py-{secrets.token_hex(12)}"
            title = _generate_title(user_message) or _truncate(user_message, 50) or "新对话"
            result = db.execute(
                text(
                    """
                    INSERT INTO ai_conversations
                        (user_id, session_key, title, source, route_summary, message_count, last_message_at)
                    VALUES
                        (:uid, :key, :title, 'user', :route, 0, NOW())
                    """
                ),
                {"uid": user_id, "key": session_key, "title": title, "route": route},
            )
            conversation_id = result.lastrowid

        db.execute(
            text(
                """
                INSERT INTO ai_messages (conversation_id, user_id, role, content, route)
                VALUES (:cid, :uid, 'user', :content, :route)
                """
            ),
            {"cid": conversation_id, "uid": user_id, "content": user_message, "route": route},
        )

        action_json = json.dumps(action, ensure_ascii=False) if action else None
        sources_json = json.dumps(sources, ensure_ascii=False) if sources else None
        ins = db.execute(
            text(
                """
                INSERT INTO ai_messages
                    (conversation_id, user_id, role, content, route, action, latency_ms,
                     token_input, token_output, sources)
                VALUES
                    (:cid, :uid, 'assistant', :content, :route, :action, :latency,
                     :token_in, :token_out, :sources)
                """
            ),
            {
                "cid": conversation_id,
                "uid": user_id,
                "content": assistant_reply,
                "route": route,
                "action": action_json,
                "latency": latency_ms,
                "token_in": token_input,
                "token_out": token_output,
                "sources": sources_json,
            },
        )
        assistant_message_id = ins.lastrowid

        db.execute(
            text(
                """
                UPDATE ai_conversations
                SET message_count = message_count + 2,
                    last_message_at = NOW(),
                    route_summary = COALESCE(:route, route_summary)
                WHERE id = :cid
                """
            ),
            {"cid": conversation_id, "route": route},
        )

        db.commit()
        return {"conversation_id": conversation_id, "message_id": assistant_message_id}
    except Exception as exc:
        db.rollback()
        print(f"[ConversationStore] save_turn failed: {exc}")
        return {"conversation_id": conversation_id, "message_id": None}
    finally:
        db.close()


def record_feedback(message_id: int, user_id: Optional[int], rating: int, comment: Optional[str] = None) -> bool:
    """记录用户对某条 AI 消息的反馈（点赞/点踩）。"""
    db = SessionLocal()
    try:
        db.execute(
            text(
                """
                INSERT INTO ai_feedbacks (message_id, user_id, rating, comment)
                VALUES (:mid, :uid, :rating, :comment)
                """
            ),
            {"mid": message_id, "uid": user_id, "rating": rating, "comment": comment},
        )
        db.commit()
        return True
    except Exception as exc:
        db.rollback()
        print(f"[ConversationStore] record_feedback failed: {exc}")
        return False
    finally:
        db.close()


def record_action_log(
    message_id: int,
    user_id: Optional[int],
    action_type: str,
    product_id: int,
    quantity: int = 1,
    execute_status: str = "pending",
    execute_error: Optional[str] = None,
) -> bool:
    """记录 AI 触发的 action（加购/立即购买）日志。"""
    db = SessionLocal()
    try:
        db.execute(
            text(
                """
                INSERT INTO ai_action_logs
                    (message_id, user_id, action_type, product_id, quantity, execute_status, execute_error)
                VALUES
                    (:mid, :uid, :type, :pid, :qty, :status, :err)
                """
            ),
            {
                "mid": message_id,
                "uid": user_id,
                "type": action_type,
                "pid": product_id,
                "qty": quantity,
                "status": execute_status,
                "err": execute_error,
            },
        )
        db.commit()
        return True
    except Exception as exc:
        db.rollback()
        print(f"[ConversationStore] record_action_log failed: {exc}")
        return False
    finally:
        db.close()


def load_recent_messages(conversation_id: int, limit: int = 8) -> list[dict[str, Any]]:
    summary = None
    if limit >= int(getattr(settings, "HISTORY_KEEP_TURNS", 8) or 8):
        summary = get_conversation_summary(conversation_id)
    db = SessionLocal()
    try:
        rows = db.execute(
            text(
                """
                SELECT role, content
                FROM ai_messages
                WHERE conversation_id = :cid AND is_deleted = 0
                ORDER BY id DESC
                LIMIT :limit
                """
            ),
            {"cid": conversation_id, "limit": limit},
        ).mappings().all()
        messages = [
            {"role": r["role"], "content": r["content"]}
            for r in reversed(rows)
            if r["role"] in ("user", "assistant")
        ]
        if summary:
            messages.insert(0, {"role": "system", "content": f"[会话摘要] {summary}"})
        return messages
    except Exception as exc:
        print(f"[ConversationStore] load_recent_messages failed: {exc}")
        return [{"role": "system", "content": f"[会话摘要] {summary}"}] if summary else []
    finally:
        db.close()
