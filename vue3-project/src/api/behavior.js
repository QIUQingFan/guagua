import request from './request.js'

/**
 * 用户行为上报（落库 ai_user_behaviors，供行为分析漏斗使用）
 *
 *   POST /ai/behavior  可选登录，游客可用（游客用 session_key 标识）
 *
 * action 类型：
 *   - view            商品详情页浏览
 *   - cart            加入购物车
 *   - purchase        下单成交（可选，后端漏斗已用订单表口径，此处仅作补充埋点）
 *   - recommend_click 点击 AI 推荐位商品
 *   - ai_recommend    AI 推荐位曝光（前端展示推荐商品时上报）
 *
 * 设计要点：
 * - 上报失败静默 catch（不阻断用户业务流程，行为统计是旁路）
 * - 游客用 localStorage 持久化的 session_key，保证同一匿名浏览器行为可关联
 */

const SESSION_KEY_STORAGE = 'ai_behavior_session_key'

/** 获取/生成游客会话标识（登录用户也会带，便于会话级行为分析） */
export function getBehaviorSessionKey() {
  try {
    let key = localStorage.getItem(SESSION_KEY_STORAGE)
    if (!key) {
      key = 'g_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 10)
      localStorage.setItem(SESSION_KEY_STORAGE, key)
    }
    return key
  } catch {
    return 'g_' + Date.now().toString(36)
  }
}

/**
 * 上报行为（fire-and-forget，失败静默）
 * @param {Object} payload { product_id, action, source?, context? }
 */
export function reportBehavior({ product_id, action, source = 'manual', context }) {
  if (!product_id || !action) return Promise.resolve()
  const body = {
    product_id,
    action,
    source,
    session_key: getBehaviorSessionKey(),
  }
  if (context) body.context = context
  return request.post('/ai/behavior', body).catch((e) => {
    
    console.warn('[behavior] 上报失败', action, e?.message || e)
  })
}

/** 浏览商品（ProductDetail 进入时调用） */
export function reportView(productId, source = 'manual') {
  return reportBehavior({ product_id: productId, action: 'view', source })
}

/** 加入购物车（Cart 加入时调用） */
export function reportCart(productId, source = 'manual') {
  return reportBehavior({ product_id: productId, action: 'cart', source })
}

/** AI 推荐位曝光（前端展示 AI 推荐商品列表时调用） */
export function reportAiExposure(productId) {
  return reportBehavior({ product_id: productId, action: 'ai_recommend', source: 'ai' })
}

/** 点击 AI 推荐位商品 */
export function reportRecommendClick(productId) {
  return reportBehavior({ product_id: productId, action: 'recommend_click', source: 'ai' })
}
