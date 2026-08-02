import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { socketService } from '@/services/socketService.js'
import {
    getChatSessions,
    getPrivateHistory,
    getUnreadChatCount,
    getChatGroups,
    createChatGroup,
    getGroupHistory,
    joinChatGroup,
    leaveChatGroup,
    getUserBrief
} from '@/api/chat.js'
import { sanitizeText } from '@/utils/contentSecurity.js'
import { setUserCache, setUserCacheBatch } from '@/utils/chatUserResolver.js'

export const useChatStore = defineStore('chat', () => {
    const sessions = ref([])
    const currentTargetId = ref(null)
    const currentSessionType = ref(1)
    const messagesMap = ref(new Map())
    const groups = ref([])
    const unreadCount = ref(0)
    const isLoading = ref(false)
    const isInitialized = ref(false)

    const currentMessages = computed(() => {
        if (!currentTargetId.value) return []
        return messagesMap.value.get(currentTargetId.value) || []
    })

    const currentSession = computed(() => {
        return sessions.value.find(s =>
            Number(s.target_id) === Number(currentTargetId.value) &&
            Number(s.session_type) === Number(currentSessionType.value)
        ) || null
    })

    const currentGroup = computed(() => {
        if (currentSessionType.value !== 2) return null
        return groups.value.find(g => Number(g.id) === Number(currentTargetId.value)) || null
    })

    const sortedSessions = computed(() => {
        return [...sessions.value].sort((a, b) => {
            return new Date(b.updated_at) - new Date(a.updated_at)
        })
    })

    /**
     * 初始化聊天状态（登录后调用）
     */
    async function init() {
        if (isInitialized.value) return

        try {
            isLoading.value = true
            await Promise.all([
                fetchSessions(),
                fetchGroups(),
                fetchUnreadCount()
            ])
            bindSocketEvents()
            isInitialized.value = true
        } finally {
            isLoading.value = false
        }
    }

    /**
     * 重置聊天状态（登出时调用）
     */
    function reset() {
        sessions.value = []
        currentTargetId.value = null
        messagesMap.value = new Map()
        unreadCount.value = 0
        isInitialized.value = false
        unbindSocketEvents()
    }

    /**
     * 获取会话列表
     */
    async function fetchSessions() {
        try {
            const response = await getChatSessions()
            if (response.success) {
                sessions.value = response.data || []
                setUserCacheBatch(sessions.value.map(s => ({
                    id: s.target_id,
                    nickname: s.target_nickname,
                    avatar: s.target_avatar
                })))
                sessions.value.forEach(s => {
                    if (Number(s.session_type) === 1 && (!s.target_nickname || !s.target_avatar)) {
                        ensureUserBrief(Number(s.target_id), s)
                    }
                })
            }
            return response
        } catch (error) {
            console.error('获取会话列表失败:', error)
            return { success: false, data: [] }
        }
    }

    const fetchingUserBrief = new Set()

    /**
     * 异步补全私聊会话的用户昵称/头像
     * 若会话已有 nickname 且 avatar，则跳过；否则从后端查询并补全缺失字段
     * 修复陌生人聊天显示"未知用户"：会话已存在但 nickname 缺失时也能补全
     * @param {number} targetId - 目标用户ID
     * @param {Object} session - 会话对象（引用，会直接修改）
     */
    async function ensureUserBrief(targetId, session) {
        targetId = Number(targetId)
        if (!targetId || !session) return
        if (session.target_nickname && session.target_avatar) return
        if (fetchingUserBrief.has(targetId)) return
        fetchingUserBrief.add(targetId)
        try {
            const res = await getUserBrief(targetId)
            if (res && res.success && res.data) {
                const nickname = res.data.nickname || null
                const avatar = res.data.avatar || null
                const placeholder = `用户${targetId}`
                if (nickname && (!session.target_nickname || session.target_nickname === placeholder)) {
                    session.target_nickname = nickname
                }
                if (avatar && !session.target_avatar) {
                    session.target_avatar = avatar
                }
                setUserCache(targetId, { nickname, avatar })
            }
        } catch (e) {
            console.error('异步补全用户信息失败:', e)
        } finally {
            fetchingUserBrief.delete(targetId)
        }
    }

    /**
     * 确保私聊会话存在（用于陌生人聊天/分享/联系卖家入口）
     * 策略：先用已知信息或占位符同步创建临时会话（UI 立即显示，避免"未知用户"），
     *       若昵称缺失再异步从后端查询并补全
     * @param {number} targetId - 目标用户ID
     * @param {{nickname?:string, avatar?:string}} meta - 已知信息（可选）
     * @returns {Promise<Object|null>} 会话对象
     */
    async function ensurePrivateSession(targetId, meta = null) {
        targetId = Number(targetId)
        if (!targetId) return null

        const existing = sessions.value.find(s =>
            Number(s.target_id) === targetId && Number(s.session_type) === 1
        )
        if (existing) {
            if (meta) {
                if (!existing.target_nickname && meta.nickname) existing.target_nickname = meta.nickname
                if (!existing.target_avatar && meta.avatar) existing.target_avatar = meta.avatar
            }
            if (!existing.target_nickname || !existing.target_avatar) {
                ensureUserBrief(targetId, existing)
            }
            return existing
        }

        const nickname = meta?.nickname || null
        const avatar = meta?.avatar || null

        const dup = sessions.value.find(s =>
            Number(s.target_id) === targetId && Number(s.session_type) === 1
        )
        if (dup) return dup

        const session = {
            id: `temp_${targetId}`,
            user_id: getCurrentUserId(),
            session_type: 1,
            target_id: targetId,
            target_nickname: nickname || `用户${targetId}`,
            target_avatar: avatar || null,
            last_message: '',
            unread_count: 0,
            updated_at: new Date().toISOString()
        }
        sessions.value.unshift(session)

        if (!nickname || !avatar) {
            ensureUserBrief(targetId, session)
        }

        return session
    }

    /**
     * 获取私聊历史记录
     */
    async function fetchPrivateHistory(userId, page = 1, pageSize = 20) {
        try {
            const response = await getPrivateHistory(userId, page, pageSize)
            if (response.success && response.data) {
                const historyMessages = response.data || []
                historyMessages.sort((a, b) => new Date(a.created_at) - new Date(b.created_at))
                setMessages(userId, historyMessages, 1)
                return {
                    success: true,
                    data: historyMessages,
                    pagination: response.pagination
                }
            }
            return response
        } catch (error) {
            console.error('获取私聊历史记录失败:', error)
            return { success: false, data: [] }
        }
    }

    /**
     * 获取群消息历史记录
     */
    async function fetchGroupHistory(groupId, page = 1, pageSize = 20) {
        try {
            const response = await getGroupHistory(groupId, page, pageSize)
            if (response.success && response.data) {
                const historyMessages = response.data || []
                historyMessages.sort((a, b) => new Date(a.created_at) - new Date(b.created_at))
                setMessages(groupId, historyMessages.map(m => ({
                    ...m,
                    group_id: m.group_id || groupId
                })), 2)
                return {
                    success: true,
                    data: historyMessages,
                    pagination: response.pagination
                }
            }
            return response
        } catch (error) {
            console.error('获取群消息历史失败:', error)
            return { success: false, data: [] }
        }
    }

    /**
     * 获取群列表
     */
    async function fetchGroups() {
        try {
            const response = await getChatGroups()
            if (response.success) {
                groups.value = response.data || []
            }
            return response
        } catch (error) {
            console.error('获取群列表失败:', error)
            return { success: false, data: [] }
        }
    }

    /**
     * 创建群聊
     */
    async function createGroup(name, description = '', memberIds = []) {
        try {
            const response = await createChatGroup({ name, description, memberIds })
            if (response.success && response.data) {
                const group = response.data
                groups.value.push(group)
                updateSession(group.id, `群聊"${group.name}"已创建`, 2)
            }
            return response
        } catch (error) {
            console.error('创建群聊失败:', error)
            return { success: false, message: error.message || '创建失败' }
        }
    }

    /**
     * 获取未读消息总数
     */
    async function fetchUnreadCount() {
        try {
            const response = await getUnreadChatCount()
            if (response.success) {
                unreadCount.value = response.data?.total || 0
            }
            return unreadCount.value
        } catch (error) {
            console.error('获取未读数失败:', error)
            unreadCount.value = 0
            return 0
        }
    }

    /**
     * 绑定 Socket 事件
     */
    function bindSocketEvents() {
        socketService.on('private:message', handlePrivateMessage)
        socketService.on('private:read', handlePrivateRead)
        socketService.on('private:recalled', handlePrivateRecalled)
        socketService.on('group:message', handleGroupMessage)
        socketService.on('group:created', handleGroupCreated)
        socketService.on('group:invited', handleGroupInvited)
        socketService.on('session:update', handleSessionUpdate)
        socketService.on('group:recalled', handleGroupRecalled)
    }

    /**
     * 解绑 Socket 事件
     */
    function unbindSocketEvents() {
        socketService.off('private:message', handlePrivateMessage)
        socketService.off('private:read', handlePrivateRead)
        socketService.off('private:recalled', handlePrivateRecalled)
        socketService.off('group:message', handleGroupMessage)
        socketService.off('group:created', handleGroupCreated)
        socketService.off('group:invited', handleGroupInvited)
        socketService.off('session:update', handleSessionUpdate)
        socketService.off('group:recalled', handleGroupRecalled)
    }

    /**
     * 处理收到私聊消息
     */
    function handlePrivateMessage(message) {
        if (!message) return

        const fromUserId = Number(message.from_user_id || message.fromUserId)
        const toUserId = Number(message.to_user_id || message.toUserId)
        const currentUserId = getCurrentUserId()

        const targetId = currentUserId === fromUserId ? toUserId : fromUserId

        appendMessage(targetId, normalizeMessage(message))

        const meta = {}
        if (message.from_nickname) meta.nickname = message.from_nickname
        if (message.from_avatar) meta.avatar = message.from_avatar
        updateSession(targetId, message.content || '', 1, meta)

        if (currentTargetId.value === targetId && currentSessionType.value === 1) {
            markAsRead(targetId)
        } else {
            incrementSessionUnread(targetId, 1)
            unreadCount.value++
        }
    }

    /**
     * 处理收到群消息
     */
    function handleGroupMessage(message) {
        if (!message) return

        const groupId = Number(message.group_id || message.groupId)
        const fromUserId = Number(message.from_user_id || message.fromUserId)
        const currentUserId = getCurrentUserId()

        appendMessage(groupId, normalizeGroupMessage(message))

        const meta = {}
        if (message.from_nickname) meta.nickname = message.from_nickname
        if (message.from_avatar) meta.avatar = message.from_avatar
        updateSession(groupId, message.content || '', 2, meta)

        if (currentTargetId.value === groupId && currentSessionType.value === 2) {
            return
        }

        incrementSessionUnread(groupId, 2)
        unreadCount.value++
    }

    /**
     * 处理被加入新群
     */
    function handleGroupCreated(group) {
        if (!group) return
        const exists = groups.value.find(g => g.id === group.id)
        if (!exists) {
            groups.value.push(group)
        }
        updateSession(group.id, `群聊"${group.name}"已创建`, 2)
    }

    /**
     * 处理被邀请加入群聊
     */
    function handleGroupInvited(data) {
        if (!data) return
        const groupId = Number(data.groupId || data.group_id)
        if (!groupId) return
        updateSession(groupId, '被邀请加入群聊', 2)
        fetchGroups()
    }

    /**
     * 处理对方已读回执
     */
    function handlePrivateRead(data) {
        if (!data) return
        const fromUserId = Number(data.fromUserId || data.from_user_id)
        const messages = messagesMap.value.get(fromUserId) || []
        messages.forEach(msg => {
            if (msg.is_read !== undefined) {
                msg.is_read = 1
            }
            if (msg.isRead !== undefined) {
                msg.isRead = true
            }
        })
    }

    /**
     * 处理会话更新通知
     */
    function handleSessionUpdate(session) {
        if (!session) return
        const targetId = Number(session.target_id ?? session.targetId)
        const sessionType = Number(session.session_type ?? session.sessionType) || 1
        updateSession(targetId, session.last_message || session.lastMessage || '', sessionType)
    }

    /**
     * 处理私聊消息撤回通知（F1）
     */
    function handlePrivateRecalled(payload) {
        if (!payload || !payload.message_id) return
        markMessageRecalled(payload.message_id)
    }

    /**
     * 处理群消息撤回通知（F1）
     */
    function handleGroupRecalled(payload) {
        if (!payload || !payload.message_id) return
        markMessageRecalled(payload.message_id)
    }

    /**
     * 标记消息为已撤回（在内存消息列表中更新，幂等）
     */
    function markMessageRecalled(messageId) {
        for (const [targetId, msgs] of messagesMap.value.entries()) {
            const idx = msgs.findIndex(m => Number(m.id) === Number(messageId))
            if (idx !== -1) {
                const updated = [...msgs]
                updated[idx] = {
                    ...msgs[idx],
                    is_recalled: 1,
                    recall_at: new Date().toISOString(),
                    content: ''
                }
                messagesMap.value.set(targetId, updated)
            }
        }
    }

    /**
     * 发送消息（根据当前会话类型自动判断私聊或群聊）
     */
    async function sendMessage(targetId, content, type = 1) {
        if (currentSessionType.value === 2) {
            return sendGroupMessage(targetId, content, type)
        }
        return sendPrivateMessage(targetId, content, type)
    }

    /**
     * 发送私聊消息
     */
    async function sendPrivateMessage(toUserId, content, type = 1) {
        const cleanContent = sanitizeText(content).trim()
        if (!cleanContent) {
            return { success: false, message: '消息内容不能为空' }
        }

        try {
            const currentUserId = getCurrentUserId()
            const me = getCurrentUserInfo()
            const tempMessage = {
                id: `temp_${Date.now()}`,
                from_user_id: currentUserId,
                to_user_id: toUserId,
                content: cleanContent,
                type,
                is_read: 0,
                created_at: new Date().toISOString(),
                from_nickname: me.nickname || null,
                from_avatar: me.avatar || null,
                sending: true
            }
            appendMessage(toUserId, tempMessage)

            const response = await socketService.sendPrivateMessage(toUserId, cleanContent, type)

            if (response.success && response.data) {
                replaceMessage(toUserId, tempMessage.id, normalizeMessage(response.data))
                updateSession(toUserId, cleanContent, 1)
            }

            return response
        } catch (error) {
            console.error('发送私聊消息失败:', error)
            const messages = messagesMap.value.get(toUserId) || []
            const tempMessage = messages.find(m => m.id && String(m.id).startsWith('temp_'))
            if (tempMessage) {
                tempMessage.failed = true
                tempMessage.sending = false
            }
            return { success: false, message: error.message || '发送失败' }
        }
    }

    /**
     * 发送群消息
     */
    async function sendGroupMessage(groupId, content, type = 1) {
        const cleanContent = sanitizeText(content).trim()
        if (!cleanContent) {
            return { success: false, message: '消息内容不能为空' }
        }

        try {
            const currentUserId = getCurrentUserId()
            const me = getCurrentUserInfo()
            const tempMessage = {
                id: `temp_${Date.now()}`,
                from_user_id: currentUserId,
                group_id: groupId,
                content: cleanContent,
                type,
                created_at: new Date().toISOString(),
                from_nickname: me.nickname || null,
                from_avatar: me.avatar || null,
                sending: true
            }
            appendMessage(groupId, tempMessage)

            const response = await socketService.sendGroupMessage(groupId, cleanContent, type)

            if (response.success && response.data) {
                replaceMessage(groupId, tempMessage.id, normalizeGroupMessage(response.data))
                updateSession(groupId, cleanContent, 2)
            }

            return response
        } catch (error) {
            console.error('发送群消息失败:', error)
            const messages = messagesMap.value.get(groupId) || []
            const tempMessage = messages.find(m => m.id && String(m.id).startsWith('temp_'))
            if (tempMessage) {
                tempMessage.failed = true
                tempMessage.sending = false
            }
            return { success: false, message: error.message || '发送失败' }
        }
    }

    /**
     * 标记消息已读
     */
    async function markAsRead(targetId, sessionType = currentSessionType.value) {
        try {
            if (sessionType === 1) {
                await socketService.markPrivateMessageAsRead(targetId)
            } else if (sessionType === 2) {
                await socketService.markGroupMessageAsRead(targetId)
            }

            const session = sessions.value.find(s => Number(s.target_id) === Number(targetId) && Number(s.session_type) === Number(sessionType))
            if (session) {
                const diff = session.unread_count || 0
                session.unread_count = 0
                unreadCount.value = Math.max(0, unreadCount.value - diff)
            }
            return { success: true }
        } catch (error) {
            console.error('标记已读失败:', error)
            return { success: false, message: error.message }
        }
    }

    /**
     * 撤回消息（F1）
     * @param {number} targetId - 会话目标ID（群聊时为 groupId）
     * @param {number} messageId - 消息ID
     * @param {number} sessionType - 1私聊 2群聊
     */
    async function recallMessage(targetId, messageId, sessionType = currentSessionType.value) {
        try {
            const result = sessionType === 2
                ? await socketService.recallGroupMessage(targetId, messageId)
                : await socketService.recallPrivateMessage(messageId)

            if (result && result.success) {
                markMessageRecalled(messageId)
                return { success: true }
            }
            return { success: false, message: (result && result.error) || '撤回失败' }
        } catch (error) {
            console.error('撤回消息失败:', error)
            return { success: false, message: error.message || '撤回失败' }
        }
    }

    /**
     * 设置当前会话
     */
    function setCurrentSession(targetId, sessionType = 1) {
        currentTargetId.value = targetId ? Number(targetId) : null
        currentSessionType.value = sessionType
        if (targetId) {
            markAsRead(targetId, sessionType)
            if (!messagesMap.value.has(targetId)) {
                if (sessionType === 2) {
                    fetchGroupHistory(targetId)
                } else {
                    fetchPrivateHistory(targetId)
                }
            }
        }
    }

    /**
     * 设置某个会话的完整消息列表
     */
    function setMessages(targetId, messages, sessionType = 1) {
        targetId = Number(targetId)
        const normalizer = sessionType === 2 ? normalizeGroupMessage : normalizeMessage
        messagesMap.value.set(targetId, messages.map(normalizer))
    }

    /**
     * 追加消息到某个会话
     */
    function appendMessage(userId, message) {
        userId = Number(userId)
        if (!messagesMap.value.has(userId)) {
            messagesMap.value.set(userId, [])
        }
        const messages = messagesMap.value.get(userId)
        if (!messages.find(m => m.id === message.id)) {
            messages.push(message)
            messages.sort((a, b) => new Date(a.created_at) - new Date(b.created_at))
        }
    }

    /**
     * 替换临时消息
     */
    function replaceMessage(userId, tempId, realMessage) {
        userId = Number(userId)
        const messages = messagesMap.value.get(userId) || []
        const index = messages.findIndex(m => m.id === tempId)
        if (index !== -1) {
            messages.splice(index, 1, realMessage)
        }
    }

    /**
     * 更新会话最后消息和时间
     */
    function updateSession(targetId, lastMessage, sessionType = 1, meta = null) {
        targetId = Number(targetId)
        const session = sessions.value.find(s => Number(s.target_id) === Number(targetId) && Number(s.session_type) === Number(sessionType))
        const now = new Date().toISOString()

        if (session) {
            session.last_message = lastMessage
            session.updated_at = now
            if (meta) {
                if (!session.target_nickname && meta.nickname) session.target_nickname = meta.nickname
                if (!session.target_avatar && meta.avatar) session.target_avatar = meta.avatar
            }
        } else {
            const isGroup = sessionType === 2
            const group = isGroup ? groups.value.find(g => g.id === targetId) : null
            const fallbackNickname = isGroup
                ? (group?.name || meta?.nickname || `群聊${targetId}`)
                : (meta?.nickname || `用户${targetId}`)
            sessions.value.push({
                id: `temp_${targetId}`,
                user_id: getCurrentUserId(),
                session_type: sessionType,
                target_id: targetId,
                target_nickname: fallbackNickname,
                target_avatar: isGroup ? (group?.avatar || meta?.avatar || null) : (meta?.avatar || null),
                last_message: lastMessage,
                unread_count: 0,
                updated_at: now
            })
        }
    }

    /**
     * 增加某个会话的未读数
     */
    function incrementSessionUnread(targetId, sessionType = 1) {
        targetId = Number(targetId)
        const session = sessions.value.find(s =>
            Number(s.target_id) === Number(targetId) &&
            Number(s.session_type) === Number(sessionType)
        )
        if (session) {
            session.unread_count = (session.unread_count || 0) + 1
        }
    }

    /**
     * 标准化消息格式
     */
    function normalizeMessage(message) {
        const normalized = {
            id: message.id,
            from_user_id: Number(message.from_user_id || message.fromUserId),
            to_user_id: Number(message.to_user_id || message.toUserId),
            content: message.content,
            type: message.type || 1,
            is_read: message.is_read !== undefined ? message.is_read : (message.isRead ? 1 : 0),
            is_recalled: Number(message.is_recalled) === 1 ? 1 : 0,
            recall_at: message.recall_at || null,
            quote_message_id: message.quote_message_id || null,
            extra: message.extra || null,
            created_at: message.created_at || message.createdAt || new Date().toISOString(),
            from_nickname: message.from_nickname,
            from_avatar: message.from_avatar,
            to_nickname: message.to_nickname,
            to_avatar: message.to_avatar
        }
        if (normalized.from_user_id) {
            setUserCache(normalized.from_user_id, { nickname: message.from_nickname, avatar: message.from_avatar })
        }
        if (normalized.to_user_id) {
            setUserCache(normalized.to_user_id, { nickname: message.to_nickname, avatar: message.to_avatar })
        }
        return normalized
    }

    /**
     * 标准化群消息格式
     */
    function normalizeGroupMessage(message) {
        const normalized = {
            id: message.id,
            from_user_id: Number(message.from_user_id || message.fromUserId),
            group_id: Number(message.group_id || message.groupId),
            content: message.content,
            type: message.type || 1,
            is_recalled: Number(message.is_recalled) === 1 ? 1 : 0,
            recall_at: message.recall_at || null,
            quote_message_id: message.quote_message_id || null,
            extra: message.extra || null,
            created_at: message.created_at || message.createdAt || new Date().toISOString(),
            from_nickname: message.from_nickname,
            from_avatar: message.from_avatar
        }
        if (normalized.from_user_id) {
            setUserCache(normalized.from_user_id, { nickname: message.from_nickname, avatar: message.from_avatar })
        }
        return normalized
    }

    /**
     * 获取当前用户信息（用于 tempMessage 注入昵称头像，修复 D8）
     */
    function getCurrentUserInfo() {
        const userInfo = localStorage.getItem('userInfo')
        if (userInfo) {
            try {
                return JSON.parse(userInfo)
            } catch (error) {
                console.error('解析用户信息失败:', error)
            }
        }
        return {}
    }

    /**
     * 获取当前用户ID
     */
    function getCurrentUserId() {
        const userInfo = localStorage.getItem('userInfo')
        if (userInfo) {
            try {
                const user = JSON.parse(userInfo)
                return Number(user.id)
            } catch (error) {
                console.error('解析用户信息失败:', error)
            }
        }
        return 0
    }

    /**
     * 加入群聊
     */
    async function joinGroup(groupId) {
        try {
            const response = await joinChatGroup(groupId)
            if (response.success) {
                await fetchGroups()
                updateSession(groupId, '加入群聊', 2)
            }
            return response
        } catch (error) {
            console.error('加入群聊失败:', error)
            return { success: false, message: error.message || '加入失败' }
        }
    }

    /**
     * 退出群聊
     */
    async function leaveGroup(groupId) {
        try {
            const response = await leaveChatGroup(groupId)
            if (response.success) {
                groups.value = groups.value.filter(g => g.id !== groupId)
                sessions.value = sessions.value.filter(s => !(s.session_type === 2 && s.target_id === groupId))
                if (currentTargetId.value === groupId && currentSessionType.value === 2) {
                    currentTargetId.value = null
                }
            }
            return response
        } catch (error) {
            console.error('退出群聊失败:', error)
            return { success: false, message: error.message || '退出失败' }
        }
    }

    return {
        sessions,
        currentTargetId,
        currentSessionType,
        messagesMap,
        groups,
        unreadCount,
        isLoading,
        isInitialized,
        currentMessages,
        currentSession,
        currentGroup,
        sortedSessions,
        init,
        reset,
        fetchSessions,
        fetchPrivateHistory,
        fetchGroupHistory,
        fetchGroups,
        fetchUnreadCount,
        ensurePrivateSession,
        sendMessage,
        sendPrivateMessage,
        sendGroupMessage,
        createGroup,
        joinGroup,
        leaveGroup,
        markAsRead,
        recallMessage,
        setCurrentSession,
        bindSocketEvents,
        unbindSocketEvents
    }
})