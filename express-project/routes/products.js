const express = require('express');
const router = express.Router();
const { pool } = require('../config/config');
const { success, error, handleError } = require('../utils/responseHelper');
const { HTTP_STATUS, RESPONSE_CODES, PRODUCT_STATUS } = require('../constants');
const { optionalAuth, authenticateToken } = require('../middleware/auth');


const SORT_MAP = {
  latest: 'p.created_at DESC',
  sales: 'p.sales DESC',
  price_asc: 'p.price ASC',
  price_desc: 'p.price DESC'
};

/**
 * 递归查询某分类及其所有子分类 ID
 */
async function getCategoryWithChildren(categoryId) {
  const [rows] = await pool.execute(
    'SELECT id FROM shop_categories WHERE id = ? OR parent_id = ?',
    [categoryId, categoryId]
  );
  return rows.map(r => r.id);
}



/**
 * @api {get} /api/products 商品列表
 * @apiQuery {Number} page=1 页码
 * @apiQuery {Number} limit=20 每页数量
 * @apiQuery {String} keyword 搜索关键字
 * @apiQuery {Number} category_id 分类ID（含子分类）
 * @apiQuery {Number} min_price 价格下限
 * @apiQuery {Number} max_price 价格上限
 * @apiQuery {String} sort=latest 排序: latest/sales/price_asc/price_desc
 */
router.get('/', async (req, res) => {
  try {
    const page = Math.max(parseInt(req.query.page) || 1, 1);
    const limit = Math.min(Math.max(parseInt(req.query.limit) || 20, 1), 100);
    const offset = (page - 1) * limit;
    const { keyword, min_price, max_price } = req.query;
    const sort = SORT_MAP[req.query.sort] || SORT_MAP.latest;

    const where = ['p.status = ?', 'p.is_deleted = 0'];
    const params = [PRODUCT_STATUS.ON_SALE];

    if (keyword && keyword.trim()) {
      where.push('(p.title LIKE ? OR p.subtitle LIKE ? OR p.description LIKE ?)');
      const kw = `%${keyword.trim()}%`;
      params.push(kw, kw, kw);
    }

    if (req.query.category_id) {
      const ids = await getCategoryWithChildren(parseInt(req.query.category_id));
      if (ids.length === 0) {
        return success(res, { data: [], total: 0, page, limit, totalPages: 0 }, '获取成功');
      }
      const placeholders = ids.map(() => '?').join(',');
      where.push(`p.category_id IN (${placeholders})`);
      params.push(...ids);
    }

    if (min_price !== undefined && min_price !== '') {
      where.push('p.price >= ?');
      params.push(parseFloat(min_price));
    }
    if (max_price !== undefined && max_price !== '') {
      where.push('p.price <= ?');
      params.push(parseFloat(max_price));
    }

    const whereClause = 'WHERE ' + where.join(' AND ');

    const [rows] = await pool.execute(
      `SELECT p.id, p.title, p.subtitle, p.price, p.original_price, p.cover_image,
              p.sales, p.stock, p.category_id, c.name AS category_name, p.created_at
       FROM products p
       LEFT JOIN shop_categories c ON p.category_id = c.id
       ${whereClause}
       ORDER BY ${sort}
       LIMIT ? OFFSET ?`,
      [...params, String(limit), String(offset)]
    );

    const [[{ total }]] = await pool.execute(
      `SELECT COUNT(*) AS total FROM products p ${whereClause}`,
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
    handleError(err, res, '获取商品列表');
  }
});



/**
 * @api {get} /api/products/recommend 推荐商品
 * @apiQuery {String} type=hot 推荐类型: hot/related
 * @apiQuery {Number} limit=10 数量
 * @apiDescription hot=全站热销; related=基于登录用户浏览历史的分类推荐
 */
router.get('/recommend', optionalAuth, async (req, res) => {
  try {
    const limit = Math.min(Math.max(parseInt(req.query.limit) || 10, 1), 50);
    const type = req.query.type || 'hot';
    const userId = req.user?.id;

    const baseSelect = `SELECT p.id, p.title, p.subtitle, p.price, p.original_price,
                       p.cover_image, p.sales, p.category_id
                FROM products p
                WHERE p.status = ? AND p.is_deleted = 0 AND p.stock > 0`;

    let rows;
    if (type === 'related' && userId) {
      
      const [cats] = await pool.execute(
        `SELECT DISTINCT category_id FROM product_browse_logs
         WHERE user_id = ? ORDER BY browsed_at DESC LIMIT 3`,
        [userId]
      );
      if (cats.length === 0) {
        [rows] = await pool.execute(
          `${baseSelect} ORDER BY p.sales DESC LIMIT ?`,
          [PRODUCT_STATUS.ON_SALE, String(limit)]
        );
      } else {
        const ids = cats.map(c => c.category_id);
        const placeholders = ids.map(() => '?').join(',');
        [rows] = await pool.execute(
          `${baseSelect} AND p.category_id IN (${placeholders})
           ORDER BY p.sales DESC LIMIT ?`,
          [PRODUCT_STATUS.ON_SALE, ...ids, String(limit)]
        );
      }
    } else {
      [rows] = await pool.execute(
        `${baseSelect} ORDER BY p.sales DESC LIMIT ?`,
        [PRODUCT_STATUS.ON_SALE, String(limit)]
      );
    }

    success(res, rows, '获取成功');
  } catch (err) {
    handleError(err, res, '获取推荐商品');
  }
});



/**
 * @api {get} /api/products/:id 商品详情
 * @apiDescription 登录后返回 is_favorited 与 related 推荐商品；并异步记录浏览历史
 */
router.get('/:id', optionalAuth, async (req, res) => {
  try {
    const { id } = req.params;
    const [rows] = await pool.execute(
      `SELECT p.id, p.category_id, p.seller_id, p.title, p.subtitle, p.description,
              p.price, p.original_price, p.stock, p.sales, p.cover_image, p.status,
              p.created_at, c.name AS category_name
       FROM products p
       LEFT JOIN shop_categories c ON p.category_id = c.id
       WHERE p.id = ? AND p.is_deleted = 0`,
      [id]
    );

    if (rows.length === 0) {
      return error(res, '商品不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }

    const product = rows[0];

    
    const [images] = await pool.execute(
      'SELECT id, url, sort FROM product_images WHERE product_id = ? ORDER BY sort ASC',
      [id]
    );

    
    const [skus] = await pool.execute(
      'SELECT id, sku_code, spec, price, stock FROM product_skus WHERE product_id = ?',
      [id]
    );

    
    let isFavorited = false;
    if (req.user) {
      const [fav] = await pool.execute(
        'SELECT id FROM product_favorites WHERE user_id = ? AND product_id = ?',
        [req.user.id, id]
      );
      isFavorited = fav.length > 0;
    }

    
    const [related] = await pool.execute(
      `SELECT id, title, price, cover_image, sales
       FROM products
       WHERE category_id = ? AND id != ? AND status = ? AND is_deleted = 0 AND stock > 0
       ORDER BY sales DESC LIMIT ?`,
      [product.category_id, id, PRODUCT_STATUS.ON_SALE, String(6)]
    );

    if (req.user) {
      pool.execute(
        'INSERT INTO product_browse_logs (user_id, product_id, category_id) VALUES (?, ?, ?)',
        [req.user.id, id, product.category_id]
      ).catch(e => console.error('记录浏览历史失败:', e.message));
    }

    success(res, {
      ...product,
      images,
      skus,
      is_favorited: isFavorited,
      related
    }, '获取成功');
  } catch (err) {
    handleError(err, res, '获取商品详情');
  }
});

module.exports = router;
