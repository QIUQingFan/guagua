/**
 * AI 回复反馈路由
 * 挂载于 /api/ai/feedback
 *
 * 接口：
 *   POST /              提交反馈（点赞/点踩），一人一条消息仅一次
 *   GET  /message/:id   查询某条消息的反馈统计（含当前用户反馈）
 *
 * 鉴权：全部 authenticateToken
 * 表：ai_feedbacks (message_id, user_id, rating(1/-1), comment, uk_message_user 唯一)
 */
const express = require('express');
const { pool } = require('../config/config');
const { authenticateToken } = require('../middleware/auth');
const { success, error, handleError, validateRequired } = require('../utils/responseHelper');

const router = express.Router();

router.use(authenticateToken);


router.post('/', async (req, res) => {
  try {
    const { message_id, rating, comment } = req.body;

    const v = validateRequired({ message_id, rating }, ['message_id', 'rating']);
    if (!v.isValid) return error(res, v.message, 400, 400);

    const messageId = parseInt(message_id, 10);
    const ratingVal = parseInt(rating, 10);
    if (!messageId) return error(res, 'message_id 无效', 400, 400);
    if (ratingVal !== 1 && ratingVal !== -1) {
      return error(res, 'rating 只能为 1(点赞) 或 -1(点踩)', 400, 400);
    }

    
    const [[msgRow]] = await pool.execute(
      'SELECT id, user_id FROM ai_messages WHERE id = ? AND is_deleted = 0',
      [messageId]
    );
    if (!msgRow) return error(res, '消息不存在', 404, 404);

    
    try {
      await pool.execute(
        'INSERT INTO ai_feedbacks (message_id, user_id, rating, comment) VALUES (?, ?, ?, ?)',
        [messageId, req.user.id, ratingVal, comment || null]
      );
    } catch (e) {
      if (e.code === 'ER_DUP_ENTRY') {
        
        await pool.execute(
          'UPDATE ai_feedbacks SET rating = ?, comment = ? WHERE message_id = ? AND user_id = ?',
          [ratingVal, comment || null, messageId, req.user.id]
        );
      } else {
        throw e;
      }
    }

    success(res, { message_id: messageId, rating: ratingVal }, '反馈成功');
  } catch (err) {
    handleError(err, res, '提交反馈');
  }
});


router.get('/message/:id', async (req, res) => {
  try {
    const messageId = parseInt(req.params.id, 10);
    if (!messageId) return error(res, '消息ID无效', 400, 400);

    const [[stat]] = await pool.execute(
      `SELECT
         SUM(CASE WHEN rating = 1 THEN 1 ELSE 0 END) AS likes,
         SUM(CASE WHEN rating = -1 THEN 1 ELSE 0 END) AS dislikes
       FROM ai_feedbacks WHERE message_id = ?`,
      [messageId]
    );

    const [[mine]] = await pool.execute(
      'SELECT rating FROM ai_feedbacks WHERE message_id = ? AND user_id = ?',
      [messageId, req.user.id]
    );

    success(res, {
      message_id: messageId,
      likes: stat.likes || 0,
      dislikes: stat.dislikes || 0,
      my_rating: mine ? mine.rating : 0,
    });
  } catch (err) {
    handleError(err, res, '查询反馈');
  }
});

module.exports = router;
