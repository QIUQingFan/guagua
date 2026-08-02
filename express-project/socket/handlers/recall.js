/**
 * 消息撤回处理器
 * 支持私聊与群聊消息撤回，校验发送者身份与时间窗
 */
const { pool } = require('../../config/config');
const { logInfo, logError } = require('../utils/logger');

const DEFAULT_RECALL_WINDOW_SECONDS = 120;

function safeCallback(callback, data) {
    if (typeof callback === 'function') {
        callback(data);
    }
}

/**
 * 读取撤回时间窗配置
 */
async function getRecallWindow() {
    try {
        const [rows] = await pool.execute(
            "SELECT config_value FROM chat_config WHERE config_key = 'message_recall_window_seconds'"
        );
        if (rows && rows[0]) {
            return parseInt(rows[0].config_value) || DEFAULT_RECALL_WINDOW_SECONDS;
        }
    } catch (e) {
    }
    return DEFAULT_RECALL_WINDOW_SECONDS;
}

/**
 * 撤回私聊消息
 * 校验：消息存在、属于调用方、在时间窗内、未撤回
 */
const recallPrivateMessage = async (socket, data, callback) => {
    try {
        const userId = socket.userId;
        const { messageId } = data || {};

        if (!messageId) {
            return safeCallback(callback, { success: false, error: '缺少消息ID' });
        }

        const [messages] = await pool.execute(
            'SELECT id, from_user_id, to_user_id, created_at, is_recalled FROM private_messages WHERE id = ?',
            [messageId]
        );

        if (!messages || messages.length === 0) {
            return safeCallback(callback, { success: false, error: '消息不存在' });
        }

        const message = messages[0];

        if (Number(message.from_user_id) !== Number(userId)) {
            return safeCallback(callback, { success: false, error: '只能撤回自己发送的消息' });
        }

        if (Number(message.is_recalled) === 1) {
            return safeCallback(callback, { success: false, error: '消息已撤回' });
        }

        const windowSeconds = await getRecallWindow();
        const elapsed = (Date.now() - new Date(message.created_at).getTime()) / 1000;
        if (elapsed > windowSeconds) {
            return safeCallback(callback, { success: false, error: `消息发送超过${windowSeconds}秒，无法撤回` });
        }

        await pool.execute(
            'UPDATE private_messages SET is_recalled = 1, recall_at = NOW(), content = "" WHERE id = ?',
            [messageId]
        );

        const recalledAt = new Date().toISOString();
        const payload = {
            message_id: messageId,
            operator_id: userId,
            recalled_at: recalledAt
        };

        socket.to(`user:${message.to_user_id}`).emit('private:recalled', payload);
        socket.emit('private:recalled', payload);

        logInfo('recallHandler', '私聊消息撤回', { messageId, userId, toUserId: message.to_user_id });
        safeCallback(callback, { success: true, recalled_at: recalledAt });
    } catch (error) {
        logError('recallHandler', '私聊消息撤回失败', error, { socketId: socket.id });
        safeCallback(callback, { success: false, error: '撤回失败' });
    }
};

/**
 * 撤回群消息
 */
const recallGroupMessage = async (socket, data, callback) => {
    try {
        const userId = socket.userId;
        const { groupId, messageId } = data || {};

        if (!messageId || !groupId) {
            return safeCallback(callback, { success: false, error: '缺少参数' });
        }

        const [messages] = await pool.execute(
            'SELECT id, group_id, from_user_id, created_at, is_recalled FROM group_messages WHERE id = ? AND group_id = ?',
            [messageId, groupId]
        );

        if (!messages || messages.length === 0) {
            return safeCallback(callback, { success: false, error: '消息不存在' });
        }

        const message = messages[0];

        if (Number(message.from_user_id) !== Number(userId)) {
            return safeCallback(callback, { success: false, error: '只能撤回自己发送的消息' });
        }

        if (Number(message.is_recalled) === 1) {
            return safeCallback(callback, { success: false, error: '消息已撤回' });
        }

        const windowSeconds = await getRecallWindow();
        const elapsed = (Date.now() - new Date(message.created_at).getTime()) / 1000;
        if (elapsed > windowSeconds) {
            return safeCallback(callback, { success: false, error: `消息发送超过${windowSeconds}秒，无法撤回` });
        }

        await pool.execute(
            'UPDATE group_messages SET is_recalled = 1, recall_at = NOW(), content = "" WHERE id = ?',
            [messageId]
        );

        const recalledAt = new Date().toISOString();
        const payload = {
            group_id: parseInt(groupId),
            message_id: messageId,
            operator_id: userId,
            recalled_at: recalledAt
        };

        socket.to(`group:${groupId}`).emit('group:recalled', payload);
        socket.emit('group:recalled', payload);

        logInfo('recallHandler', '群消息撤回', { messageId, groupId, userId });
        safeCallback(callback, { success: true, recalled_at: recalledAt });
    } catch (error) {
        logError('recallHandler', '群消息撤回失败', error, { socketId: socket.id });
        safeCallback(callback, { success: false, error: '撤回失败' });
    }
};

module.exports = {
    recallPrivateMessage,
    recallGroupMessage
};
