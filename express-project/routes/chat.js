const express = require('express');
const router = express.Router();
const { authenticateToken } = require('../middleware/auth');
const { pool } = require('../config/config');
const { HTTP_STATUS, RESPONSE_CODES } = require('../constants');
const connectionManager = require('../socket/manager/connectionManager');

const DEFAULT_PAGE_SIZE = 20;

/**
 * 获取私聊历史记录
 * GET /api/chat/private/history?userId=123&page=1&pageSize=20
 */
router.get('/private/history', authenticateToken, async (req, res) => {
    try {
        const currentUserId = req.user.id;
        const targetUserId = parseInt(req.query.userId);
        const page = parseInt(req.query.page) || 1;
        const pageSize = parseInt(req.query.pageSize) || DEFAULT_PAGE_SIZE;

        if (!targetUserId) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '缺少用户ID'
            });
        }

        const offset = (page - 1) * pageSize;

        const [messages] = await pool.execute(
            `SELECT pm.*, 
              u_from.nickname as from_nickname, u_from.avatar as from_avatar,
              u_to.nickname as to_nickname, u_to.avatar as to_avatar
       FROM private_messages pm
       JOIN users u_from ON pm.from_user_id = u_from.id
       JOIN users u_to ON pm.to_user_id = u_to.id
       WHERE (pm.from_user_id = ? AND pm.to_user_id = ?) 
          OR (pm.from_user_id = ? AND pm.to_user_id = ?)
       ORDER BY pm.created_at DESC
       LIMIT ? OFFSET ?`,
            [currentUserId, targetUserId, targetUserId, currentUserId, pageSize.toString(), offset.toString()]
        );

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: messages.reverse(),
            pagination: {
                page,
                pageSize,
                hasMore: messages.length === pageSize
            }
        });
    } catch (error) {
        console.error('获取私聊历史记录失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '获取失败'
        });
    }
});

/**
 * 获取会话列表
 * GET /api/chat/sessions
 */
router.get('/sessions', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;

        const [sessions] = await pool.execute(
            `SELECT cs.*, 
        CASE 
          WHEN cs.session_type = 1 THEN u.nickname 
          ELSE cg.name 
        END as target_nickname,
        CASE 
          WHEN cs.session_type = 1 THEN u.avatar 
          ELSE cg.avatar 
        END as target_avatar,
        cg.announcement as group_announcement,
        gma.member_avatars
       FROM chat_sessions cs
       LEFT JOIN users u ON cs.session_type = 1 AND cs.target_id = u.id
       LEFT JOIN chat_groups cg ON cs.session_type = 2 AND cs.target_id = cg.id
       LEFT JOIN (
           SELECT gm.group_id, GROUP_CONCAT(u.avatar ORDER BY gm.role ASC, gm.joined_at ASC SEPARATOR ',') AS member_avatars
           FROM group_members gm
           JOIN users u ON gm.user_id = u.id
           GROUP BY gm.group_id
       ) gma ON cs.session_type = 2 AND cs.target_id = gma.group_id
       WHERE cs.user_id = ?
       ORDER BY cs.updated_at DESC`,
            [userId]
        );

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: sessions
        });
    } catch (error) {
        console.error('获取会话列表失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '获取失败'
        });
    }
});

/**
 * 获取用户简要信息
 * GET /api/chat/user/:id/brief
 */
router.get('/user/:id/brief', authenticateToken, async (req, res) => {
    try {
        const targetId = parseInt(req.params.id);
        const [users] = await pool.execute(
            'SELECT id, nickname, avatar FROM users WHERE id = ?',
            [targetId]
        );
        if (!users || users.length === 0) {
            return res.status(HTTP_STATUS.NOT_FOUND).json({
                code: RESPONSE_CODES.NOT_FOUND,
                message: '用户不存在'
            });
        }
        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: users[0]
        });
    } catch (error) {
        console.error('获取用户简要信息失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '获取失败'
        });
    }
});

/**
 * 创建会话（私聊）
 * POST /api/chat/sessions
 * body: { target_id: number, type: 'private' }
 */
