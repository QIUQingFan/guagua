"""
评估流水线

报告持久化到 evaluation/reports/latest.json，供 /ai/eval/report 接口读取。
"""
from __future__ import annotations

import json
import os
from datetime import datetime
from typing import List, Optional

from evaluation.cases import CASES, TEST_USER_ID
from evaluation.judge import AgentJudge

REPORT_DIR = os.path.join(os.path.dirname(__file__), "reports")
LATEST_REPORT_PATH = os.path.join(REPORT_DIR, "latest.json")


def run_evaluation(
    user_id: int = TEST_USER_ID,
    case_ids: Optional[List[str]] = None,
    limit: Optional[int] = None,
) -> dict:
    """
    执行评估流水线。

    Args:
        user_id: 评估使用的测试用户 ID（需有订单种子数据）
        case_ids: 仅跑指定 case_id 列表（None 则全量）
        limit: 限制案例数（从前 N 条）

    Returns:
        汇总报告 dict
    """
    from agent import run_agent_with_meta

    judge = AgentJudge()
    cases = CASES
    if case_ids:
        id_set = set(case_ids)
        cases = [c for c in CASES if c["case_id"] in id_set]
    if limit:
        cases = cases[:limit]

    results: list = []
    for i, case in enumerate(cases):
        print(f"[eval {i + 1}/{len(cases)}] {case['case_id']} ({case['scenario']}/{case['dimension']})...", flush=True)

        agent_out = run_agent_with_meta(case["user_input"], [], case["user_id"])
        agent_output = {
            "reply": agent_out.get("reply", ""),
            "route": agent_out.get("route"),
            "action": agent_out.get("action"),
            "tool_calls_trace": agent_out.get("tool_calls_trace", []),
            "validation": agent_out.get("validation"),
        }

        judge_result = judge.judge_case(case["user_input"], agent_output, case["expected"])

        results.append({
            "case_id": case["case_id"],
            "scenario": case["scenario"],
            "dimension": case["dimension"],
            "user_input": case["user_input"],
            "expected": case["expected"],
            "agent_reply": (agent_output["reply"] or "")[:300],
            "tool_calls": [t.get("name", "") for t in agent_output["tool_calls_trace"]],
            "validation_violations": (agent_output["validation"] or {}).get("violations", 0),
            "scores": judge_result.get("scores", {}),
            "compliant": judge_result.get("compliant", False),
            "judge_violations": judge_result.get("violations", []),
            "comment": judge_result.get("comment", ""),
        })

    report = generate_report(results)
    _save_report(report)
    return report


def generate_report(results: list) -> dict:
    """汇总评估结果为报告。"""
    total = len(results)
    compliant_count = sum(1 for r in results if r["compliant"])

    dims = ["format", "logic", "tool_call", "param"]
    avg_scores: dict = {}
    for d in dims:
        scores = [r["scores"].get(d, 0) for r in results if r.get("scores")]
        avg_scores[d] = round(sum(scores) / len(scores), 2) if scores else 0

    violation_by_scenario: dict = {}
    violation_by_dimension: dict = {}
    for r in results:
        if not r["compliant"]:
            violation_by_scenario[r["scenario"]] = violation_by_scenario.get(r["scenario"], 0) + 1
            violation_by_dimension[r["dimension"]] = violation_by_dimension.get(r["dimension"], 0) + 1

    return {
        "report_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "total": total,
        "compliant_count": compliant_count,
        "compliance_rate": round(compliant_count / total * 100, 1) if total else 0,
        "avg_scores": avg_scores,
        "overall_score": round(sum(avg_scores.values()) / len(avg_scores), 2) if avg_scores else 0,
        "violation_by_scenario": violation_by_scenario,
        "violation_by_dimension": violation_by_dimension,
        "cases": results,
    }


def _save_report(report: dict) -> None:
    os.makedirs(REPORT_DIR, exist_ok=True)
    with open(LATEST_REPORT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)


def load_latest_report() -> Optional[dict]:
    if os.path.exists(LATEST_REPORT_PATH):
        try:
            with open(LATEST_REPORT_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return None
    return None
