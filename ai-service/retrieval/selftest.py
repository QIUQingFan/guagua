"""
多路检索 + RRF 融合 自测脚本（静态结构验证，不依赖运行中的 DB / ChromaDB）

运行：python -m retrieval.selftest
"""
from __future__ import annotations

from retrieval.channel import (
    RetrievedChunk,
    SearchChannelResult,
    SearchChannelType,
)
from retrieval.fusion import dedup_chunks, fuse_by_rrf, truncate_for_rerank
from retrieval.engine import RetrievalBudget


def _chunk(content: str, cid: str = None, source_type: str = "product") -> RetrievedChunk:
    return RetrievedChunk(content=content, id=cid, source_type=source_type)


def test_dedup_by_id():
    """同 id 的 chunk 只保留首个"""
    chunks = [
        _chunk("A", cid="product:1"),
        _chunk("A-dup", cid="product:1"),
        _chunk("B", cid="product:2"),
    ]
    unique = dedup_chunks(chunks)
    assert len(unique) == 2, f"去重后应为 2，实际 {len(unique)}"
    assert unique[0].content == "A"
    print("[PASS] 去重：同 id chunk 只保留首个")


def test_dedup_by_content_hash():
    """无 id 时按内容 SHA-256 去重"""
    chunks = [
        _chunk("same content"),
        _chunk("same content"),
        _chunk("different"),
    ]
    unique = dedup_chunks(chunks)
    assert len(unique) == 2, f"去重后应为 2，实际 {len(unique)}"
    print("[PASS] 去重：无 id 时按内容哈希去重")


def test_rrf_multi_hit_ranks_higher():
    """多路命中的 chunk RRF 分数应高于单路命中"""
    vector = SearchChannelResult(
        channel_type=SearchChannelType.VECTOR,
        chunks=[_chunk("A", cid="p:1"), _chunk("B", cid="p:2"), _chunk("C", cid="p:3")],
    )
    keyword = SearchChannelResult(
        channel_type=SearchChannelType.KEYWORD,
        chunks=[_chunk("B", cid="p:2"), _chunk("A", cid="p:1"), _chunk("D", cid="p:4")],
    )
    deduped = dedup_chunks(vector.chunks + keyword.chunks)
    fused = fuse_by_rrf([vector, keyword], deduped, k=20, weights={"vector": 1.0, "keyword": 1.0})

    top_ids = [c.id for c in fused[:2]]
    assert "p:1" in top_ids and "p:2" in top_ids, f"多路命中应排前二，实际 {top_ids}"
    assert fused[0].score > fused[2].score, "多路命中分数应高于单路命中"
    print(f"[PASS] RRF：多路命中排前二 ({top_ids})，分数 {fused[0].score:.4f} > 单路 {fused[2].score:.4f}")


def test_rrf_weight_affects_order():
    """低权重通道的命中贡献降低，影响排序"""
    vector = SearchChannelResult(
        channel_type=SearchChannelType.VECTOR,
        chunks=[_chunk("A", cid="p:1")],
    )
    hot = SearchChannelResult(
        channel_type=SearchChannelType.HOT,
        chunks=[_chunk("B", cid="p:2")],
    )
    deduped = dedup_chunks(vector.chunks + hot.chunks)
    fused = fuse_by_rrf([vector, hot], deduped, k=20, weights={"vector": 1.0, "hot": 0.5})

    assert fused[0].id == "p:1", f"高权重通道应排第一，实际 {fused[0].id}"
    assert fused[0].score > fused[1].score, "高权重通道分数应更高"
    print(f"[PASS] RRF 加权：向量(1.0) 分数 {fused[0].score:.4f} > 热销(0.5) {fused[1].score:.4f}")


def test_truncate():
    """截断候选池：limit>0 时只保留前 N"""
    chunks = [_chunk(f"c{i}", cid=f"p:{i}") for i in range(50)]
    truncated = truncate_for_rerank(chunks, limit=40)
    assert len(truncated) == 40, f"截断后应为 40，实际 {len(truncated)}"
    assert len(truncate_for_rerank(chunks, limit=0)) == 50
    print("[PASS] 截断：limit=40 时保留 40 条，limit<=0 不截断")


def test_budget_invariants():
    """漏斗不变式：recall ≥ topk 且 rerank ≥ topk，违反时抛错"""
    RetrievalBudget(recall_budget=20, rerank_candidate_limit=40, default_top_k=10)
    print("[PASS] 漏斗校验：合法配置通过")

    try:
        RetrievalBudget(recall_budget=5, rerank_candidate_limit=40, default_top_k=10)
        raise AssertionError("应抛 ValueError")
    except ValueError:
        print("[PASS] 漏斗校验：recall_budget(5) < top_k(10) 正确拒绝")

    try:
        RetrievalBudget(recall_budget=20, rerank_candidate_limit=5, default_top_k=10)
        raise AssertionError("应抛 ValueError")
    except ValueError:
        print("[PASS] 漏斗校验：rerank_candidate_limit(5) < top_k(10) 正确拒绝")


def test_rrf_formula_manual():
    """手工验算 RRF 公式：score = Σ weight/(k+rank)，rank 从 1 开始"""
    vector = SearchChannelResult(
        channel_type=SearchChannelType.VECTOR,
        chunks=[_chunk("A", cid="p:1")],
    )
    keyword = SearchChannelResult(
        channel_type=SearchChannelType.KEYWORD,
        chunks=[_chunk("A", cid="p:1")],
    )
    deduped = dedup_chunks(vector.chunks + keyword.chunks)
    fused = fuse_by_rrf([vector, keyword], deduped, k=20, weights={"vector": 1.0, "keyword": 1.0})

    expected = 2 / 21
    assert abs(fused[0].score - expected) < 1e-9, f"RRF 分数应为 {expected:.6f}，实际 {fused[0].score:.6f}"
    print(f"[PASS] RRF 公式验算：2/(20+1) = {expected:.6f} 与实际 {fused[0].score:.6f} 一致")


def main():
    print("=" * 60)
    print("多路检索 + RRF 融合 自测")
    print("=" * 60)
    test_dedup_by_id()
    test_dedup_by_content_hash()
    test_rrf_multi_hit_ranks_higher()
    test_rrf_weight_affects_order()
    test_truncate()
    test_budget_invariants()
    test_rrf_formula_manual()
    print("=" * 60)
    print("全部通过 ✅")
    print("=" * 60)


if __name__ == "__main__":
    main()
