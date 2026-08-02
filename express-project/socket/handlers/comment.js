const { pool } = require('../../config/config');
const { logInfo, logError } = require('../utils/logger');
const NotificationHelper = require('../../utils/notificationHelper');
const { sanitizeContent } = require('../../utils/contentSecurity');
const { extractMentionedUsers, hasMentions } = require('../../utils/mentionParser');

const MAX_COMMENT_LENGTH = 2000;

const safeCallback = (callback, data) => {
    if (typeof callback === 'function') {
        callback(data);
    }
};

/**
 * 创建评论相关通知
 */
const createNotifications = async (userId, postId, commentId, parentId, content) => {
    try {
        if (parentId) {
            const [parentRows] = await pool.execute(
                'SELECT user_id FROM comments WHERE id = ?',
                [parentId.toString()]
            );
            if (parentRows.length > 0 && parentRows[0].user_id !== userId) {
                const data = NotificationHelper.createReplyCommentNotification(
                    parentRows[0].user_id,
                    userId,
                    postId,
                    commentId
                );
                await NotificationHelper.insertNotification(pool, data);
            }
        } else {
            const [postRows] = await pool.execute(
                'SELECT user_id FROM posts WHERE id = ?',
                [postId.toString()]
            );
            if (postRows.length > 0 && postRows[0].user_id !== userId) {
                const data = NotificationHelper.createCommentPostNotification(
                    postRows[0].user_id,
                    userId,
                    postId,
                    commentId
                );
                await NotificationHelper.insertNotification(pool, data);
            }
        }

        if (hasMentions(content)) {
            const mentionedUsers = extractMentionedUsers(content);
            for (const mentionedUser of mentionedUsers) {
                const [userRows] = await pool.execute(
                    'SELECT id FROM users WHERE user_id = ?',
                    [mentionedUser.userId]
                );
                if (userRows.length > 0) {
                    const mentionedUserId = userRows[0].id;
                    if (mentionedUserId !== userId) {
                        const mentionData = NotificationHelper.createNotificationData({
                            userId: mentionedUserId,
                            senderId: userId,
                            type: NotificationHelper.TYPES.MENTION_COMMENT,
                            targetId: postId,
                            commentId
                        });
                        await NotificationHelper.insertNotification(pool, mentionData);
                    }
                }
            }
        }
    } catch (error) {
        logError('commentHandler', '创建评论通知失败', error, { commentId });
    }
};

/**
 * 发布评论并通过 WebSocket 广播
 */
const postComment = async (io, socket, data, callback) => {
    try {
        const userId = socket.userId;
        const { postId, content, parentId = null } = data;

        if (!postId) {
            return safeCallback(callback, { success: false, error: '缺少笔记ID' });
        }
        if (!content || typeof content !== 'string') {
            return safeCallback(callback, { success: false, error: '评论内容不能为空' });
        }

        const sanitizedContent = sanitizeContent(content);
        if (!sanitizedContent.trim()) {
            return safeCallback(callback, { success: false, error: '评论内容不能为空' });
        }
        if (sanitizedContent.length > MAX_COMMENT_LENGTH) {
            return safeCallback(callback, { success: false, error: '评论内容超过限制' });
        }

        const [postRows] = await pool.execute('SELECT id FROM posts WHERE id = ?', [postId.toString()]);
        if (postRows.length === 0) {
            return safeCallback(callback, { success: false, error: '笔记不存在' });
        }

        if (parentId) {
            const [parentRows] = await pool.execute(
                'SELECT id, post_id FROM comments WHERE id = ?',
                [parentId.toString()]
            );
            if (parentRows.length === 0) {
                return safeCallback(callback, { success: false, error: '父评论不存在' });
            }
            if (parentRows[0].post_id != postId) {
                return safeCallback(callback, { success: false, error: '父评论不属于该笔记' });
            }
        }

        const connection = await pool.getConnection();
        let commentId;
        try {
            await connection.beginTransaction();
            const [result] = await connection.execute(
                'INSERT INTO comments (post_id, user_id, content, parent_id) VALUES (?, ?, ?, ?)',
                [postId.toString(), userId.toString(), sanitizedContent, parentId ? parentId.toString() : null]
            );
            commentId = result.insertId;
            await connection.execute(
                'UPDATE posts SET comment_count = comment_count + 1 WHERE id = ?',
                [postId.toString()]
            );
            await connection.commit();
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }

        await createNotifications(userId, postId, commentId, parentId, content);

        const [commentRows] = await pool.execute(
            `SELECT c.*, u.nickname, u.avatar as user_avatar, u.id as user_auto_id,
                    u.user_id as user_display_id, u.location as user_location, u.verified
             FROM comments c
             LEFT JOIN users u ON c.user_id = u.id
             WHERE c.id = ?`,
            [commentId.toString()]
        );

        const commentData = commentRows[0];
        commentData.liked = false;
        commentData.reply_count = 0;

        let replyToUsername = null;
        if (parentId) {
            const [parentAuthorRows] = await pool.execute(
                `SELECT u.nickname FROM comments c
                 LEFT JOIN users u ON c.user_id = u.id
                 WHERE c.id = ?`,
                [parentId.toString()]
            );
            if (parentAuthorRows.length > 0) {
                replyToUsername = parentAuthorRows[0].nickname || '匿名用户';
            }
        }

        const broadcastData = {
            ...commentData,
            reply_to_username: replyToUsername
        };

        io.to(`post:${postId}`).emit('comment:new', broadcastData);

        safeCallback(callback, { success: true, data: broadcastData });
    } catch (error) {
        logError('commentHandler', 'WebSocket 评论失败', error, { socketId: socket.id });
        safeCallback(callback, { success: false, error: '评论失败' });
    }
};

module.exports = {
    postComment
};