router.post('/sessions', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const { target_id, type = 'private' } = req.body;

        if (!target_id) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '缺少目标用户ID'
            });
        }
        if (type !== 'private') {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '暂仅支持私聊会话创建'
            });
        }
        const targetId = parseInt(target_id);
        if (!targetId || targetId === userId) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '不能与自己创建会话'
            });
        }


        const [users] = await pool.execute(
            'SELECT id, nickname, avatar FROM users WHERE id = ?',
            [String(targetId)]
        );
        if (!users || users.length === 0) {
            return res.status(HTTP_STATUS.NOT_FOUND).json({
                code: RESPONSE_CODES.NOT_FOUND,
                message: '用户不存在'
            });
        }
        const peer = users[0];


        const [existing] = await pool.execute(
            'SELECT * FROM chat_sessions WHERE user_id = ? AND session_type = 1 AND target_id = ?',
            [String(userId), String(targetId)]
        );
        let session;
        if (existing && existing.length > 0) {
            session = existing[0];
        } else {
            const [r] = await pool.execute(
                'INSERT INTO chat_sessions (user_id, session_type, target_id, last_message, unread_count) VALUES (?, 1, ?, ?, 0)',
                [String(userId), String(targetId), '']
            );
            session = {
                id: r.insertId,
                user_id: userId,
                session_type: 1,
                target_id: targetId,
                last_message: '',
                unread_count: 0,
                updated_at: new Date()
            };

            const [peerExisting] = await pool.execute(
                'SELECT id FROM chat_sessions WHERE user_id = ? AND session_type = 1 AND target_id = ?',
                [String(targetId), String(userId)]
            );
            if (!peerExisting || peerExisting.length === 0) {
                await pool.execute(
                    'INSERT INTO chat_sessions (user_id, session_type, target_id, last_message, unread_count) VALUES (?, 1, ?, ?, 0)',
                    [String(targetId), String(userId), '']
                );
            }
        }

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: {
                id: session.id,
                session_type: 1,
                type: 'private',
                target_id: targetId,
                peer_id: targetId,
                name: peer.nickname,
                nickname: peer.nickname,
                avatar: peer.avatar,
                target_nickname: peer.nickname,
                target_avatar: peer.avatar,
                last_message: session.last_message || '',
                unread_count: session.unread_count || 0,
                updated_at: session.updated_at
            }
        });
    } catch (error) {
        console.error('创建会话失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '创建失败'
        });
    }
});

/**
 * 获取会话消息历史（私聊/群聊统一入口）
 * GET /api/chat/messages/:sessionId?page=1&limit=20
 */
router.get('/messages/:sessionId', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const sessionId = parseInt(req.params.sessionId);
        const page = parseInt(req.query.page) || 1;
        const limit = Math.min(Math.max(parseInt(req.query.limit) || 20, 1), 100);
        const offset = (page - 1) * limit;

        if (!sessionId) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '缺少会话ID'
            });
        }


        const [sessions] = await pool.execute(
            'SELECT * FROM chat_sessions WHERE id = ? AND user_id = ?',
            [String(sessionId), String(userId)]
        );
        if (!sessions || sessions.length === 0) {
            return res.status(HTTP_STATUS.NOT_FOUND).json({
                code: RESPONSE_CODES.NOT_FOUND,
                message: '会话不存在'
            });
        }
        const session = sessions[0];

        let rows = [];
        let total = 0;

        if (session.session_type === 1) {

            const peerId = session.target_id;
            [rows] = await pool.execute(
                `SELECT pm.id, pm.from_user_id, pm.to_user_id, pm.content, pm.type, pm.is_read, pm.created_at,
                        pm.share_id, pm.share_title, pm.share_cover,
                        pm.is_recalled, pm.recall_at, pm.quote_message_id, pm.extra,
                        u_from.nickname AS from_nickname, u_from.avatar AS from_avatar
                 FROM private_messages pm
                 JOIN users u_from ON pm.from_user_id = u_from.id
                 WHERE (pm.from_user_id = ? AND pm.to_user_id = ?)
                    OR (pm.from_user_id = ? AND pm.to_user_id = ?)
                 ORDER BY pm.created_at DESC
                 LIMIT ? OFFSET ?`,
                [String(userId), String(peerId), String(peerId), String(userId), String(limit), String(offset)]
            );
            const [[{ total: t }]] = await pool.execute(
                `SELECT COUNT(*) AS total FROM private_messages pm
                 WHERE (pm.from_user_id = ? AND pm.to_user_id = ?)
                    OR (pm.from_user_id = ? AND pm.to_user_id = ?)`,
                [String(userId), String(peerId), String(peerId), String(userId)]
            );
            total = t;
        } else {

            const groupId = session.target_id;
            [rows] = await pool.execute(
                `SELECT gm.id, gm.user_id AS from_user_id, gm.content, gm.type, gm.created_at,
                        gm.share_id, gm.share_title, gm.share_cover,
                        gm.is_recalled, gm.recall_at, gm.quote_message_id, gm.extra,
                        u.nickname AS from_nickname, u.avatar AS from_avatar
                 FROM group_messages gm
                 JOIN users u ON gm.user_id = u.id
                 WHERE gm.group_id = ?
                 ORDER BY gm.created_at DESC
                 LIMIT ? OFFSET ?`,
                [String(groupId), String(limit), String(offset)]
            );
            const [[{ total: t }]] = await pool.execute(
                'SELECT COUNT(*) AS total FROM group_messages WHERE group_id = ?',
                [String(groupId)]
            );
            total = t;
        }

        const messages = rows.map(m => ({
            ...m,
            session_id: sessionId,
            read_by_peer: m.from_user_id === userId ? (m.is_read === 1 || m.is_read === '1') : false
        }));

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: {
                messages: messages,
                pagination: {
                    page,
                    limit,
                    total,
                    pages: Math.ceil(total / limit) || 1
                }
            }
        });
    } catch (error) {
        console.error('获取会话消息失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '获取失败'
        });
    }
});

