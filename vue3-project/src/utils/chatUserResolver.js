/**
 * 聊天用户昵称/头像统一解析器
 * 修复 D3：统一 SessionList / ChatWindow / MessageBubble 三处名称回退策略，
 * 并提供内存缓存，在后端字段缺失时兜底。
 */

const userCache = new Map()

/**
 * 写入单个用户信息缓存
 * @param {number} userId
 * @param {{nickname?:string, avatar?:string}} info
 */
export function setUserCache(userId, info) {
    if (!userId) return
    const existing = userCache.get(Number(userId)) || {}
    userCache.set(Number(userId), {
        nickname: info?.nickname || existing.nickname || null,
        avatar: info?.avatar || existing.avatar || null
    })
}

/**
 * 批量写入用户信息缓存
 * @param {Array} list - 元素含 id/user_id/from_user_id + nickname/avatar
 */
export function setUserCacheBatch(list) {
    if (!Array.isArray(list)) return
    list.forEach(item => {
        if (!item) return
        const uid = item.id || item.user_id || item.from_user_id || item.target_id
        if (uid) {
            setUserCache(uid, { nickname: item.nickname, avatar: item.avatar })
        }
    })
}

/**
 * 从缓存读取
 * @param {number} userId
 * @returns {{nickname:string|null, avatar:string|null}|null}
 */
export function getUserCache(userId) {
    return userCache.get(Number(userId)) || null
}

/**
 * 判断昵称是否为占位符 `用户${targetId}`
 */
const isPlaceholderNickname = (nickname, targetId) => {
    if (!nickname || !targetId) return false
    return nickname === `用户${targetId}`
}

/**
 * 解析会话目标昵称（统一回退文案：未知用户 / 群聊X / 用户X）
 * 修复陌生人聊天显示"未知用户"：占位符视为缺失，优先用缓存中的真实昵称兜底
 * @param {Object} session - 会话对象
 * @returns {string}
 */
export function resolveSessionName(session) {
    if (!session) return '未知用户'
    if (Number(session.session_type) === 2) {
        return session.target_nickname || `群聊${session.target_id}`
    }
    const hasRealNickname = session.target_nickname && !isPlaceholderNickname(session.target_nickname, session.target_id)
    if (hasRealNickname) return session.target_nickname
    
    const cached = getUserCache(session.target_id)
    if (cached?.nickname) return cached.nickname
    
    return session.target_nickname || '未知用户'
}

/**
 * 解析会话目标头像
 * @param {Object} session
 * @param {string} fallback
 * @returns {string}
 */
export function resolveSessionAvatar(session, fallback = '') {
    if (!session) return fallback
    if (session.target_avatar) return session.target_avatar
    const cached = getUserCache(session.target_id)
    return cached?.avatar || fallback
}

/**
 * 解析消息发送者昵称（统一回退文案：未知用户）
 * @param {Object} message
 * @returns {string}
 */
export function resolveSenderName(message) {
    if (!message) return '未知用户'
    if (message.from_nickname) return message.from_nickname
    const cached = getUserCache(message.from_user_id)
    if (cached?.nickname) return cached.nickname
    return '未知用户'
}

/**
 * 解析消息发送者头像
 * @param {Object} message
 * @param {string} fallback
 * @returns {string}
 */
export function resolveSenderAvatar(message, fallback = '') {
    if (!message) return fallback
    if (message.from_avatar) return message.from_avatar
    const cached = getUserCache(message.from_user_id)
    return cached?.avatar || fallback
}

export default {
    setUserCache,
    setUserCacheBatch,
    getUserCache,
    resolveSessionName,
    resolveSessionAvatar,
    resolveSenderName,
    resolveSenderAvatar
}
