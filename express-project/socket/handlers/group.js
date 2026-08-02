const { pool } = require('../../config/config');
const connectionManager = require('../manager/connectionManager');
const { logInfo, logError } = require('../utils/logger');

const MAX_MESSAGE_LENGTH = 2000;
const MAX_GROUP_NAME_LENGTH = 100;

/**
 * 安全调用回调函数
 */
const safeCallback = (callback, data) => {
    if (typeof callback === 'function') {
        callback(data);
    }
};

/**
 * 更新群会话最后消息
 */
const updateGroupSession = async (groupId, lastMessage) => {
    try {
        await pool.execute(
            'UPDATE chat_sessions SET last_message = ?, updated_at = NOW() WHERE session_type = 2 AND target_id = ?',
            [lastMessage, groupId]
        );
    } catch (error) {
        logError('groupHandler', '更新群会话失败', error, { groupId });
    }
};

/**
 * 增加群成员未读数
 */
const incrementGroupUnread = async (groupId, excludeUserId) => {
    try {
        await pool.execute(
            'UPDATE chat_sessions SET unread_count = unread_count + 1 WHERE session_type = 2 AND target_id = ? AND user_id != ?',
            [groupId, excludeUserId]
        );
    } catch (error) {
        logError('groupHandler', '增加群未读数失败', error, { groupId });
    }
};

/**
 * 创建群聊
 */
const createGroup = async (socket, data, callback) => {
    try {
        const ownerId = socket.userId;
        const { name, description = '', memberIds = [] } = data;

        if (!name || typeof name !== 'string') {
            return safeCallback(callback, { success: false, error: '群名称不能为空' });
        }
        if (name.length > MAX_GROUP_NAME_LENGTH) {
            return safeCallback(callback, { success: false, error: '群名称过长' });
        }

        const uniqueMemberIds = [...new Set([...memberIds.map(Number), ownerId])];
        if (uniqueMemberIds.length < 2) {
            return safeCallback(callback, { success: false, error: '群聊至少需要两名成员' });
        }

        const connection = await pool.getConnection();
        let groupId;
        try {
            await connection.beginTransaction();

            const [groupResult] = await connection.execute(
                'INSERT INTO chat_groups (name, owner_id, description, member_count) VALUES (?, ?, ?, ?)',
                [name, ownerId, description, uniqueMemberIds.length]
            );
            groupId = groupResult.insertId;

            const memberValues = uniqueMemberIds.map(userId => {
                const role = userId === ownerId ? 1 : 2;
                return [groupId, userId, role];
            });
            await connection.query(
                'INSERT INTO group_members (group_id, user_id, role) VALUES ?',
                [memberValues]
            );

            for (const userId of uniqueMemberIds) {
                await connection.execute(
                    'INSERT INTO chat_sessions (user_id, session_type, target_id, last_message, unread_count) VALUES (?, ?, ?, ?, ?)',
                    [userId, 2, groupId, `群聊"${name}"已创建`, 0]
                );
            }

            await connection.commit();
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }

        const group = {
            id: groupId,
            name,
            owner_id: ownerId,
            description,
            member_count: uniqueMemberIds.length,
            created_at: new Date().toISOString()
        };

        connectionManager.joinRoom(socket, `group:${groupId}`);

        uniqueMemberIds
            .filter(id => Number(id) !== Number(ownerId))
            .forEach(userId => {
                const socketIds = connectionManager.getUserSocketIds(userId);
                socketIds.forEach(socketId => {
                    const targetSocket = connectionManager.getSocketById(socketId);
                    if (targetSocket) {
                        connectionManager.joinRoom(targetSocket, `group:${groupId}`);
                        targetSocket.emit('group:created', group);
                    }
                });
            });

        logInfo('groupHandler', '群聊创建成功', { groupId, owner: ownerId, members: uniqueMemberIds });
        safeCallback(callback, { success: true, data: group });
    } catch (error) {
        logError('groupHandler', '创建群聊失败', error, { socketId: socket.id });
        safeCallback(callback, { success: false, error: '创建失败' });
    }
};

/**
 * 发送群消息
 */
const sendGroupMessage = async (io, socket, data, callback) => {
    try {
        const fromUserId = socket.userId;
        const { groupId, content, type = 1, share_id, share_title, share_cover } = data;

        if (!groupId) {
            return safeCallback(callback, { success: false, error: '缺少群ID' });
        }
        if (!content || typeof content !== 'string') {
            return safeCallback(callback, { success: false, error: '消息内容不能为空' });
        }
        if (content.length > MAX_MESSAGE_LENGTH) {
            return safeCallback(callback, { success: false, error: '消息长度超过限制' });
        }

        const [membership] = await pool.execute(
            'SELECT id FROM group_members WHERE group_id = ? AND user_id = ?',
            [groupId, fromUserId]
        );
        if (!membership || membership.length === 0) {
            return safeCallback(callback, { success: false, error: '不是群成员，无法发送消息' });
        }

        const [result] = await pool.execute(
            'INSERT INTO group_messages (group_id, from_user_id, content, type, share_id, share_title, share_cover) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [groupId, fromUserId, content, type, share_id || null, share_title || null, share_cover || null]
        );

        const [users] = await pool.execute(
            'SELECT id, nickname, avatar FROM users WHERE id = ?',
            [fromUserId]
        );
        const fromUser = (users && users[0]) || {};

        const message = {
            id: result.insertId,
            group_id: parseInt(groupId),
            from_user_id: parseInt(fromUserId),
            content,
            type,
            share_id: share_id || null,
            share_title: share_title || null,
            share_cover: share_cover || null,
            created_at: new Date().toISOString(),
            from_nickname: fromUser.nickname || null,
            from_avatar: fromUser.avatar || null
        };

        socket.to(`group:${groupId}`).emit('group:message', message);

        await updateGroupSession(groupId, content);
        await incrementGroupUnread(groupId, fromUserId);

        io.to(`group:${groupId}`).emit('session:update', {
            session_type: 2,
            target_id: parseInt(groupId),
            last_message: content,
            updated_at: new Date().toISOString()
        });

        logInfo('groupHandler', '群消息已发送', { messageId: message.id, groupId, from: fromUserId });
        safeCallback(callback, { success: true, data: message });
    } catch (error) {
        logError('groupHandler', '发送群消息失败', error, { socketId: socket.id });
        safeCallback(callback, { success: false, error: '发送失败' });
    }
};