/**
 * 获取未读消息总数
 * GET /api/chat/unread-count
 */
router.get('/unread-count', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;

        const [result] = await pool.execute(
            'SELECT SUM(unread_count) as total FROM chat_sessions WHERE user_id = ?',
            [userId]
        );

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: {
                total: result[0].total || 0
            }
        });
    } catch (error) {
        console.error('获取未读数失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '获取失败'
        });
    }
});

/**
 * 获取当前用户的群列表
 * GET /api/chat/groups
 */
router.get('/groups', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;

        const [groups] = await pool.execute(
            `SELECT cg.*, gm.role, gma.member_avatars
       FROM chat_groups cg
       JOIN group_members gm ON cg.id = gm.group_id
       LEFT JOIN (
           SELECT gm.group_id, GROUP_CONCAT(u.avatar ORDER BY gm.role ASC, gm.joined_at ASC SEPARATOR ',') AS member_avatars
           FROM group_members gm
           JOIN users u ON gm.user_id = u.id
           GROUP BY gm.group_id
       ) gma ON cg.id = gma.group_id
       WHERE gm.user_id = ?
       ORDER BY cg.updated_at DESC`,
            [userId]
        );

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: groups
        });
    } catch (error) {
        console.error('获取群列表失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '获取失败'
        });
    }
});

/**
 * 创建群聊
 * POST /api/chat/groups
 */
router.post('/groups', authenticateToken, async (req, res) => {
    try {
        const ownerId = req.user.id;
        const { name, description = '', memberIds = [] } = req.body;

        if (!name) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '群名称不能为空'
            });
        }

        const uniqueMemberIds = [...new Set([...memberIds.map(Number), ownerId])];
        if (uniqueMemberIds.length < 2) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '群聊至少需要两名成员'
            });
        }

        const connection = await pool.getConnection();
        try {
            await connection.beginTransaction();

            const [groupResult] = await connection.execute(
                'INSERT INTO chat_groups (name, owner_id, description, member_count) VALUES (?, ?, ?, ?)',
                [name, ownerId, description, uniqueMemberIds.length]
            );
            const groupId = groupResult.insertId;

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


            const io = req.app.get('io');
            if (io) {
                uniqueMemberIds.forEach(memberId => {
                    const socketIds = connectionManager.getUserSocketIds(memberId);
                    socketIds.forEach(socketId => {
                        const socket = io.sockets.sockets.get(socketId);
                        if (socket) {
                            socket.join(`group:${groupId}`);
                            socket.emit('group:created', {
                                id: groupId,
                                name,
                                owner_id: ownerId,
                                description,
                                member_count: uniqueMemberIds.length,
                                created_at: new Date().toISOString()
                            });
                        }
                    });
                });
            }

            res.json({
                code: RESPONSE_CODES.SUCCESS,
                data: {
                    id: groupId,
                    name,
                    owner_id: ownerId,
                    description,
                    member_count: uniqueMemberIds.length
                }
            });
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }
    } catch (error) {
        console.error('创建群聊失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '创建失败'
        });
    }
});

