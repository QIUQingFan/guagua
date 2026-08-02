import request from './request.js'

/** 查询 Trace Run 列表（分页，支持 route/status/days 筛选） */
export function fetchTraceRuns(params) {
  return request.get('/ai/admin/trace/runs', { params })
}

/** 查询单个 Trace Run 的完整 Node 明细 */
export function fetchTraceRun(runId) {
  return request.get(`/ai/admin/trace/runs/${runId}`)
}

/** 查询 Trace 统计聚合（总数/平均耗时/错误率/按日趋势/状态分布/路由分布） */
export function fetchTraceStats(params) {
  return request.get('/ai/admin/trace/stats', { params })
}