/**
 * 加入群聊
 */
const joinGroup = async (socket, data, callback) => {
    try {
        const userId = socket.userId;
        const { groupId } = data;

        if (!groupId) {
            return safeCallback(callback, { success: false, error: '缺少群ID' });
        }

        const [groups] = await pool.execute(
            'SELECT id, name FROM chat_groups WHERE id = ?',
            [groupId]
        );
        if (!groups || groups.length === 0) {
            return safeCallback(callback, { success: false, error: '群不存在' });
        }

        const [existing] = await pool.execute(
            'SELECT id FROM group_members WHERE group_id = ? AND user_id = ?',
            [groupId, userId]
        );
        if (existing && existing.length > 0) {
            return safeCallback(callback, { success: false, error: '已经是群成员' });
        }

        const connection = await pool.getConnection();
        try {
            await connection.beginTransaction();

            await connection.execute(
                'INSERT INTO group_members (group_id, user_id, role) VALUES (?, ?, ?)',
                [groupId, userId, 2]
            );

            await connection.execute(
                'UPDATE chat_groups SET member_count = member_count + 1 WHERE id = ?',
                [groupId]
            );

            await connection.execute(
                'INSERT INTO chat_sessions (user_id, session_type, target_id, last_message, unread_count) VALUES (?, ?, ?, ?, ?)',
                [userId, 2, groupId, '加入群聊', 0]
            );

            await connection.commit();
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }

        connectionManager.joinRoom(socket, `group:${groupId}`);

        logInfo('groupHandler', '用户加入群聊', { groupId, userId });
        safeCallback(callback, { success: true, message: '加入成功' });
    } catch (error) {
        logError('groupHandler', '加入群聊失败', error, { socketId: socket.id });
        safeCallback(callback, { success: false, error: '加入失败' });
    }
};

/**
 * 退出群聊
 */
const leaveGroup = async (socket, data, callback) => {
    try {
        const userId = socket.userId;
        const { groupId } = data;

        if (!groupId) {
            return safeCallback(callback, { success: false, error: '缺少群ID' });
        }

        const [groups] = await pool.execute(
            'SELECT owner_id FROM chat_groups WHERE id = ?',
            [groupId]
        );
        if (!groups || groups.length === 0) {
            return safeCallback(callback, { success: false, error: '群不存在' });
        }

        if (groups[0].owner_id === userId) {
            return safeCallback(callback, { success: false, error: '群主不能退出群聊' });
        }

        const connection = await pool.getConnection();
        try {
            await connection.beginTransaction();

            await connection.execute(
                'DELETE FROM group_members WHERE group_id = ? AND user_id = ?',
                [groupId, userId]
            );

            await connection.execute(
                'UPDATE chat_groups SET member_count = member_count - 1 WHERE id = ?',
                [groupId]
            );

            await connection.execute(
                'DELETE FROM chat_sessions WHERE session_type = 2 AND target_id = ? AND user_id = ?',
                [groupId, userId]
            );

            await connection.commit();
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }

        connectionManager.leaveRoom(socket, `group:${groupId}`);

        logInfo('groupHandler', '用户退出群聊', { groupId, userId });
        safeCallback(callback, { success: true, message: '退出成功' });
    } catch (error) {
        logError('groupHandler', '退出群聊失败', error, { socketId: socket.id });
        safeCallback(callback, { success: false, error: '退出失败' });
    }
};

/**
 * 群消息已读（清零该群对该用户的未读数）
 */
const markGroupRead = async (socket, data, callback) => {
    try {
        const userId = socket.userId;
        const { groupId } = data;

        if (!groupId) {
            return safeCallback(callback, { success: false, error: '缺少群ID' });
        }

        await pool.execute(
            'UPDATE chat_sessions SET unread_count = 0 WHERE user_id = ? AND session_type = 2 AND target_id = ?',
            [userId, groupId]
        );

        logInfo('groupHandler', '群消息已读', { groupId, userId });
        safeCallback(callback, { success: true });
    } catch (error) {
        logError('groupHandler', '群消息已读失败', error, { socketId: socket.id });
        safeCallback(callback, { success: false, error: '操作失败' });
    }
};

module.exports = {
    createGroup,
    sendGroupMessage,
    joinGroup,
    leaveGroup,
    markGroupRead
};