/**
 * 更新群聊信息（仅群主）
 * PUT /api/chat/groups/:id
 * body: { name?, description?, avatar? }
 */
router.put('/groups/:id', authenticateToken, async (req, res) => {
    try {
        const operatorId = req.user.id;
        const groupId = parseInt(req.params.id);
        const { name, description, avatar } = req.body;

        const [groups] = await pool.execute(
            'SELECT id, owner_id FROM chat_groups WHERE id = ?',
            [groupId]
        );
        if (!groups || groups.length === 0) {
            return res.status(HTTP_STATUS.NOT_FOUND).json({
                code: RESPONSE_CODES.NOT_FOUND,
                message: '群不存在'
            });
        }

        if (groups[0].owner_id !== operatorId) {
            return res.status(HTTP_STATUS.FORBIDDEN).json({
                code: RESPONSE_CODES.FORBIDDEN,
                message: '只有群主可以修改群信息'
            });
        }

        if (name !== undefined && (typeof name !== 'string' || !name.trim())) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '群名称不能为空'
            });
        }
        if (name !== undefined && name.length > 100) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '群名称过长'
            });
        }

        const fields = [];
        const values = [];
        if (name !== undefined) {
            fields.push('`name` = ?');
            values.push(name.trim());
        }
        if (description !== undefined) {
            fields.push('`description` = ?');
            values.push(description);
        }
        if (avatar !== undefined) {
            fields.push('`avatar` = ?');
            values.push(avatar || null);
        }
        if (fields.length === 0) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '没有需要更新的字段'
            });
        }

        values.push(groupId);
        await pool.execute(
            `UPDATE chat_groups SET ${fields.join(', ')} WHERE id = ?`,
            values
        );

        const [updated] = await pool.execute(
            'SELECT id, name, avatar, description, announcement, announcement_updated_at, member_count, created_at FROM chat_groups WHERE id = ?',
            [groupId]
        );

        // 实时通知群内成员
        const io = req.app.get('io');
        if (io) {
            io.to(`group:${groupId}`).emit('group:updated', updated[0]);
        }

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: updated[0]
        });
    } catch (error) {
        console.error('更新群信息失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '更新失败'
        });
    }
});

/**
 * 更新群公告（仅群主）
 * PUT /api/chat/groups/:id/announcement
 * body: { announcement: string }
 */
router.put('/groups/:id/announcement', authenticateToken, async (req, res) => {
    try {
        const operatorId = req.user.id;
        const groupId = parseInt(req.params.id);
        const { announcement } = req.body;

        const [groups] = await pool.execute(
            'SELECT id, owner_id FROM chat_groups WHERE id = ?',
            [groupId]
        );
        if (!groups || groups.length === 0) {
            return res.status(HTTP_STATUS.NOT_FOUND).json({
                code: RESPONSE_CODES.NOT_FOUND,
                message: '群不存在'
            });
        }

        if (groups[0].owner_id !== operatorId) {
            return res.status(HTTP_STATUS.FORBIDDEN).json({
                code: RESPONSE_CODES.FORBIDDEN,
                message: '只有群主可以修改群公告'
            });
        }

        if (announcement === undefined || typeof announcement !== 'string') {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '公告内容不能为空'
            });
        }

        const trimmed = announcement.trim();
        await pool.execute(
            'UPDATE chat_groups SET announcement = ?, announcement_updated_at = NOW() WHERE id = ?',
            [trimmed || null, groupId]
        );

        const [updated] = await pool.execute(
            'SELECT id, name, avatar, description, announcement, announcement_updated_at, member_count, created_at FROM chat_groups WHERE id = ?',
            [groupId]
        );

        const io = req.app.get('io');
        if (io) {
            io.to(`group:${groupId}`).emit('group:updated', updated[0]);
        }

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: updated[0]
        });
    } catch (error) {
        console.error('更新群公告失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '更新失败'
        });
    }
});

