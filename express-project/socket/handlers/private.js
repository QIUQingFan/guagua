const { pool } = require('../../config/config');
const connectionManager = require('../manager/connectionManager');
const { logInfo, logError } = require('../utils/logger');

const MAX_MESSAGE_LENGTH = 2000;

/**
 * 保存或更新会话列表
 */
const upsertSession = async (userId, targetId, sessionType, lastMessage, incrementUnread = false) => {
    try {
        const [rows] = await pool.execute(
            'SELECT id, unread_count FROM chat_sessions WHERE user_id = ? AND session_type = ? AND target_id = ?',
            [userId, sessionType, targetId]
        );

        const existing = rows && rows.length > 0 ? rows[0] : null;

        if (existing) {
            const newUnread = incrementUnread ? existing.unread_count + 1 : existing.unread_count;
            await pool.execute(
                'UPDATE chat_sessions SET last_message = ?, unread_count = ?, updated_at = NOW() WHERE id = ?',
                [lastMessage, newUnread, existing.id]
            );
        } else {
            const unreadCount = incrementUnread ? 1 : 0;
            await pool.execute(
                'INSERT INTO chat_sessions (user_id, session_type, target_id, last_message, unread_count) VALUES (?, ?, ?, ?, ?)',
                [userId, sessionType, targetId, lastMessage, unreadCount]
            );
        }
    } catch (error) {
        logError('privateHandler', '更新会话列表失败', error, { userId, targetId });
        throw error;
    }
};

/**
 * 发送私聊消息
 */
const sendMessage = async (socket, data, callback) => {
    try {
        const fromUserId = socket.userId;
        const { toUserId, content, type = 1, share_id, share_title, share_cover } = data;

        if (!toUserId) {
            return safeCallback(callback, { success: false, error: '缺少接收者ID' });
        }
        if (!content || typeof content !== 'string') {
            return safeCallback(callback, { success: false, error: '消息内容不能为空' });
        }
        if (content.length > MAX_MESSAGE_LENGTH) {
            return safeCallback(callback, { success: false, error: '消息长度超过限制' });
        }
        if (parseInt(fromUserId) === parseInt(toUserId)) {
            return safeCallback(callback, { success: false, error: '不能给自己发送消息' });
        }

        const [result] = await pool.execute(
            'INSERT INTO private_messages (from_user_id, to_user_id, content, type, share_id, share_title, share_cover) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [fromUserId, toUserId, content, type, share_id || null, share_title || null, share_cover || null]
        );

        const [users] = await pool.execute(
            'SELECT id, nickname, avatar FROM users WHERE id IN (?, ?)',
            [fromUserId, toUserId]
        );
        const fromUser = users.find(u => Number(u.id) === Number(fromUserId)) || {};
        const toUser = users.find(u => Number(u.id) === Number(toUserId)) || {};

        const message = {
            id: result.insertId,
            from_user_id: parseInt(fromUserId),
            to_user_id: parseInt(toUserId),
            content,
            type,
            share_id: share_id || null,
            share_title: share_title || null,
            share_cover: share_cover || null,
            is_read: 0,
            created_at: new Date().toISOString(),
            from_nickname: fromUser.nickname || null,
            from_avatar: fromUser.avatar || null,
            to_nickname: toUser.nickname || null,
            to_avatar: toUser.avatar || null
        };

        await upsertSession(fromUserId, toUserId, 1, content, false);

        await upsertSession(toUserId, fromUserId, 1, content, true);

        socket.to(`user:${toUserId}`).emit('private:message', message);

        socket.to(`user:${toUserId}`).emit('session:update', {
            session_type: 1,
            target_id: parseInt(fromUserId),
            last_message: content,
            updated_at: new Date().toISOString()
        });

        logInfo('privateHandler', '私聊消息已发送', {
            messageId: message.id,
            from: fromUserId,
            to: toUserId
        });

        safeCallback(callback, { success: true, data: message });
    } catch (error) {
        logError('privateHandler', '发送私聊消息失败', error, { socketId: socket.id });
        safeCallback(callback, { success: false, error: '发送失败' });
    }
};

/**
 * 标记消息已读
 */
const markAsRead = async (socket, data, callback) => {
    try {
        const toUserId = socket.userId;
        const { fromUserId } = data;

        if (!fromUserId) {
            return safeCallback(callback, { success: false, error: '缺少发送者ID' });
        }

        await pool.execute(
            'UPDATE private_messages SET is_read = 1 WHERE from_user_id = ? AND to_user_id = ? AND is_read = 0',
            [fromUserId, toUserId]
        );

        await pool.execute(
            'UPDATE chat_sessions SET unread_count = 0 WHERE user_id = ? AND session_type = 1 AND target_id = ?',
            [toUserId, fromUserId]
        );

        socket.to(`user:${fromUserId}`).emit('private:read', {
            fromUserId: toUserId,
            toUserId: fromUserId
        });

        safeCallback(callback, { success: true });
    } catch (error) {
        logError('privateHandler', '标记已读失败', error, { socketId: socket.id });
        safeCallback(callback, { success: false, error: '操作失败' });
    }
};

/**
 * 安全调用回调函数
 */
const safeCallback = (callback, data) => {
    if (typeof callback === 'function') {
        callback(data);
    }
};

module.exports = {
    sendMessage,
    markAsRead
};