import request from './request.js'

/**
 * 获取会话列表
 */
export function getChatSessions() {
    return request.get('/chat/sessions')
}

/**
 * 获取私聊历史记录
 * @param {number} userId - 目标用户ID
 * @param {number} page - 页码
 * @param {number} pageSize - 每页数量
 */
export function getPrivateHistory(userId, page = 1, pageSize = 20) {
    return request.get('/chat/private/history', {
        params: { userId, page, pageSize }
    })
}

/**
 * 获取未读消息总数
 */
export function getUnreadChatCount() {
    return request.get('/chat/unread-count')
}

/**
 * 获取当前用户的群列表
 */
export function getChatGroups() {
    return request.get('/chat/groups')
}

/**
 * 创建群聊
 * @param {Object} data - { name, description, memberIds }
 */
export function createChatGroup(data) {
    return request.post('/chat/groups', data)
}

/**
 * 获取群成员列表
 * @param {number} groupId - 群ID
 */
export function getGroupMembers(groupId) {
    return request.get(`/chat/groups/${groupId}/members`)
}

/**
 * 获取群消息历史
 * @param {number} groupId - 群ID
 * @param {number} page - 页码
 * @param {number} pageSize - 每页数量
 */
export function getGroupHistory(groupId, page = 1, pageSize = 20) {
    return request.get(`/chat/groups/${groupId}/messages`, {
        params: { page, pageSize }
    })
}

/**
 * 群消息已读（清零该群未读数）
 * 修复 D6：群聊未读数无法清零
 * @param {number} groupId - 群ID
 */
export function markGroupRead(groupId) {
    return request.post(`/chat/groups/${groupId}/read`)
}

/**
 * 获取用户简要信息（用于陌生人聊天补全昵称头像）
 * @param {number} userId - 用户ID
 */
export function getUserBrief(userId) {
    return request.get(`/chat/user/${userId}/brief`)
}

/**
 * 加入群聊
 * @param {number} groupId - 群ID
 */
export function joinChatGroup(groupId) {
    return request.post(`/chat/groups/${groupId}/join`)
}

/**
 * 退出群聊
 * @param {number} groupId - 群ID
 */
export function leaveChatGroup(groupId) {
    return request.post(`/chat/groups/${groupId}/leave`)
}

/**
 * 邀请用户加入群聊
 * @param {number} groupId - 群ID
 * @param {number} userId - 被邀请用户ID
 */
export function inviteGroupMember(groupId, userId) {
    return request.post(`/chat/groups/${groupId}/invite`, { userId })
}

/**
 * 获取群邀请候选用户（最近聊天对象 + 关注对象）
 * @param {number} groupId - 群ID
 */
export function getGroupInviteCandidates(groupId) {
    return request.get(`/chat/groups/${groupId}/invite-candidates`)
}

/**
 * 移除群成员（仅群主/管理员可用）
 * @param {number} groupId - 群ID
 * @param {number} userId - 被移除用户ID
 */
export function removeGroupMember(groupId, userId) {
    return request.post(`/chat/groups/${groupId}/remove`, { userId })
}

/**
 * 解散群聊（仅群主可用）
 * @param {number} groupId - 群ID
 */
export function dissolveChatGroup(groupId) {
    return request.post(`/chat/groups/${groupId}/dissolve`)
}

/**
 * 更新群聊信息（仅群主可用）
 * @param {number} groupId - 群ID
 * @param {Object} data - { name?, description?, avatar? }
 */
export function updateChatGroupInfo(groupId, data) {
    return request.put(`/chat/groups/${groupId}`, data)
}

/**
 * 更新群公告（仅群主可用）
 * @param {number} groupId - 群ID
 * @param {string} announcement - 公告内容
 */
export function updateGroupAnnouncement(groupId, announcement) {
    return request.put(`/chat/groups/${groupId}/announcement`, { announcement })
}