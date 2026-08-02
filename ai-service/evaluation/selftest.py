from __future__ import annotations

import json
import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, _ROOT)


def test_cases_structure():
    from evaluation.cases import CASES, case_count, get_cases

    assert case_count() == 32, f"案例数应为 32，实际 {case_count()}"
    required_fields = {"case_id", "scenario", "dimension", "user_input", "user_id", "expected"}
    scenarios = set()
    dimensions = set()
    ids = set()
    for c in CASES:
        assert required_fields.issubset(c.keys()), f"案例 {c.get('case_id')} 缺字段"
        assert c["user_input"], f"{c['case_id']} user_input 为空"
        assert c["expected"], f"{c['case_id']} expected 为空"
        assert c["user_id"] is not None, f"{c['case_id']} user_id 为 None"
        scenarios.add(c["scenario"])
        dimensions.add(c["dimension"])
        assert c["case_id"] not in ids, f"case_id 重复: {c['case_id']}"
        ids.add(c["case_id"])

    expected_scenarios = {
        "query_order", "apply_refund", "transfer_human",
        "update_address", "query_product", "knowledge_retrieval",
    }
    expected_dimensions = {
        "normal", "info_missing", "state_constraint", "privilege", "emotion",
    }
    assert scenarios == expected_scenarios, f"场景不全: {scenarios}"
    assert dimensions == expected_dimensions, f"维度不全: {dimensions}"

    refund_cases = get_cases(scenario="apply_refund")
    assert len(refund_cases) == 6, f"apply_refund 应有 6 条，实际 {len(refund_cases)}"
    emotion_cases = get_cases(dimension="emotion")
    assert len(emotion_cases) == 6, f"emotion 应有 6 条，实际 {len(emotion_cases)}"
    print(f"[PASS] 案例集结构: {case_count()} 条 / {len(scenarios)} 场景 / {len(dimensions)} 维度")


def test_judge_pure_functions():
    from evaluation.judge import _extract_json_robust, _normalize_result, _fallback_result

    txt = '```json\n{"scores":{"format":9,"logic":8,"tool_call":10,"param":7},"compliant":true,"violations":[],"comment":"ok"}\n```'
    r = _extract_json_robust(txt)
    assert r is not None and r["compliant"] is True

    r2 = _extract_json_robust('前面有思维链 {"scores":{"format":5,"logic":5,"tool_call":5,"param":5},"compliant":false,"violations":["x"],"comment":"y"}')
    assert r2 is not None and r2["compliant"] is False

    assert _extract_json_robust("纯文本无JSON") is None

    norm = _normalize_result({"scores": {"format": 8}, "compliant": True})
    assert norm["scores"] == {"format": 8, "logic": 0, "tool_call": 0, "param": 0}
    assert norm["compliant"] is True
    assert norm["violations"] == []

    fb = _fallback_result("raw text", "解析失败")
    assert fb["compliant"] is False
    assert fb["scores"] == {"format": 0, "logic": 0, "tool_call": 0, "param": 0}
    assert "解析失败" in fb["violations"]
    print("[PASS] Judge 纯函数: JSON 提取 / 归一化 / fallback")


def test_report_generation_and_persistence():
    from evaluation.runner import generate_report, _save_report, load_latest_report, LATEST_REPORT_PATH

    mock_results = [
        {
            "case_id": "E001", "scenario": "query_order", "dimension": "normal",
            "user_input": "查物流", "expected": "调 query_user_orders",
            "agent_reply": "您的订单已发货", "tool_calls": ["query_user_orders"],
            "validation_violations": 0,
            "scores": {"format": 9, "logic": 9, "tool_call": 10, "param": 9},
            "compliant": True, "judge_violations": [], "comment": "规范",
        },
        {
            "case_id": "E007", "scenario": "apply_refund", "dimension": "info_missing",
            "user_input": "帮我退款", "expected": "索要订单号与理由",
            "agent_reply": "直接调了退款工具", "tool_calls": ["execute_aftersales_action"],
            "validation_violations": 3,
            "scores": {"format": 5, "logic": 4, "tool_call": 3, "param": 2},
            "compliant": False, "judge_violations": ["缺订单号", "缺理由", "未先查后动"],
            "comment": "违规",
        },
    ]
    report = generate_report(mock_results)
    assert report["total"] == 2
    assert report["compliant_count"] == 1
    assert report["compliance_rate"] == 50.0
    assert report["avg_scores"]["format"] == 7.0
    assert report["overall_score"] > 0
    assert report["violation_by_scenario"]["apply_refund"] == 1
    assert report["violation_by_dimension"]["info_missing"] == 1
    assert len(report["cases"]) == 2

    _save_report(report)
    assert os.path.exists(LATEST_REPORT_PATH), "报告未写入磁盘"
    loaded = load_latest_report()
    assert loaded is not None
    assert loaded["total"] == 2
    assert loaded["compliance_rate"] == 50.0
    print(f"[PASS] 报告生成与持久化: rate={report['compliance_rate']}% score={report['overall_score']}")


