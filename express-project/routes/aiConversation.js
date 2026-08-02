/**
 * AI 会话历史路由
 * 挂载于 /api/ai/conversations
 *
 * 接口：
 *   GET    /              会话列表（分页，仅本人）
 *   GET    /:id           会话详情（含消息列表，仅本人）
 *   DELETE /:id           删除会话（软删除，连带消息软删除）
 *
 * 鉴权：全部 authenticateToken（会话强用户绑定）
 */
const express = require('express');
const { pool } = require('../config/config');
const { authenticateToken } = require('../middleware/auth');
const { success, error, handleError } = require('../utils/responseHelper');

const router = express.Router();


router.use(authenticateToken);


router.get('/', async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const pageNum = Math.max(1, parseInt(page, 10) || 1);
    const limitNum = Math.min(100, Math.max(1, parseInt(limit, 10) || 20));
    const offset = (pageNum - 1) * limitNum;

    const [rows] = await pool.execute(
      `SELECT id, title, source, route_summary, message_count, last_message_at, created_at
       FROM ai_conversations
       WHERE user_id = ? AND is_deleted = 0
       ORDER BY last_message_at DESC
       LIMIT ? OFFSET ?`,
      [req.user.id, limitNum, offset]
    );

    const [[{ total }]] = await pool.execute(
      'SELECT COUNT(*) AS total FROM ai_conversations WHERE user_id = ? AND is_deleted = 0',
      [req.user.id]
    );

    success(res, { list: rows, total, page: pageNum, limit: limitNum });
  } catch (err) {
    handleError(err, res, '获取会话列表');
  }
});


router.get('/:id', async (req, res) => {
  try {
    const conversationId = parseInt(req.params.id, 10);
    if (!conversationId) return error(res, '会话ID无效', 400, 400);

    const [[conv]] = await pool.execute(
      `SELECT id, title, source, route_summary, message_count, last_message_at, created_at
       FROM ai_conversations
       WHERE id = ? AND user_id = ? AND is_deleted = 0`,
      [conversationId, req.user.id]
    );
    if (!conv) return error(res, '会话不存在', 404, 404);

    const [messages] = await pool.execute(
      `SELECT id, role, content, route, action, sources, created_at
       FROM ai_messages
       WHERE conversation_id = ? AND is_deleted = 0
       ORDER BY id`,
      [conversationId]
    );

    
    const parseJson = (v) => {
      if (v == null) return null;
      if (typeof v === 'object') return v;
      try { return JSON.parse(v); } catch (e) { return null; }
    };
    const parsedMessages = (messages || []).map((m) => ({
      ...m,
      action: parseJson(m.action),
      sources: parseJson(m.sources),
    }));

    success(res, { ...conv, messages: parsedMessages });
  } catch (err) {
    handleError(err, res, '获取会话详情');
  }
});


router.delete('/:id', async (req, res) => {
  try {
    const conversationId = parseInt(req.params.id, 10);
    if (!conversationId) return error(res, '会话ID无效', 400, 400);

    const [r] = await pool.execute(
      'UPDATE ai_conversations SET is_deleted = 1 WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [conversationId, req.user.id]
    );
    if (r.affectedRows === 0) return error(res, '会话不存在', 404, 404);

    
    await pool.execute('UPDATE ai_messages SET is_deleted = 1 WHERE conversation_id = ?', [conversationId]);

    success(res, null, '删除成功');
  } catch (err) {
    handleError(err, res, '删除会话');
  }
});

module.exports = router;
