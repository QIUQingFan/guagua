"""
查询词映射
"""
from __future__ import annotations

import logging
import threading
import time
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import text

logger = logging.getLogger("query.term_mapping")



def _get_engine():
    from database import engine
    return engine


_CACHE_TTL_SECONDS = 300
_cache_lock = threading.Lock()
_cache: Optional[Dict[str, Any]] = None


def _invalidate_cache() -> None:
    """清除内存缓存（CRUD 后调用）。"""
    global _cache
    with _cache_lock:
        _cache = None


def _is_cache_fresh() -> bool:
    if _cache is None:
        return False
    return (time.time() - _cache["loaded_at"]) < _CACHE_TTL_SECONDS


def ensure_query_term_mapping_table() -> None:
    """CREATE TABLE IF NOT EXISTS query_term_mapping。失败不阻断启动（降级为不归一化）。"""
    ddl = """
    CREATE TABLE IF NOT EXISTS query_term_mapping (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        domain VARCHAR(64) NULL COMMENT '业务域（可选，如 product/faq/policy）',
        source_term VARCHAR(128) NOT NULL COMMENT '源词（用户原始短语/简称/同义词）',
        target_term VARCHAR(128) NOT NULL COMMENT '目标词（归一化后的标准词）',
        match_type TINYINT NOT NULL DEFAULT 1 COMMENT '匹配类型 1：子串精确 2：整词（预留）',
        priority INT NOT NULL DEFAULT 100 COMMENT '优先级，数值越大越先匹配（长词建议给高优先级）',
        enabled TINYINT NOT NULL DEFAULT 1 COMMENT '是否启用 1：是 0：否',
        remark VARCHAR(255) NULL COMMENT '备注',
        create_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        update_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_qtm_source (source_term),
        KEY idx_qtm_enabled (enabled)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    COMMENT='查询词映射表（同义词/简称→标准词）'
    """
    try:
        with _get_engine().begin() as conn:
            conn.execute(text(ddl))
        logger.info("query_term_mapping 表已就绪")
    except Exception as exc:
        logger.warning("query_term_mapping 建表失败（查询词映射功能将降级为不归一化）：%s", exc)


def apply_mapping(text: str, source_term: str, target_term: str) -> str:
    """
    安全子串替换：把 text 中所有 source_term 替换为 target_term，
    但若命中位置已经是 target_term 的起始，则跳过（避免重复替换）。

    例：
      apply_mapping("蓝牙耳机降噪", "蓝牙", "蓝牙耳机")
        → "蓝牙" 命中于 index 0，但 text[0:4]=="蓝牙耳机" 已是 target → 跳过
        → 结果 "蓝牙耳机降噪"（不变）
      apply_mapping("买个蓝牙", "蓝牙", "蓝牙耳机")
        → "蓝牙" 命中于 index 2，text[2:6]="买蓝牙"≠"蓝牙耳机" → 替换
        → 结果 "买个蓝牙耳机"
    """
    if not text or not source_term or not target_term:
        return text

    sb: List[str] = []
    idx = 0
    n = len(text)
    src_len = len(source_term)
    tgt_len = len(target_term)

    while idx < n:
        hit = text.find(source_term, idx)
        if hit < 0:
            sb.append(text[idx:n])
            break

        sb.append(text[idx:hit])

        already_target = (hit + tgt_len <= n) and text.startswith(target_term, hit)
        if already_target:
            sb.append(text[hit:hit + tgt_len])
            idx = hit + tgt_len
        else:
            sb.append(target_term)
            idx = hit + src_len

    return "".join(sb)


def _load_mappings_from_db() -> List[Dict[str, Any]]:
    """从 DB 加载启用中的映射规则，按 priority 降序 + source_term 长度降序排列。"""
    sql = text(
        "SELECT id, domain, source_term, target_term, match_type, priority, enabled, remark "
        "FROM query_term_mapping WHERE enabled = 1 AND match_type = 1 "
        "ORDER BY priority DESC, CHAR_LENGTH(source_term) DESC"
    )
    with _get_engine().connect() as conn:
        rows = conn.execute(sql).mappings().all()
    return [dict(r) for r in rows]


def load_mappings() -> List[Dict[str, Any]]:
    """加载映射规则（优先读缓存，过期或无则查 DB 并回填）。失败返回空列表。"""
    global _cache
    if _is_cache_fresh():
        return _cache["mappings"]

    try:
        mappings = _load_mappings_from_db()
    except Exception as exc:
        logger.warning("加载查询词映射失败，本次跳过归一化: %s", exc)
        return []

    with _cache_lock:
        _cache = {"mappings": mappings, "loaded_at": time.time()}
    return mappings


def normalize(text: str) -> str:
    """
    对用户问题做术语归一化：按优先级顺序应用所有启用规则。

    DB 不可用 / 无规则 / 文本为空时原样返回（降级安全）。
    """
    if not text:
        return text
    mappings = load_mappings()
    if not mappings:
        return text

    result = text
    for m in mappings:
        source = m.get("source_term") or ""
        target = m.get("target_term") or ""
        if not source or not target:
            continue
        result = apply_mapping(result, source, target)

    if result != text:
        logger.info("查询词归一化：'%s' → '%s'", text, result)
    return result


