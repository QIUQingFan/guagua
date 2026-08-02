/**
 * 管理端 - 商品管理路由
 * 挂载于 /api/admin/products，由 routes/admin.js 通过 router.use('/products', adminAuth, ...) 引入
 *
 * 提供能力：
 *  - GET    /            商品列表（搜索/分类/状态/价格筛选 + 分页）
 *  - GET    /:id         商品详情（含 images / skus）
 *  - POST   /            创建商品（事务写入 products → product_images → product_skus）
 *  - PUT    /:id         更新商品（事务更新主表 + 重建 images/skus）
 *  - DELETE /:id         软删除（is_deleted=1）
 *  - PATCH  /:id/status  上下架
 *  - PATCH  /:id/stock   调整库存（绝对值 / 增量）
 */
const express = require('express');
const router = express.Router();
const { pool } = require('../config/config');
const { success, error, handleError, validateRequired } = require('../utils/responseHelper');
const { HTTP_STATUS, RESPONSE_CODES, PRODUCT_STATUS, PRODUCT_STATUS_TEXT, SHOP_RESPONSE_CODES } = require('../constants');
const { isValidAmount } = require('../utils/amount');


const VALID_PRODUCT_STATUSES = Object.values(PRODUCT_STATUS);


const SORT_FIELD_MAP = {
  id: 'p.id',
  title: 'p.title',
  price: 'p.price',
  stock: 'p.stock',
  sales: 'p.sales',
  created_at: 'p.created_at'
};

/**
 * 校验商品状态合法性
 */
function isValidProductStatus(status) {
  return VALID_PRODUCT_STATUSES.includes(status);
}


router.get('/', async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit) || 20));
    const offset = (page - 1) * limit;

    const conditions = ['p.is_deleted = 0'];
    const params = [];

    if (req.query.keyword) {
      conditions.push('(p.title LIKE ? OR p.subtitle LIKE ?)');
      const kw = `%${String(req.query.keyword).trim()}%`;
      params.push(kw, kw);
    }
    if (req.query.category_id) {
      conditions.push('p.category_id = ?');
      params.push(String(req.query.category_id));
    }
    if (req.query.status && isValidProductStatus(req.query.status)) {
      conditions.push('p.status = ?');
      params.push(req.query.status);
    }
    if (req.query.min_price !== undefined && req.query.min_price !== '') {
      conditions.push('p.price >= ?');
      params.push(String(req.query.min_price));
    }
    if (req.query.max_price !== undefined && req.query.max_price !== '') {
      conditions.push('p.price <= ?');
      params.push(String(req.query.max_price));
    }

    const where = 'WHERE ' + conditions.join(' AND ');

    
    const sortField = SORT_FIELD_MAP[req.query.sortField] || 'p.created_at';
    const sortOrder = String(req.query.sortOrder).toLowerCase() === 'asc' ? 'ASC' : 'DESC';
    const orderClause = `ORDER BY ${sortField} ${sortOrder}`;

    const [[{ total }]] = await pool.execute(
      `SELECT COUNT(*) AS total FROM products p ${where}`,
      params
    );

    const [rows] = await pool.execute(
      `SELECT p.id, p.title, p.subtitle, p.price, p.original_price, p.stock, p.sales,
              p.cover_image, p.status, p.category_id, c.name AS category_name, p.created_at
       FROM products p
       LEFT JOIN shop_categories c ON p.category_id = c.id
       ${where}
       ${orderClause}
       LIMIT ? OFFSET ?`,
      [...params, String(limit), String(offset)]
    );

    success(res, {
      data: rows,
      pagination: { page, limit, total, pages: Math.ceil(total / limit) }
    }, '获取成功');
  } catch (err) {
    handleError(err, res, '获取商品列表');
  }
});


