import request from './request.js'

/**
 * 数据分析看板 - REST 直连接口（不经 LLM，秒级加载）
 *
 *   - GET /ai/dashboard/snapshot   运营快照（订单/营收/趋势/热销/漏斗/对比/预警）
 *   - GET /ai/dashboard/ai-usage   AI 调用量统计（调用量/token/路由/耗时/反馈）
 *   - GET /ai/dashboard/behavior   用户行为分析（漏斗/TopN/趋势/推荐 CTR）
 *
 * 区间参数统一：range ∈ {today,7d,30d,custom}；当 range=custom 时传 start_date & end_date（YYYY-MM-DD，闭区间）。
 *
 * 后端：ai-service/main.py 暴露，express-project/routes/aiProxy.js 代理，
 *      均强制 admin 鉴权（网关注入 X-User-Role=admin）。
 */

/** 构造区间 query 参数（range + 可选 start_date/end_date） */
function buildRangeParams(range = '7d', startDate, endDate) {
  const params = { range }
  if (range === 'custom' && startDate && endDate) {
    params.start_date = startDate
    params.end_date = endDate
  }
  return params
}

/** 运营看板快照（订单/营收/趋势/热销/漏斗/对比/预警） */
export function getDashboardSnapshot(range = '7d', startDate, endDate) {
  return request.get('/ai/dashboard/snapshot', { params: buildRangeParams(range, startDate, endDate) })
}

/** AI 调用量统计（调用量/token/路由/耗时/反馈） */
export function getAiUsage(range = '7d', startDate, endDate) {
  return request.get('/ai/dashboard/ai-usage', { params: buildRangeParams(range, startDate, endDate) })
}

/** 用户行为分析快照（漏斗/TopN/趋势/AI 推荐点击率） */
export function getBehaviorSnapshot(range = '7d', startDate, endDate) {
  return request.get('/ai/dashboard/behavior', { params: buildRangeParams(range, startDate, endDate) })
}
