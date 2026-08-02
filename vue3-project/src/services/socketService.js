import { io } from 'socket.io-client'
import apiConfig from '@/config/api.js'

/**
 * Socket.IO 客户端服务
 * 管理 WebSocket 连接、认证、事件监听和重连
 */
class SocketService {
    constructor() {
        this.socket = null
        this.eventHandlers = new Map()
        this.isConnected = false
        this.isConnecting = false
        this.reconnectAttempts = 0
        this.maxReconnectAttempts = 30
        this.reconnectDelayMax = 30000
        this.manualDisconnect = false
        this.status = 'disconnected'
        this.statusListeners = new Set()
    }

    /**
     * 获取 Socket 服务器 URL
     * 从 API baseURL 解析主机和端口
     */
    getServerUrl() {
        const baseUrl = apiConfig.baseURL || '/api'

        if (baseUrl.startsWith('http')) {
            return baseUrl.replace(/\/api\/?$/, '')
        }

        if (import.meta.env.DEV) {
            return 'http://localhost:3001'
        }

        return `${window.location.protocol}//${window.location.host}`
    }

    /**
     * 获取用户 token
     */
    getToken() {
        return localStorage.getItem('token') || ''
    }

    /**
     * 建立 Socket 连接
     */
    connect() {
        const token = this.getToken()
        if (!token) {
            console.warn('[Socket] 未找到用户 token，跳过连接')
            return
        }

        if (this.isConnecting || this.isConnected) {
            return
        }

        this.isConnecting = true
        this.manualDisconnect = false
        this.setStatus('connecting')

        const serverUrl = this.getServerUrl()

        this.socket = io(serverUrl, {
            auth: { token },
            transports: ['websocket', 'polling'],
            reconnection: true,
            reconnectionAttempts: this.maxReconnectAttempts,
            reconnectionDelay: 1000,
            reconnectionDelayMax: this.reconnectDelayMax,
            timeout: 20000
        })

        this.bindBaseEvents()
        this.bindCustomHandlers()
    }

    /**
     * 绑定基础连接事件
     */
    bindBaseEvents() {
        if (!this.socket) return

        this.socket.on('connect', () => {
            this.isConnected = true
            this.isConnecting = false
            this.reconnectAttempts = 0
            this.setStatus('connected')
            console.log('[Socket] 连接成功，socket id:', this.socket.id)
        })

        this.socket.on('disconnect', (reason) => {
            this.isConnected = false
            this.isConnecting = false
            if (this.manualDisconnect || reason === 'io server disconnect' || reason === 'io client disconnect') {
                this.setStatus('disconnected')
            } else {
                this.setStatus('reconnecting')
            }
            console.log('[Socket] 连接断开，原因:', reason)
        })

        this.socket.on('connect_error', (error) => {
            this.isConnecting = false
            this.reconnectAttempts++
            console.error('[Socket] 连接错误:', error.message)
            if (this.status !== 'failed') {
                this.setStatus('reconnecting')
            }
        })

        this.socket.io.on('reconnect_failed', () => {
            this.setStatus('failed')
            console.error('[Socket] 重连次数已达上限，停止自动重连')
        })

        this.socket.on('connection:established', (data) => {
            console.log('[Socket] 连接认证通过:', data)
        })
    }

    /**
     * 绑定自定义事件处理器
     */
    bindCustomHandlers() {
        if (!this.socket) return

        this.eventHandlers.forEach((handlers, event) => {
            handlers.forEach(handler => {
                this.socket.on(event, handler)
            })
        })
    }

    /**
     * 注册事件监听器
     * @param {string} event - 事件名
     * @param {function} handler - 回调函数
     */
    on(event, handler) {
        if (!this.eventHandlers.has(event)) {
            this.eventHandlers.set(event, new Set())
        }

        this.eventHandlers.get(event).add(handler)

        if (this.socket) {
            this.socket.on(event, handler)
        }
    }

    /**
     * 移除事件监听器
     * @param {string} event - 事件名
     * @param {function} handler - 回调函数
     */
    off(event, handler) {
        const handlers = this.eventHandlers.get(event)
        if (handlers) {
            handlers.delete(handler)
            if (handlers.size === 0) {
                this.eventHandlers.delete(event)
            }
        }

        if (this.socket) {
            this.socket.off(event, handler)
        }
    }