/**
 * 获取群成员列表
 * GET /api/chat/groups/:id/members
 */
router.get('/groups/:id/members', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const groupId = parseInt(req.params.id);


        const [membership] = await pool.execute(
            'SELECT id FROM group_members WHERE group_id = ? AND user_id = ?',
            [groupId, userId]
        );
        if (!membership || membership.length === 0) {
            return res.status(HTTP_STATUS.FORBIDDEN).json({
                code: RESPONSE_CODES.FORBIDDEN,
                message: '不是群成员'
            });
        }

        const [members] = await pool.execute(
            `SELECT u.id, u.nickname, u.avatar, gm.role, gm.joined_at
       FROM group_members gm
       JOIN users u ON gm.user_id = u.id
       WHERE gm.group_id = ?
       ORDER BY gm.role ASC, gm.joined_at ASC`,
            [groupId]
        );

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: members
        });
    } catch (error) {
        console.error('获取群成员失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '获取失败'
        });
    }
});

/**
 * 获取群消息历史
 * GET /api/chat/groups/:id/messages?page=1&pageSize=20
 */
router.get('/groups/:id/messages', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const groupId = parseInt(req.params.id);
        const page = parseInt(req.query.page) || 1;
        const pageSize = parseInt(req.query.pageSize) || DEFAULT_PAGE_SIZE;
        const offset = (page - 1) * pageSize;


        const [membership] = await pool.execute(
            'SELECT id FROM group_members WHERE group_id = ? AND user_id = ?',
            [groupId, userId]
        );
        if (!membership || membership.length === 0) {
            return res.status(HTTP_STATUS.FORBIDDEN).json({
                code: RESPONSE_CODES.FORBIDDEN,
                message: '不是群成员'
            });
        }

        const [messages] = await pool.execute(
            `SELECT gm.*, u.nickname as from_nickname, u.avatar as from_avatar
       FROM group_messages gm
       JOIN users u ON gm.from_user_id = u.id
       WHERE gm.group_id = ?
       ORDER BY gm.created_at DESC
       LIMIT ? OFFSET ?`,
            [groupId, pageSize.toString(), offset.toString()]
        );

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: messages.reverse(),
            pagination: {
                page,
                pageSize,
                hasMore: messages.length === pageSize
            }
        });
    } catch (error) {
        console.error('获取群消息失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '获取失败'
        });
    }
});

/**
 * 群消息已读
 * POST /api/chat/groups/:id/read
 */
router.post('/groups/:id/read', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const groupId = parseInt(req.params.id);


        const [membership] = await pool.execute(
            'SELECT id FROM group_members WHERE group_id = ? AND user_id = ?',
            [groupId, userId]
        );
        if (!membership || membership.length === 0) {
            return res.status(HTTP_STATUS.FORBIDDEN).json({
                code: RESPONSE_CODES.FORBIDDEN,
                message: '不是群成员'
            });
        }

        const [result] = await pool.execute(
            'UPDATE chat_sessions SET unread_count = 0 WHERE user_id = ? AND session_type = 2 AND target_id = ?',
            [userId, groupId]
        );

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data: { cleared: result.affectedRows }
        });
    } catch (error) {
        console.error('群消息已读失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '操作失败'
        });
    }
});

/**
 * 加入群聊
 * POST /api/chat/groups/:id/join
 */
router.post('/groups/:id/join', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const groupId = parseInt(req.params.id);


        const [groups] = await pool.execute(
            'SELECT id FROM chat_groups WHERE id = ?',
            [groupId]
        );
        if (!groups || groups.length === 0) {
            return res.status(HTTP_STATUS.NOT_FOUND).json({
                code: RESPONSE_CODES.NOT_FOUND,
                message: '群不存在'
            });
        }


        const [existing] = await pool.execute(
            'SELECT id FROM group_members WHERE group_id = ? AND user_id = ?',
            [groupId, userId]
        );
        if (existing && existing.length > 0) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '已经是群成员'
            });
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

            res.json({
                code: RESPONSE_CODES.SUCCESS,
                message: '加入成功'
            });
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }
    } catch (error) {
        console.error('加入群聊失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '加入失败'
        });
    }
});