router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const [rows] = await pool.execute(
      `SELECT p.id, p.title, p.subtitle, p.description, p.price, p.original_price, p.stock, p.sales,
              p.cover_image, p.status, p.category_id, c.name AS category_name, p.seller_id, p.created_at, p.updated_at
       FROM products p
       LEFT JOIN shop_categories c ON p.category_id = c.id
       WHERE p.id = ? AND p.is_deleted = 0`,
      [String(id)]
    );
    if (rows.length === 0) {
      return error(res, '商品不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }
    const product = rows[0];

    const [images] = await pool.execute(
      'SELECT id, url, sort FROM product_images WHERE product_id = ? ORDER BY sort ASC, id ASC',
      [String(id)]
    );
    const [skus] = await pool.execute(
      'SELECT id, sku_code, spec, price, stock FROM product_skus WHERE product_id = ? ORDER BY id ASC',
      [String(id)]
    );

    product.images = images.map(i => i.url);
    product.image_objects = images;
    product.skus = skus;
    success(res, product, '获取成功');
  } catch (err) {
    handleError(err, res, '获取商品详情');
  }
});


router.post('/', async (req, res) => {
  const conn = await pool.getConnection();
  try {
    const body = req.body || {};
    const check = validateRequired(body, ['title', 'category_id', 'price', 'stock']);
    if (!check.isValid) {
      return error(res, check.message, RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }

    const title = String(body.title).trim();
    if (title.length > 128) {
      return error(res, '商品标题过长（最多128字）', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }
    if (!isValidAmount(body.price)) {
      return error(res, '商品价格非法', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }
    const stock = parseInt(body.stock);
    if (!Number.isFinite(stock) || stock < 0) {
      return error(res, '库存数量非法', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }

    
    const [cat] = await conn.execute(
      'SELECT id FROM shop_categories WHERE id = ?',
      [String(body.category_id)]
    );
    if (cat.length === 0) {
      return error(res, '所选分类不存在', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }

    
    const status = body.status && isValidProductStatus(body.status) ? body.status : PRODUCT_STATUS.DRAFT;
    const originalPrice = (body.original_price !== undefined && body.original_price !== null && isValidAmount(body.original_price))
      ? body.original_price : null;

    await conn.beginTransaction();

    const [result] = await conn.execute(
      `INSERT INTO products (category_id, seller_id, title, subtitle, description, price, original_price, stock, cover_image, status)
       VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [String(body.category_id), title, body.subtitle || null, body.description || null,
      String(body.price), originalPrice, stock, body.cover_image || null, status]
    );
    const productId = result.insertId;

    
    const images = Array.isArray(body.images) ? body.images.filter(u => u && typeof u === 'string') : [];
    for (let i = 0; i < images.length; i++) {
      await conn.execute(
        'INSERT INTO product_images (product_id, url, sort) VALUES (?, ?, ?)',
        [String(productId), images[i], i]
      );
    }

    
    const skus = Array.isArray(body.skus) ? body.skus : [];
    for (const s of skus) {
      if (!s || !s.spec || !isValidAmount(s.price)) continue;
      const skuStock = parseInt(s.stock);
      await conn.execute(
        'INSERT INTO product_skus (product_id, sku_code, spec, price, stock) VALUES (?, ?, ?, ?, ?)',
        [String(productId), s.sku_code || null, String(s.spec), String(s.price), Number.isFinite(skuStock) ? skuStock : 0]
      );
    }

    await conn.commit();
    success(res, { id: productId }, '商品创建成功', HTTP_STATUS.CREATED);
  } catch (err) {
    await conn.rollback();
    handleError(err, res, '创建商品');
  } finally {
    conn.release();
  }
});


router.put('/:id', async (req, res) => {
  const conn = await pool.getConnection();
  try {
    const { id } = req.params;
    const body = req.body || {};

    const [exist] = await conn.execute(
      'SELECT id FROM products WHERE id = ? AND is_deleted = 0', [String(id)]
    );
    if (exist.length === 0) {
      return error(res, '商品不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }

    
    if (body.category_id !== undefined) {
      const [cat] = await conn.execute('SELECT id FROM shop_categories WHERE id = ?', [String(body.category_id)]);
      if (cat.length === 0) {
        return error(res, '所选分类不存在', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
      }
    }
    if (body.price !== undefined && !isValidAmount(body.price)) {
      return error(res, '商品价格非法', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }
    if (body.status !== undefined && !isValidProductStatus(body.status)) {
      return error(res, '商品状态非法', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }

    await conn.beginTransaction();

    
    const fields = ['title', 'subtitle', 'description', 'price', 'original_price', 'stock', 'cover_image', 'status', 'category_id'];
    const sets = [];
    const vals = [];
    for (const f of fields) {
      if (body[f] !== undefined) {
        sets.push(`${f} = ?`);
        vals.push(body[f]);
      }
    }
    if (sets.length > 0) {
      vals.push(String(id));
      await conn.execute(`UPDATE products SET ${sets.join(', ')} WHERE id = ?`, vals);
    }

    
    if (Array.isArray(body.images)) {
      await conn.execute('DELETE FROM product_images WHERE product_id = ?', [String(id)]);
      const images = body.images.filter(u => u && typeof u === 'string');
      for (let i = 0; i < images.length; i++) {
        await conn.execute(
          'INSERT INTO product_images (product_id, url, sort) VALUES (?, ?, ?)',
          [String(id), images[i], i]
        );
      }
    }

    
    if (Array.isArray(body.skus)) {
      await conn.execute('DELETE FROM product_skus WHERE product_id = ?', [String(id)]);
      for (const s of body.skus) {
        if (!s || !s.spec || !isValidAmount(s.price)) continue;
        const skuStock = parseInt(s.stock);
        await conn.execute(
          'INSERT INTO product_skus (product_id, sku_code, spec, price, stock) VALUES (?, ?, ?, ?, ?)',
          [String(id), s.sku_code || null, String(s.spec), String(s.price), Number.isFinite(skuStock) ? skuStock : 0]
        );
      }
    }

    await conn.commit();
    success(res, { id: Number(id) }, '商品更新成功');
  } catch (err) {
    await conn.rollback();
    handleError(err, res, '更新商品');
  } finally {
    conn.release();
  }
});


router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const [r] = await pool.execute(
      'UPDATE products SET is_deleted = 1 WHERE id = ? AND is_deleted = 0',
      [String(id)]
    );
    if (r.affectedRows === 0) {
      return error(res, '商品不存在或已删除', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }
    success(res, null, '商品删除成功');
  } catch (err) {
    handleError(err, res, '删除商品');
  }
});


router.patch('/:id/status', async (req, res) => {
  try {
    const { id } = req.params;
    const { status } = req.body || {};
    if (!status || !isValidProductStatus(status)) {
      return error(res, '商品状态非法', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }
    const [r] = await pool.execute(
      'UPDATE products SET status = ? WHERE id = ? AND is_deleted = 0',
      [status, String(id)]
    );
    if (r.affectedRows === 0) {
      return error(res, '商品不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }
    success(res, { id: Number(id), status, status_text: PRODUCT_STATUS_TEXT[status] }, '状态更新成功');
  } catch (err) {
    handleError(err, res, '更新商品状态');
  }
});


router.patch('/:id/stock', async (req, res) => {
  try {
    const { id } = req.params;
    const { stock, delta } = req.body || {};

    
    let newStock;
    if (stock !== undefined) {
      newStock = parseInt(stock);
      if (!Number.isFinite(newStock) || newStock < 0) {
        return error(res, '库存数量非法', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
      }
      const [r] = await pool.execute(
        'UPDATE products SET stock = ? WHERE id = ? AND is_deleted = 0',
        [newStock, String(id)]
      );
      if (r.affectedRows === 0) {
        return error(res, '商品不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
      }
    } else if (delta !== undefined) {
      const d = parseInt(delta);
      if (!Number.isFinite(d)) {
        return error(res, '库存增量非法', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
      }
      
      const [r] = await pool.execute(
        'UPDATE products SET stock = GREATEST(stock + ?, 0) WHERE id = ? AND is_deleted = 0',
        [d, String(id)]
      );
      if (r.affectedRows === 0) {
        return error(res, '商品不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
      }
      const [[row]] = await pool.execute('SELECT stock FROM products WHERE id = ?', [String(id)]);
      newStock = row ? row.stock : 0;
    } else {
      return error(res, '请提供 stock 或 delta 参数', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }

    success(res, { id: Number(id), stock: newStock }, '库存更新成功');
  } catch (err) {
    handleError(err, res, '更新商品库存');
  }
});

module.exports = router;
