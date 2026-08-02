"""
查询预处理模块（问题重写 + 查询词映射）
"""
from query.rewrite import prepare_retrieval_query, rewrite_query
from query.term_mapping import (
    apply_mapping,
    create_mapping,
    delete_mapping,
    ensure_query_term_mapping_table,
    get_mapping,
    list_mappings,
    normalize,
    update_mapping,
)

__all__ = [
    "prepare_retrieval_query",
    "rewrite_query",
    "apply_mapping",
    "normalize",
    "ensure_query_term_mapping_table",
    "list_mappings",
    "get_mapping",
    "create_mapping",
    "update_mapping",
    "delete_mapping",
]
