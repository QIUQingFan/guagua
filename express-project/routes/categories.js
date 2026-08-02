const express = require('express');
const router = express.Router();
const { pool } = require('../config/config');
const { success, error } = require('../utils/responseHelper');

/**
 * @api {get} /api/categories 获取分类列表
 * @apiName GetCategories
 * @apiGroup Categories
 * @apiDescription 获取所有分类列表
 * 
 * @apiSuccess {Number} code 状态码
 * @apiSuccess {String} message 响应消息
 * @apiSuccess {Array} data 分类列表
 * @apiSuccess {Number} data.id 分类ID
 * @apiSuccess {String} data.name 分类名称
 * 
 * @apiSuccessExample {json} Success-Response:
 *     HTTP/1.1 200 OK
 *     {
 *       "code": 200,
 *       "message": "获取成功",
 *       "data": [
 *         {
 *           "id": 1,
 *           "name": "推荐"
 *         },
 *         {
 *           "id": 2,
 *           "name": "学习"
 *         }
 *       ]
 *     }
 */
router.get('/', async (req, res) => {
  try {
    const { sortField = 'id', sortOrder = 'asc', name, category_title } = req.query;

    const allowedSortFields = {
      'id': 'c.id',
      'name': 'c.name',
      'created_at': 'c.created_at',
      'post_count': 'post_count'
    };
    const allowedSortOrders = {
      'asc': 'ASC',
      'desc': 'DESC'
    };
    const validSortField = allowedSortFields[sortField] || allowedSortFields['id'];
    const validSortOrder = allowedSortOrders[sortOrder?.toLowerCase()] || allowedSortOrders['asc'];

    
    const queryParams = [];
    const conditions = [];

    if (name && typeof name === 'string' && name.trim()) {
      conditions.push('c.name LIKE ?');
      queryParams.push(`%${name.trim()}%`);
    }

    if (category_title && typeof category_title === 'string' && category_title.trim()) {
      conditions.push('c.category_title LIKE ?');
      queryParams.push(`%${category_title.trim()}%`);
    }

    const whereClause = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';
    const [categories] = await pool.execute(`
      SELECT 
        c.id, 
        c.name, 
        c.category_title,
        c.created_at,
        COUNT(p.id) as post_count
      FROM categories c
      LEFT JOIN posts p ON c.id = p.category_id
      ${whereClause}
      GROUP BY c.id, c.name, c.category_title, c.created_at
      ORDER BY ${validSortField} ${validSortOrder}
    `, queryParams)

    success(res, categories, '获取成功');
  } catch (err) {
    console.error('获取分类列表失败:', err);
    error(res, '获取分类列表失败');
  }
});
module.exports = router;