def list_mappings(
    keyword: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> Dict[str, Any]:
    """分页查询映射规则（keyword 模糊匹配 source_term/target_term）。返回 {items, total}。"""
    conditions = []
    params: Dict[str, Any] = {"limit": limit, "offset": offset}
    if keyword:
        conditions.append("(source_term LIKE :kw OR target_term LIKE :kw)")
        params["kw"] = f"%{keyword}%"

    where = (" WHERE " + " AND ".join(conditions)) if conditions else ""

    with _get_engine().connect() as conn:
        total_row = conn.execute(
            text(f"SELECT COUNT(*) AS c FROM query_term_mapping{where}"), params
        ).fetchone()
        total = total_row.c if total_row else 0

        rows = conn.execute(
            text(
                f"SELECT id, domain, source_term, target_term, match_type, priority, enabled, remark, "
                f"create_time, update_time "
                f"FROM query_term_mapping{where} "
                f"ORDER BY priority DESC, update_time DESC LIMIT :limit OFFSET :offset"
            ),
            params,
        ).mappings().all()

    items = []
    for r in rows:
        d = dict(r)
        d["create_time"] = d["create_time"].strftime("%Y-%m-%d %H:%M:%S") if d.get("create_time") else None
        d["update_time"] = d["update_time"].strftime("%Y-%m-%d %H:%M:%S") if d.get("update_time") else None
        items.append(d)
    return {"items": items, "total": total}


def get_mapping(mapping_id: int) -> Optional[Dict[str, Any]]:
    """查询单条映射规则。"""
    with _get_engine().connect() as conn:
        row = conn.execute(
            text(
                "SELECT id, domain, source_term, target_term, match_type, priority, enabled, remark, "
                "create_time, update_time FROM query_term_mapping WHERE id = :id"
            ),
            {"id": mapping_id},
        ).mappings().one_or_none()
    if not row:
        return None
    d = dict(row)
    d["create_time"] = d["create_time"].strftime("%Y-%m-%d %H:%M:%S") if d.get("create_time") else None
    d["update_time"] = d["update_time"].strftime("%Y-%m-%d %H:%M:%S") if d.get("update_time") else None
    return d


def create_mapping(
    source_term: str,
    target_term: str,
    domain: Optional[str] = None,
    match_type: int = 1,
    priority: int = 100,
    enabled: bool = True,
    remark: Optional[str] = None,
) -> int:
    """创建映射规则，返回新 id。源词/目标词不能为空。"""
    source_term = (source_term or "").strip()
    target_term = (target_term or "").strip()
    if not source_term:
        raise ValueError("源词不能为空")
    if not target_term:
        raise ValueError("目标词不能为空")

    with _get_engine().begin() as conn:
        result = conn.execute(
            text(
                "INSERT INTO query_term_mapping "
                "(domain, source_term, target_term, match_type, priority, enabled, remark, create_time) "
                "VALUES (:domain, :source, :target, :mt, :priority, :enabled, :remark, :now)"
            ),
            {
                "domain": (domain or "").strip() or None,
                "source": source_term,
                "target": target_term,
                "mt": int(match_type) if match_type in (1, 2) else 1,
                "priority": int(priority),
                "enabled": 1 if enabled else 0,
                "remark": (remark or "").strip() or None,
                "now": datetime.now(),
            },
        )
        new_id = result.lastrowid
    _invalidate_cache()
    logger.info("创建查询词映射 #%d：'%s' → '%s'", new_id, source_term, target_term)
    return int(new_id)


def update_mapping(
    mapping_id: int,
    source_term: Optional[str] = None,
    target_term: Optional[str] = None,
    domain: Optional[str] = None,
    match_type: Optional[int] = None,
    priority: Optional[int] = None,
    enabled: Optional[bool] = None,
    remark: Optional[str] = None,
) -> bool:
    """更新映射规则（仅更新非 None 字段）。返回是否命中。"""
    fields: List[str] = []
    params: Dict[str, Any] = {"id": mapping_id}

    if source_term is not None:
        source_term = source_term.strip()
        if not source_term:
            raise ValueError("源词不能为空")
        fields.append("source_term = :source")
        params["source"] = source_term
    if target_term is not None:
        target_term = target_term.strip()
        if not target_term:
            raise ValueError("目标词不能为空")
        fields.append("target_term = :target")
        params["target"] = target_term
    if domain is not None:
        fields.append("domain = :domain")
        params["domain"] = domain.strip() or None
    if match_type is not None:
        params["mt"] = int(match_type) if match_type in (1, 2) else 1
        fields.append("match_type = :mt")
    if priority is not None:
        params["priority"] = int(priority)
        fields.append("priority = :priority")
    if enabled is not None:
        params["enabled"] = 1 if enabled else 0
        fields.append("enabled = :enabled")
    if remark is not None:
        fields.append("remark = :remark")
        params["remark"] = remark.strip() or None

    if not fields:
        return get_mapping(mapping_id) is not None

    fields.append("update_time = :now")
    params["now"] = datetime.now()

    with _get_engine().begin() as conn:
        result = conn.execute(
            text(f"UPDATE query_term_mapping SET {', '.join(fields)} WHERE id = :id"),
            params,
        )
        affected = result.rowcount
    if affected:
        _invalidate_cache()
        logger.info("更新查询词映射 #%d", mapping_id)
    return bool(affected)


def delete_mapping(mapping_id: int) -> bool:
    """删除映射规则。返回是否命中。"""
    with _get_engine().begin() as conn:
        result = conn.execute(
            text("DELETE FROM query_term_mapping WHERE id = :id"), {"id": mapping_id}
        )
        affected = result.rowcount
    if affected:
        _invalidate_cache()
        logger.info("删除查询词映射 #%d", mapping_id)
    return bool(affected)
