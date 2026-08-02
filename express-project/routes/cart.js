const express = require('express');
const router = express.Router();
const { pool } = require('../config/config');
const { success, error, handleError, validateRequired } = require('../utils/responseHelper');
const { HTTP_STATUS, RESPONSE_CODES, PRODUCT_STATUS, SHOP_RESPONSE_CODES, CART_MAX_QUANTITY } = require('../constants');
const { authenticateToken } = require('../middleware/auth');


router.use(authenticateToken);

/**
 * 计算购物车概要 + 失效项
 * @param {Array} rows 购物车行（含 product 字段）
 */
function buildSummary(rows) {
    let selectedCount = 0;
    let selectedQuantity = 0;
    let selectedAmount = 0;
    let totalQuantity = 0;
    const invalidItems = [];

    rows.forEach(r => {
        const qty = Number(r.quantity);
        totalQuantity += qty;
        const product = r.product || {};
        const invalid = !product.id
            || product.is_deleted
            || product.status !== PRODUCT_STATUS.ON_SALE
            || Number(product.stock) < qty;

        if (invalid) {
            let reason = '商品已失效';
            if (product.id && product.is_deleted) reason = '商品已删除';
            else if (product.id && product.status !== PRODUCT_STATUS.ON_SALE) reason = '商品已下架';
            else if (product.id && Number(product.stock) < qty) reason = '库存不足';
            invalidItems.push({
                id: r.id,
                product_id: r.product_id,
                reason
            });
        }

        if (Number(r.is_selected) === 1 && !invalid) {
            selectedCount += 1;
            selectedQuantity += qty;
            selectedAmount += Number(product.price) * qty;
        }
    });

    return {
        selected_count: selectedCount,
        selected_quantity: selectedQuantity,
        selected_amount: selectedAmount.toFixed(2),
        total_quantity: totalQuantity
    };
}



/**
 * @api {get} /api/cart 购物车列表（含合计与失效项）
 */
router.get('/', async (req, res) => {
    try {
        const userId = req.user.id;
        const [rows] = await pool.execute(
            `SELECT c.id, c.product_id, c.sku_id, c.quantity, c.is_selected, c.created_at,
                    p.title, p.cover_image, p.price, p.stock, p.status, p.is_deleted,
                    s.spec, s.price AS sku_price, s.stock AS sku_stock
             FROM cart_items c
             LEFT JOIN products p ON c.product_id = p.id
             LEFT JOIN product_skus s ON c.sku_id = s.id
             WHERE c.user_id = ?
             ORDER BY c.created_at DESC`,
            [userId]
        );

        
        const items = rows.map(r => ({
            id: r.id,
            product_id: r.product_id,
            sku_id: r.sku_id,
            quantity: r.quantity,
            is_selected: r.is_selected,
            created_at: r.created_at,
            product: {
                id: r.product_id,
                title: r.title,
                cover_image: r.cover_image,
                price: r.sku_id ? r.sku_price : r.price,
                stock: r.sku_id ? r.sku_stock : r.stock,
                status: r.status,
                is_deleted: r.is_deleted,
                spec: r.spec || null
            }
        }));

        const summary = buildSummary(items);

        success(res, { items, summary, invalid_items: summary.invalid_items || [] }, '获取成功');
    } catch (err) {
        handleError(err, res, '获取购物车');
    }
});



/**
 * @api {post} /api/cart 加入购物车
 * @apiBody {Number} product_id 商品ID
 * @apiBody {Number} [sku_id] SKU ID
 * @apiBody {Number} [quantity=1] 数量
 */
