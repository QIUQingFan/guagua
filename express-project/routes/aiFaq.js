/**
 * FAQ 知识库管理路由（管理端）
 * 挂载于 /api/ai/faqs
 *
 * 接口：
 *   GET    /              列表（分页 + category/is_active 过滤）
 *   GET    /:id           详情
 *   POST   /              新建
 *   PUT    /:id           更新
 *   DELETE /:id           删除
 *
 * 鉴权：全部 authenticateToken + admin
 * 表：ai_faqs (question, answer, category, sort, tags, is_active, created_by)
 */
const express = require('express');
const { pool } = require('../config/config');
const { authenticateToken } = require('../middleware/auth');
const { success, error, handleError, validateRequired } = require('../utils/responseHelper');

const router = express.Router();


router.use(authenticateToken);
router.use((req, res, next) => {
  if (!req.user || req.user.type !== 'admin') {
    return error(res, '无权限，需要管理员账号', 403, 403);
  }
  next();
});


router.get('/', async (req, res) => {
  try {
    const { page = 1, limit = 20, category, is_active } = req.query;
    const pageNum = Math.max(1, parseInt(page, 10) || 1);
    const limitNum = Math.min(100, Math.max(1, parseInt(limit, 10) || 20));
    const offset = (pageNum - 1) * limitNum;

    const where = [];
    const params = [];
    if (category) {
      where.push('category = ?');
      params.push(category);
    }
    if (is_active !== undefined && is_active !== '') {
      where.push('is_active = ?');
      params.push(parseInt(is_active, 10) === 1 ? 1 : 0);
    }
    const whereSql = where.length ? 'WHERE ' + where.join(' AND ') : '';

    const [rows] = await pool.execute(
      `SELECT id, question, answer, category, sort, tags, is_active, created_at, updated_at
       FROM ai_faqs ${whereSql}
       ORDER BY sort DESC, id DESC
       LIMIT ? OFFSET ?`,
      [...params, limitNum, offset]
    );

    const [[{ total }]] = await pool.execute(
      `SELECT COUNT(*) AS total FROM ai_faqs ${whereSql}`,
      params
    );

    success(res, { list: rows, total, page: pageNum, limit: limitNum });
  } catch (err) {
    handleError(err, res, '获取FAQ列表');
  }
});


router.get('/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id) return error(res, 'ID无效', 400, 400);

    const [[row]] = await pool.execute(
      'SELECT * FROM ai_faqs WHERE id = ?',
      [id]
    );
    if (!row) return error(res, 'FAQ不存在', 404, 404);

    success(res, row);
  } catch (err) {
    handleError(err, res, '获取FAQ详情');
  }
});


router.post('/', async (req, res) => {
  try {
    const { question, answer, category = 'other', sort = 0, tags = null, is_active = 1 } = req.body;

    const v = validateRequired({ question, answer }, ['question', 'answer']);
    if (!v.isValid) return error(res, v.message, 400, 400);

    const [r] = await pool.execute(
      `INSERT INTO ai_faqs (question, answer, category, sort, tags, is_active, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [question, answer, category, parseInt(sort, 10) || 0, tags, is_active ? 1 : 0, req.user.adminId || req.user.id]
    );

    success(res, { id: r.insertId }, '创建成功');
  } catch (err) {
    handleError(err, res, '创建FAQ');
  }
});


router.put('/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id) return error(res, 'ID无效', 400, 400);

    const { question, answer, category, sort, tags, is_active } = req.body;
    const fields = [];
    const params = [];
    if (question !== undefined) { fields.push('question = ?'); params.push(question); }
    if (answer !== undefined) { fields.push('answer = ?'); params.push(answer); }
    if (category !== undefined) { fields.push('category = ?'); params.push(category); }
    if (sort !== undefined) { fields.push('sort = ?'); params.push(parseInt(sort, 10) || 0); }
    if (tags !== undefined) { fields.push('tags = ?'); params.push(tags); }
    if (is_active !== undefined) { fields.push('is_active = ?'); params.push(is_active ? 1 : 0); }

    if (fields.length === 0) return error(res, '无更新字段', 400, 400);

    params.push(id);
    const [r] = await pool.execute(
      `UPDATE ai_faqs SET ${fields.join(', ')} WHERE id = ?`,
      params
    );
    if (r.affectedRows === 0) return error(res, 'FAQ不存在', 404, 404);

    success(res, null, '更新成功');
  } catch (err) {
    handleError(err, res, '更新FAQ');
  }
});


router.delete('/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (!id) return error(res, 'ID无效', 400, 400);

    const [r] = await pool.execute('DELETE FROM ai_faqs WHERE id = ?', [id]);
    if (r.affectedRows === 0) return error(res, 'FAQ不存在', 404, 404);

    success(res, null, '删除成功');
  } catch (err) {
    handleError(err, res, '删除FAQ');
  }
});

module.exports = router;