    /**
     * 发送事件
     * @param {string} event - 事件名
     * @param {...any} args - 参数
     */
    emit(event, ...args) {
        if (!this.socket || !this.isConnected) {
            console.warn('[Socket] 未连接，无法发送事件:', event)
            return Promise.reject(new Error('Socket 未连接'))
        }

        return new Promise((resolve, reject) => {
            this.socket.emit(event, ...args, (response) => {
                if (response && response.success === false) {
                    reject(new Error(response.error || '发送失败'))
                } else {
                    resolve(response)
                }
            })
        })
    }

    /**
     * 发送私聊消息
     * @param {number} toUserId - 接收者ID
     * @param {string} content - 消息内容
     * @param {number} type - 消息类型
     */
    sendPrivateMessage(toUserId, content, type = 1) {
        return this.emit('private:message', { toUserId, content, type })
    }

    /**
     * 标记私聊消息已读
     * @param {number} fromUserId - 发送者ID
     */
    markPrivateMessageAsRead(fromUserId) {
        return this.emit('private:read', { fromUserId })
    }

    /**
     * 标记群消息已读（清零该群对当前用户的未读数）
     * 修复 D6：群聊未读数无法清零
     * @param {number} groupId - 群ID
     */
    markGroupMessageAsRead(groupId) {
        return this.emit('group:read', { groupId })
    }

    /**
     * 撤回私聊消息（F1）
     * @param {number} messageId - 消息ID
     */
    recallPrivateMessage(messageId) {
        return this.emit('private:recall', { messageId })
    }

    /**
     * 撤回群消息（F1）
     * @param {number} groupId - 群ID
     * @param {number} messageId - 消息ID
     */
    recallGroupMessage(groupId, messageId) {
        return this.emit('group:recall', { groupId, messageId })
    }

    /**
     * 创建群聊
     * @param {Object} data - { name, description, memberIds }
     */
    createGroup(data) {
        return this.emit('group:create', data)
    }

    /**
     * 发送群消息
     * @param {number} groupId - 群ID
     * @param {string} content - 消息内容
     * @param {number} type - 消息类型
     */
    sendGroupMessage(groupId, content, type = 1) {
        return this.emit('group:message', { groupId, content, type })
    }

    /**
     * 加入群聊
     * @param {number} groupId - 群ID
     */
    joinGroup(groupId) {
        return this.emit('group:join', { groupId })
    }

    /**
     * 退出群聊
     * @param {number} groupId - 群ID
     */
    leaveGroup(groupId) {
        return this.emit('group:leave', { groupId })
    }

    /**
     * 订阅笔记实时评论
     * @param {number} postId - 笔记ID
     */
    subscribePost(postId) {
        return this.emit('post:subscribe', { postId })
    }

    /**
     * 取消订阅笔记实时评论
     * @param {number} postId - 笔记ID
     */
    unsubscribePost(postId) {
        return this.emit('post:unsubscribe', { postId })
    }

    /**
     * 通过 WebSocket 发布评论
     * @param {number} postId - 笔记ID
     * @param {string} content - 评论内容
     * @param {number|null} parentId - 父评论ID
     */
    postComment(postId, content, parentId = null) {
        return this.emit('comment:post', { postId, content, parentId })
    }

    /**
     * 设置连接状态并通知监听器
     * @param {string} status
     */
    setStatus(status) {
        this.status = status
        this.statusListeners.forEach(fn => {
            try { fn(status) } catch (e) { console.error('[Socket] 状态监听器异常:', e) }
        })
    }

    /**
     * 订阅连接状态变更（供 UI 显示重连提示）
     * @param {function} handler - (status) => void
     * @returns {function} 取消订阅函数
     */
    onStatusChange(handler) {
        if (typeof handler === 'function') {
            this.statusListeners.add(handler)
            try { handler(this.status) } catch (e) {  }
        }
        return () => this.statusListeners.delete(handler)
    }

    /**
     * 手动重连（自动重连失败后由 UI 触发）
     */
    manualReconnect() {
        this.reconnectAttempts = 0
        this.reconnect()
    }

    /**
     * 断开连接
     */
    disconnect() {
        this.manualDisconnect = true

        if (this.socket) {
            this.socket.disconnect()
            this.socket = null
        }

        this.isConnected = false
        this.isConnecting = false
        this.reconnectAttempts = 0
        this.setStatus('disconnected')
    }

    /**
     * 重新连接（token 更新后调用）
     */
    reconnect() {
        this.disconnect()
        this.connect()
    }
}

export const socketService = new SocketService()

export default socketService