router.post('/', async (req, res) => {
    try {
        const userId = req.user.id;
        const { product_id, sku_id = null, quantity = 1 } = req.body;

        const v = validateRequired({ product_id }, ['product_id']);
        if (!v.isValid) {
            return error(res, v.message, RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
        }

        const qty = parseInt(quantity);
        if (!qty || qty < 1) {
            return error(res, '数量必须为正整数', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
        }

        
        const [products] = await pool.execute(
            'SELECT id, title, status, stock, is_deleted FROM products WHERE id = ?',
            [product_id]
        );
        if (products.length === 0 || products[0].is_deleted) {
            return error(res, '商品不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
        }
        const product = products[0];
        if (product.status !== PRODUCT_STATUS.ON_SALE) {
            return error(res, '商品已下架', SHOP_RESPONSE_CODES.PRODUCT_OFF_SHELF, HTTP_STATUS.CONFLICT);
        }

        
        let availableStock = Number(product.stock);
        if (sku_id) {
            const [skus] = await pool.execute(
                'SELECT id, stock FROM product_skus WHERE id = ? AND product_id = ?',
                [sku_id, product_id]
            );
            if (skus.length === 0) {
                return error(res, '商品规格不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
            }
            availableStock = Number(skus[0].stock);
        }
        if (availableStock < qty) {
            return error(res, '库存不足', SHOP_RESPONSE_CODES.OUT_OF_STOCK, HTTP_STATUS.CONFLICT);
        }

        const [exist] = await pool.execute(
            'SELECT id, quantity FROM cart_items WHERE user_id = ? AND product_id = ? AND ' +
            '(sku_id <=> ?)',
            [userId, product_id, sku_id]
        );

        if (exist.length > 0) {
            const newQty = exist[0].quantity + qty;
            if (newQty > CART_MAX_QUANTITY) {
                return error(res, `单个商品数量不能超过${CART_MAX_QUANTITY}件`, SHOP_RESPONSE_CODES.CART_ITEM_LIMIT, HTTP_STATUS.CONFLICT);
            }
            if (newQty > availableStock) {
                return error(res, '库存不足', SHOP_RESPONSE_CODES.OUT_OF_STOCK, HTTP_STATUS.CONFLICT);
            }
            await pool.execute(
                'UPDATE cart_items SET quantity = ? WHERE id = ?',
                [newQty, exist[0].id]
            );
            return success(res, { id: exist[0].id, quantity: newQty }, '已加入购物车');
        }

        const [result] = await pool.execute(
            'INSERT INTO cart_items (user_id, product_id, sku_id, quantity, is_selected) VALUES (?, ?, ?, ?, 1)',
            [userId, product_id, sku_id, qty]
        );

        success(res, { id: result.insertId, quantity: qty }, '已加入购物车');
    } catch (err) {
        handleError(err, res, '加入购物车');
    }
});


/**
 * @api {put} /api/cart/select-all 全选/取消全选
 * @apiBody {Number} is_selected 1/0
 */
router.put('/select-all', async (req, res) => {
    try {
        const userId = req.user.id;
        const { is_selected } = req.body;
        await pool.execute(
            'UPDATE cart_items SET is_selected = ? WHERE user_id = ?',
            [is_selected ? 1 : 0, userId]
        );
        success(res, null, '操作成功');
    } catch (err) {
        handleError(err, res, '更新全选状态');
    }
});



/**
 * @api {put} /api/cart/:id 修改数量/勾选
 * @apiBody {Number} [quantity] 数量
 * @apiBody {Number} [is_selected] 勾选 1/0
 */
router.put('/:id', async (req, res) => {
    try {
        const userId = req.user.id;
        const cartId = parseInt(req.params.id);
        const { quantity, is_selected } = req.body;

        
        const [rows] = await pool.execute(
            'SELECT id, product_id, sku_id FROM cart_items WHERE id = ? AND user_id = ?',
            [cartId, userId]
        );
        if (rows.length === 0) {
            return error(res, '购物车项不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
        }

        const updates = [];
        const params = [];

        if (quantity !== undefined) {
            const qty = parseInt(quantity);
            if (!qty || qty < 1) {
                return error(res, '数量必须为正整数', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
            }
            if (qty > CART_MAX_QUANTITY) {
                return error(res, `单个商品数量不能超过${CART_MAX_QUANTITY}件`, SHOP_RESPONSE_CODES.CART_ITEM_LIMIT, HTTP_STATUS.CONFLICT);
            }
            
            const item = rows[0];
            if (item.sku_id) {
                const [skus] = await pool.execute('SELECT stock FROM product_skus WHERE id = ?', [item.sku_id]);
                if (skus.length && Number(skus[0].stock) < qty) {
                    return error(res, '库存不足', SHOP_RESPONSE_CODES.OUT_OF_STOCK, HTTP_STATUS.CONFLICT);
                }
            } else {
                const [p] = await pool.execute('SELECT stock FROM products WHERE id = ?', [item.product_id]);
                if (p.length && Number(p[0].stock) < qty) {
                    return error(res, '库存不足', SHOP_RESPONSE_CODES.OUT_OF_STOCK, HTTP_STATUS.CONFLICT);
                }
            }
            updates.push('quantity = ?');
            params.push(qty);
        }

        if (is_selected !== undefined) {
            updates.push('is_selected = ?');
            params.push(is_selected ? 1 : 0);
        }

        if (updates.length === 0) {
            return error(res, '没有需要更新的字段', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
        }

        params.push(cartId, userId);
        await pool.execute(
            `UPDATE cart_items SET ${updates.join(', ')} WHERE id = ? AND user_id = ?`,
            params
        );

        success(res, { id: cartId }, '更新成功');
    } catch (err) {
        handleError(err, res, '更新购物车');
    }
});



/**
 * @api {delete} /api/cart/:id 删除购物车单项
 */
router.delete('/:id', async (req, res) => {
    try {
        const userId = req.user.id;
        const cartId = parseInt(req.params.id);
        const [result] = await pool.execute(
            'DELETE FROM cart_items WHERE id = ? AND user_id = ?',
            [cartId, userId]
        );
        if (result.affectedRows === 0) {
            return error(res, '购物车项不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
        }
        success(res, null, '删除成功');
    } catch (err) {
        handleError(err, res, '删除购物车项');
    }
});



/**
 * @api {delete} /api/cart 批量删除或清空
 * @apiBody {Number[]} [ids] 购物车项ID数组，不传则清空
 */
router.delete('/', async (req, res) => {
    try {
        const userId = req.user.id;
        const { ids } = req.body || {};

        if (ids && Array.isArray(ids) && ids.length > 0) {
            const placeholders = ids.map(() => '?').join(',');
            await pool.execute(
                `DELETE FROM cart_items WHERE user_id = ? AND id IN (${placeholders})`,
                [userId, ...ids]
            );
        } else {
            await pool.execute('DELETE FROM cart_items WHERE user_id = ?', [userId]);
        }
        success(res, null, '删除成功');
    } catch (err) {
        handleError(err, res, '清空购物车');
    }
});

module.exports = router;