/**
 * 退出群聊
 * POST /api/chat/groups/:id/leave
 */
router.post('/groups/:id/leave', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const groupId = parseInt(req.params.id);

        const [groups] = await pool.execute(
            'SELECT owner_id FROM chat_groups WHERE id = ?',
            [groupId]
        );
        if (!groups || groups.length === 0) {
            return res.status(HTTP_STATUS.NOT_FOUND).json({
                code: RESPONSE_CODES.NOT_FOUND,
                message: '群不存在'
            });
        }

        if (groups[0].owner_id === userId) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '群主不能退出群聊'
            });
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

            res.json({
                code: RESPONSE_CODES.SUCCESS,
                message: '退出成功'
            });
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }
    } catch (error) {
        console.error('退出群聊失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '退出失败'
        });
    }
});

/**
 * 获取群邀请候选用户
 * GET /api/chat/groups/:id/invite-candidates
 */
router.get('/groups/:id/invite-candidates', authenticateToken, async (req, res) => {
    try {
        const userId = req.user.id;
        const groupId = parseInt(req.params.id);

        // 当前群成员ID（含自己）
        const [members] = await pool.execute(
            'SELECT user_id FROM group_members WHERE group_id = ?',
            [groupId]
        );
        const memberIds = new Set(members.map(m => Number(m.user_id)));
        memberIds.add(Number(userId));

        // 1. 最近聊天对象（私聊会话）
        const [recentChats] = await pool.execute(
            `SELECT cs.target_id AS id, u.nickname, u.avatar
             FROM chat_sessions cs
             LEFT JOIN users u ON cs.target_id = u.id
             WHERE cs.user_id = ? AND cs.session_type = 1
             ORDER BY cs.updated_at DESC
             LIMIT 30`,
            [userId]
        );

        // 2. 关注对象
        const [followed] = await pool.execute(
            `SELECT u.id, u.nickname, u.avatar
             FROM follows f
             LEFT JOIN users u ON f.following_id = u.id
             WHERE f.follower_id = ?
             ORDER BY f.created_at DESC
             LIMIT 30`,
            [userId.toString()]
        );

        // 合并去重，标注来源
        const map = new Map();
        const addUser = (u, source) => {
            if (!u || !u.id) return;
            const id = Number(u.id);
            if (!id || memberIds.has(id)) return;
            if (!map.has(id)) {
                map.set(id, { id, nickname: u.nickname || `用户${id}`, avatar: u.avatar, sources: new Set() });
            }
            map.get(id).sources.add(source);
        };
        recentChats.forEach(u => addUser(u, 'chat'));
        followed.forEach(u => addUser(u, 'follow'));

        const data = Array.from(map.values()).map(item => ({
            id: item.id,
            nickname: item.nickname,
            avatar: item.avatar,
            sources: Array.from(item.sources)
        }));

        res.json({
            code: RESPONSE_CODES.SUCCESS,
            data
        });
    } catch (error) {
        console.error('获取群邀请候选失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '获取失败'
        });
    }
});

/**
 * 邀请用户加入群聊
 * POST /api/chat/groups/:id/invite
 */
router.post('/groups/:id/invite', authenticateToken, async (req, res) => {
    try {
        const inviterId = req.user.id;
        const groupId = parseInt(req.params.id);
        const { userId } = req.body;

        if (!userId) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '缺少被邀请用户ID'
            });
        }


        const [membership] = await pool.execute(
            'SELECT id FROM group_members WHERE group_id = ? AND user_id = ?',
            [groupId, inviterId]
        );
        if (!membership || membership.length === 0) {
            return res.status(HTTP_STATUS.FORBIDDEN).json({
                code: RESPONSE_CODES.FORBIDDEN,
                message: '不是群成员，无法邀请'
            });
        }


        const [existing] = await pool.execute(
            'SELECT id FROM group_members WHERE group_id = ? AND user_id = ?',
            [groupId, userId]
        );
        if (existing && existing.length > 0) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '用户已是群成员'
            });
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
                [userId, 2, groupId, '被邀请加入群聊', 0]
            );

            await connection.commit();


            const io = req.app.get('io');
            if (io) {
                const socketIds = connectionManager.getUserSocketIds(userId);
                socketIds.forEach(socketId => {
                    const socket = io.sockets.sockets.get(socketId);
                    if (socket) {
                        socket.join(`group:${groupId}`);
                        socket.emit('group:invited', { groupId, inviterId });
                    }
                });
            }

            res.json({ code: RESPONSE_CODES.SUCCESS, message: '邀请成功' });
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }
    } catch (error) {
        console.error('邀请用户失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '邀请失败'
        });
    }
});

