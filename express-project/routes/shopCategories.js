const express = require('express');
const router = express.Router();
const { pool } = require('../config/config');
const { success, error, handleError } = require('../utils/responseHelper');
const { HTTP_STATUS, RESPONSE_CODES } = require('../constants');
const { createCrudHandlers } = require('../middleware/crudFactory');
const { adminAuth } = require('../utils/uploadHelper');



router.get('/', async (req, res) => {
  try {
    const flat = String(req.query.flat) === '1';
    const [rows] = await pool.execute(
      `SELECT id, name, parent_id, sort, icon, is_active
       FROM shop_categories
       WHERE is_active = 1
       ORDER BY sort DESC, id ASC`
    );

    if (flat) {
      return success(res, rows, '获取成功');
    }


    const map = {};
    const tree = [];
    rows.forEach(item => {
      map[item.id] = { ...item, children: [] };
    });
    rows.forEach(item => {
      if (item.parent_id && map[item.parent_id]) {
        map[item.parent_id].children.push(map[item.id]);
      } else {
        tree.push(map[item.id]);
      }
    });

    const cleanTree = (nodes) => {
      nodes.forEach(n => {
        if (n.children.length === 0) delete n.children;
        else cleanTree(n.children);
      });
    };
    cleanTree(tree);

    success(res, tree, '获取成功');
  } catch (err) {
    handleError(err, res, '获取商城分类');
  }
});

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const [rows] = await pool.execute(
      'SELECT id, name, parent_id, sort, icon, is_active FROM shop_categories WHERE id = ?',
      [id]
    );
    if (rows.length === 0) {
      return error(res, '分类不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }
    success(res, rows[0], '获取成功');
  } catch (err) {
    handleError(err, res, '获取商城分类详情');
  }
});




const categoryCrud = createCrudHandlers({
  table: 'shop_categories',
  name: '商城分类',
  requiredFields: ['name'],
  updateFields: ['name', 'parent_id', 'sort', 'icon', 'is_active'],
  searchFields: {
    name: { operator: 'LIKE' },
    parent_id: { operator: '=', transform: v => parseInt(v) },
    is_active: { operator: '=', transform: v => parseInt(v) }
  },
  defaultOrderBy: 'sort DESC, id ASC',
  beforeDelete: async (id) => {

    const [children] = await pool.execute(
      'SELECT id FROM shop_categories WHERE parent_id = ? LIMIT 1', [id]
    );
    if (children.length > 0) {
      return { isValid: false, message: '该分类下有子分类，无法删除' };
    }

    const [products] = await pool.execute(
      'SELECT id FROM products WHERE category_id = ? AND is_deleted = 0 LIMIT 1', [id]
    );
    if (products.length > 0) {
      return { isValid: false, message: '该分类下有商品，无法删除' };
    }
    return { isValid: true };
  }
});


router.get('/admin/list', adminAuth, async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;
    const offset = (page - 1) * limit;
    const conditions = [];
    const params = [];

    if (req.query.name) {
      conditions.push('name LIKE ?');
      params.push(`%${req.query.name.trim()}%`);
    }
    if (req.query.is_active !== undefined && req.query.is_active !== '') {
      conditions.push('is_active = ?');
      params.push(parseInt(req.query.is_active));
    }
    const where = conditions.length ? 'WHERE ' + conditions.join(' AND ') : '';

    const [rows] = await pool.execute(
      `SELECT id, name, parent_id, sort, icon, is_active, created_at
       FROM shop_categories ${where}
       ORDER BY sort DESC, id ASC LIMIT ? OFFSET ?`,
      [...params, String(limit), String(offset)]
    );
    const [[{ total }]] = await pool.execute(
      `SELECT COUNT(*) AS total FROM shop_categories ${where}`, params
    );
    success(res, { data: rows, total, page, limit, totalPages: Math.ceil(total / limit) }, '获取成功');
  } catch (err) {
    handleError(err, res, '获取商城分类列表');
  }
});

router.post('/', adminAuth, categoryCrud.create);
router.put('/:id', adminAuth, categoryCrud.update);
router.delete('/:id', adminAuth, categoryCrud.deleteOne);

module.exports = router;