def test_audit_tool_calls():
    from validation import audit_tool_calls

    trace = [
        {"name": "execute_aftersales_action",
         "args": {"user_id": 1, "order_id": "SO20240001", "action_type": "CANCEL_ORDER_REFUND", "reason": ""},
         "output_preview": ""},
    ]
    audit = audit_tool_calls(trace, injected_user_id=1)
    assert audit["total"] == 1
    assert audit["validatable"] == 1
    assert audit["violations"] >= 2, f"应至少 2 个违规(序列+参数)，实际 {audit['violations']}"
    assert any(d["tool"] == "execute_aftersales_action" for d in audit["details"])

    trace2 = [
        {"name": "query_user_orders", "args": {"user_id": 1}, "output_preview": ""},
        {"name": "execute_aftersales_action",
         "args": {"user_id": 2, "order_id": "SO20240001", "action_type": "CANCEL_ORDER_REFUND", "reason": "商品破损"},
         "output_preview": ""},
    ]
    audit2 = audit_tool_calls(trace2, injected_user_id=1)
    assert audit2["violations"] >= 1, "应检测到 user_id 越权"
    print(f"[PASS] 校验审计: 序列/参数/越权违规均能识别 (case1 violations={audit['violations']}, case2={audit2['violations']})")


def test_fastapi_routes():
    """验证 main.py 注册了评估接口"""
    main_path = os.path.join(_ROOT, "main.py")
    with open(main_path, "r", encoding="utf-8") as f:
        src = f.read()

    assert '"/ai/eval/run"' in src, "缺少 /ai/eval/run 路由"
    assert '"/ai/eval/report"' in src, "缺少 /ai/eval/report 路由"
    assert "eval_run" in src and "eval_report" in src
    assert src.count('user_role != "admin"') >= 2, "评估接口未做 admin 鉴权"
    assert "background_tasks.add_task" in src or "BackgroundTasks" in src
    print("[PASS] FastAPI 路由: /ai/eval/run + /ai/eval/report 已注册（含 admin 鉴权 + 后台任务）")


def test_agent_trace_extraction_signature():
    """验证 agent.py 三个节点均填充 tool_calls_trace"""
    agent_path = os.path.join(_ROOT, "agent.py")
    with open(agent_path, "r", encoding="utf-8") as f:
        src = f.read()

    for node_name in ["customer_service_node", "recommend_node", "analysis_node"]:
        marker = f"def {node_name}("
        idx = src.find(marker)
        assert idx != -1, f"未找到 {node_name}"
        next_def = src.find("\ndef ", idx + 1)
        body = src[idx:next_def] if next_def != -1 else src[idx:]
        assert "extract_tool_calls_from_messages" in body, f"{node_name} 未调用 extract_tool_calls_from_messages"
        assert "tool_calls_trace" in body, f"{node_name} 未设置 tool_calls_trace"
        assert body.count("tool_calls_trace") >= 2, f"{node_name} 正常/异常路径应都处理 trace"
    print("[PASS] agent 节点 trace 填充: customer_service / recommend / analysis 均已接入（正常+异常路径）")


if __name__ == "__main__":
    test_cases_structure()
    test_judge_pure_functions()
    test_report_generation_and_persistence()
    test_audit_tool_calls()
    test_agent_trace_extraction_signature()
    test_fastapi_routes()
    print("\n=== 评估层自测全部通过 ===")