/**
 * 移除群成员
 * POST /api/chat/groups/:id/remove
 */
router.post('/groups/:id/remove', authenticateToken, async (req, res) => {
    try {
        const operatorId = req.user.id;
        const groupId = parseInt(req.params.id);
        const { userId } = req.body;

        if (!userId) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '缺少被移除用户ID'
            });
        }


        const [operator] = await pool.execute(
            'SELECT role FROM group_members WHERE group_id = ? AND user_id = ?',
            [groupId, operatorId]
        );
        if (!operator || operator.length === 0 || operator[0].role !== 1) {
            return res.status(HTTP_STATUS.FORBIDDEN).json({
                code: RESPONSE_CODES.FORBIDDEN,
                message: '只有群主可以移除成员'
            });
        }

        if (parseInt(userId) === operatorId) {
            return res.status(HTTP_STATUS.BAD_REQUEST).json({
                code: RESPONSE_CODES.VALIDATION_ERROR,
                message: '不能移除自己'
            });
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


            const io = req.app.get('io');
            if (io) {
                const socketIds = connectionManager.getUserSocketIds(userId);
                socketIds.forEach(socketId => {
                    const socket = io.sockets.sockets.get(socketId);
                    if (socket) {
                        socket.leave(`group:${groupId}`);
                        socket.emit('group:removed', { groupId });
                    }
                });
            }

            res.json({ code: RESPONSE_CODES.SUCCESS, message: '移除成功' });
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }
    } catch (error) {
        console.error('移除成员失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '移除失败'
        });
    }
});

/**
 * 解散群聊
 * POST /api/chat/groups/:id/dissolve
 */
router.post('/groups/:id/dissolve', authenticateToken, async (req, res) => {
    try {
        const operatorId = req.user.id;
        const groupId = parseInt(req.params.id);

        const [groups] = await pool.execute(
            'SELECT owner_id FROM chat_groups WHERE id = ?',
            [groupId]
        );
        if (!groups || groups.length === 0) {
            return res.status(HTTP_STATUS.NOT_FOUND).json({
                code: RESPONSE_CODES.NOT_FOUND,
                message: '群不存在'
            });
        }

        if (groups[0].owner_id !== operatorId) {
            return res.status(HTTP_STATUS.FORBIDDEN).json({
                code: RESPONSE_CODES.FORBIDDEN,
                message: '只有群主可以解散群聊'
            });
        }

        const connection = await pool.getConnection();
        try {
            await connection.beginTransaction();

            await connection.execute(
                'DELETE FROM chat_sessions WHERE session_type = 2 AND target_id = ?',
                [groupId]
            );

            await connection.execute(
                'DELETE FROM group_members WHERE group_id = ?',
                [groupId]
            );

            await connection.execute(
                'DELETE FROM group_messages WHERE group_id = ?',
                [groupId]
            );

            await connection.execute(
                'DELETE FROM chat_groups WHERE id = ?',
                [groupId]
            );

            await connection.commit();


            const io = req.app.get('io');
            if (io) {
                io.to(`group:${groupId}`).emit('group:dissolved', { groupId });
            }

            res.json({ code: RESPONSE_CODES.SUCCESS, message: '解散成功' });
        } catch (error) {
            await connection.rollback();
            throw error;
        } finally {
            connection.release();
        }
    } catch (error) {
        console.error('解散群聊失败:', error);
        res.status(HTTP_STATUS.INTERNAL_SERVER_ERROR).json({
            code: RESPONSE_CODES.ERROR,
            message: '解散失败'
        });
    }
});

module.exports = router;