const express = require('express');
const router = express.Router();
const { pool } = require('../config/config');
const { success, error, handleError } = require('../utils/responseHelper');
const { HTTP_STATUS, RESPONSE_CODES, PRODUCT_STATUS } = require('../constants');
const { authenticateToken } = require('../middleware/auth');


router.use(authenticateToken);



/**
 * @api {get} /api/product-favorites 我的收藏列表
 * @apiQuery {Number} page=1 页码
 * @apiQuery {Number} limit=20 每页数量
 * @apiDescription 返回当前用户收藏的商品列表（仅返回在售/已下架商品，不含已删除商品）
 */
router.get('/', async (req, res) => {
  try {
    const userId = req.user.id;
    const page = Math.max(parseInt(req.query.page) || 1, 1);
    const limit = Math.min(Math.max(parseInt(req.query.limit) || 20, 1), 100);
    const offset = (page - 1) * limit;

    const where = 'WHERE f.user_id = ? AND p.is_deleted = 0';
    const params = [userId];

    const [rows] = await pool.execute(
      `SELECT p.id, p.title, p.subtitle, p.price, p.original_price, p.cover_image,
              p.sales, p.stock, p.status, p.category_id, c.name AS category_name,
              f.created_at AS favorited_at
       FROM product_favorites f
       INNER JOIN products p ON f.product_id = p.id
       LEFT JOIN shop_categories c ON p.category_id = c.id
       ${where}
       ORDER BY f.created_at DESC
       LIMIT ? OFFSET ?`,
      [...params, String(limit), String(offset)]
    );

    const [[{ total }]] = await pool.execute(
      `SELECT COUNT(*) AS total
       FROM product_favorites f
       INNER JOIN products p ON f.product_id = p.id
       ${where}`,
      params
    );

    success(res, {
      data: rows,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit)
    }, '获取成功');
  } catch (err) {
    handleError(err, res, '获取收藏列表');
  }
});



/**
 * @api {post} /api/product-favorites/:productId 收藏商品
 * @apiDescription 重复收藏幂等返回成功；商品不存在或已删除返回 404
 */
router.post('/:productId', async (req, res) => {
  try {
    const userId = req.user.id;
    const productId = parseInt(req.params.productId);
    if (!productId) {
      return error(res, '商品ID无效', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }

    
    const [products] = await pool.execute(
      'SELECT id FROM products WHERE id = ? AND is_deleted = 0',
      [productId]
    );
    if (products.length === 0) {
      return error(res, '商品不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }

    
    await pool.execute(
      'INSERT IGNORE INTO product_favorites (user_id, product_id) VALUES (?, ?)',
      [userId, productId]
    );

    success(res, { product_id: productId, is_favorited: true }, '收藏成功');
  } catch (err) {
    handleError(err, res, '收藏商品');
  }
});



/**
 * @api {delete} /api/product-favorites/:productId 取消收藏
 * @apiDescription 未收藏时幂等返回成功
 */
router.delete('/:productId', async (req, res) => {
  try {
    const userId = req.user.id;
    const productId = parseInt(req.params.productId);
    if (!productId) {
      return error(res, '商品ID无效', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }

    await pool.execute(
      'DELETE FROM product_favorites WHERE user_id = ? AND product_id = ?',
      [userId, productId]
    );

    success(res, { product_id: productId, is_favorited: false }, '取消收藏成功');
  } catch (err) {
    handleError(err, res, '取消收藏');
  }
});

module.exports = router;
