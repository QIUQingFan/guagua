const express = require('express');
const router = express.Router();
const { pool } = require('../config/config');
const { success, error, handleError, validateRequired } = require('../utils/responseHelper');
const { HTTP_STATUS, RESPONSE_CODES, ORDER_STATUS, OPERATOR_TYPE, PRODUCT_STATUS, SHOP_RESPONSE_CODES } = require('../constants');
const { authenticateToken } = require('../middleware/auth');
const { generateOrderNo, isValidOrderNo } = require('../utils/orderNo');
const { canTransition, getStatusText } = require('../utils/orderStatus');
const { calcSubtotal, calcTotal, calcPayAmount } = require('../utils/amount');


router.use(authenticateToken);

/**
 * 根据参数解析订单：纯数字按 id 查，否则按 order_no 查
 * @param {string} idOrNo
 * @param {number} userId
 * @param {Object} conn 可选连接
 * @returns {Promise<Object|null>}
 */
async function findOrder(idOrNo, userId, conn = pool) {
    const isNumeric = /^\d+$/.test(String(idOrNo));
    const sql = isNumeric
        ? `SELECT * FROM orders WHERE id = ? AND user_id = ? AND is_deleted = 0`
        : `SELECT * FROM orders WHERE order_no = ? AND user_id = ? AND is_deleted = 0`;
    const [rows] = await conn.execute(sql, [idOrNo, userId]);
    return rows.length > 0 ? rows[0] : null;
}



/**
 * @api {post} /api/orders 下单
 * @apiBody {Array} items [{ product_id, sku_id?, quantity }]
 * @apiBody {Number} address_id 收货地址ID
 * @apiBody {String} [remark] 备注
 * @apiBody {Boolean} [from_cart] 是否来自购物车
 */
router.post('/', async (req, res) => {
    const conn = await pool.getConnection();
    try {
        const userId = req.user.id;
        const { items, address_id, remark, from_cart } = req.body;

        if (!Array.isArray(items) || items.length === 0) {
            return error(res, '商品列表不能为空', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
        }
        if (!address_id) {
            return error(res, '请选择收货地址', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
        }

        await conn.beginTransaction();

        
        const [addrRows] = await conn.execute(
            'SELECT id, receiver, phone, province, city, district, detail FROM addresses WHERE id = ? AND user_id = ?',
            [address_id, userId]
        );
        if (addrRows.length === 0) {
            await conn.rollback();
            return error(res, '收货地址不存在或不属于当前用户', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
        }
        const address = addrRows[0];

        
        const subtotals = [];
        const orderItems = [];
        const stockOps = [];

        for (const item of items) {
            const { product_id, sku_id = null, quantity } = item;
            if (!product_id || !quantity || quantity < 1) {
                await conn.rollback();
                return error(res, '商品参数错误', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
            }
            const qty = parseInt(quantity);

            
            const [pRows] = await conn.execute(
                `SELECT id, title, cover_image, price, stock, status, is_deleted
                 FROM products WHERE id = ? FOR UPDATE`,
                [product_id]
            );
            if (pRows.length === 0 || pRows[0].is_deleted) {
                await conn.rollback();
                return error(res, `商品 ${product_id} 不存在`, RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
            }
            const product = pRows[0];
            if (product.status !== PRODUCT_STATUS.ON_SALE) {
                await conn.rollback();
                return error(res, `商品「${product.title}」已下架`, SHOP_RESPONSE_CODES.PRODUCT_OFF_SHELF, HTTP_STATUS.CONFLICT);
            }

            let unitPrice = Number(product.price);
            let spec = null;
            let availableStock = Number(product.stock);

            if (sku_id) {
                const [sRows] = await conn.execute(
                    'SELECT id, spec, price, stock FROM product_skus WHERE id = ? AND product_id = ? FOR UPDATE',
                    [sku_id, product_id]
                );
                if (sRows.length === 0) {
                    await conn.rollback();
                    return error(res, `商品「${product.title}」规格不存在`, RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
                }
                const sku = sRows[0];
                unitPrice = Number(sku.price);
                spec = sku.spec;
                availableStock = Number(sku.stock);
            }

            if (availableStock < qty) {
                await conn.rollback();
                return error(res, `商品「${product.title}」库存不足`, SHOP_RESPONSE_CODES.OUT_OF_STOCK, HTTP_STATUS.CONFLICT);
            }

            const subtotal = calcSubtotal(unitPrice, qty);
            subtotals.push(subtotal);
            orderItems.push([
                product_id,
                sku_id,
                product.title,
                product.cover_image,
                spec,
                unitPrice.toFixed(2),
                qty,
                subtotal
            ]);
            stockOps.push({ product_id, sku_id, quantity: qty });
        }

        
        const totalAmount = calcTotal(subtotals);
        const shippingFee = '0.00'; 
        const payAmount = calcPayAmount(totalAmount, shippingFee);
        const orderNo = generateOrderNo();

        
        const fullAddress = `${address.province}${address.city}${address.district}${address.detail}`;
        const [orderResult] = await conn.execute(
            `INSERT INTO orders
             (order_no, user_id, status, total_amount, shipping_fee, pay_amount,
              receiver, phone, address, remark)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [orderNo, userId, ORDER_STATUS.PENDING_PAYMENT, totalAmount, shippingFee, payAmount,
                address.receiver, address.phone, fullAddress, remark || null]
        );
        const orderId = orderResult.insertId;

        
        for (const oi of orderItems) {
            await conn.execute(
                `INSERT INTO order_items
                 (order_id, product_id, sku_id, product_title, product_image, spec, unit_price, quantity, subtotal)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [orderId, ...oi]
            );
        }

        
        for (const op of stockOps) {
            if (op.sku_id) {
                const [r] = await conn.execute(
                    'UPDATE product_skus SET stock = stock - ? WHERE id = ? AND stock >= ?',
                    [op.quantity, op.sku_id, op.quantity]
                );
                if (r.affectedRows === 0) {
                    await conn.rollback();
                    return error(res, '库存扣减失败（并发冲突）', SHOP_RESPONSE_CODES.OUT_OF_STOCK, HTTP_STATUS.CONFLICT);
                }
            }
            const [r2] = await conn.execute(
                'UPDATE products SET stock = stock - ?, sales = sales + ? WHERE id = ? AND stock >= ?',
                [op.quantity, op.quantity, op.product_id, op.quantity]
            );
            if (r2.affectedRows === 0) {
                await conn.rollback();
                return error(res, '库存扣减失败（并发冲突）', SHOP_RESPONSE_CODES.OUT_OF_STOCK, HTTP_STATUS.CONFLICT);
            }
        }

        
        await conn.execute(
            `INSERT INTO order_status_logs (order_id, from_status, to_status, operator_id, operator_type, remark)
             VALUES (?, NULL, ?, ?, 'user', '下单')`,
            [orderId, ORDER_STATUS.PENDING_PAYMENT, userId]
        );

        
        if (from_cart) {
            for (const op of stockOps) {
                await conn.execute(
                    'DELETE FROM cart_items WHERE user_id = ? AND product_id = ? AND (sku_id <=> ?)',
                    [userId, op.product_id, op.sku_id]
                );
            }
        }

        await conn.commit();

        success(res, { order_no: orderNo, order_id: orderId, pay_amount: payAmount }, '下单成功');
    } catch (err) {
        await conn.rollback();
        handleError(err, res, '下单失败');
    } finally {
        conn.release();
    }
});



/**
 * @api {get} /api/orders 我的订单列表
 * @apiQuery {Number} [page=1]
 * @apiQuery {Number} [limit=20]
 * @apiQuery {String} [status] 多值逗号分隔
 */
router.get('/', async (req, res) => {
    try {
        const userId = req.user.id;
        const page = Math.max(parseInt(req.query.page) || 1, 1);
        const limit = Math.min(Math.max(parseInt(req.query.limit) || 20, 1), 100);
        const offset = (page - 1) * limit;

        const where = ['o.user_id = ?', 'o.is_deleted = 0'];
        const params = [userId];

        if (req.query.status) {
            const statuses = String(req.query.status).split(',').map(s => s.trim()).filter(Boolean);
            if (statuses.length > 0) {
                const placeholders = statuses.map(() => '?').join(',');
                where.push(`o.status IN (${placeholders})`);
                params.push(...statuses);
            }
        }

        const whereClause = 'WHERE ' + where.join(' AND ');

        const [rows] = await pool.execute(
            `SELECT o.id, o.order_no, o.status, o.total_amount, o.pay_amount,
                    o.created_at, o.completed_at
             FROM orders o
             ${whereClause}
             ORDER BY o.created_at DESC
             LIMIT ? OFFSET ?`,
            [...params, String(limit), String(offset)]
        );

        
        let list = [];
        if (rows.length > 0) {
            const orderIds = rows.map(r => r.id);
            const placeholders = orderIds.map(() => '?').join(',');
            const [itemRows] = await pool.execute(
                `SELECT order_id, product_id, product_title, product_image, spec, quantity, unit_price
                 FROM order_items WHERE order_id IN (${placeholders})`,
                orderIds
            );
            const itemMap = {};
            itemRows.forEach(i => {
                if (!itemMap[i.order_id]) itemMap[i.order_id] = [];
                itemMap[i.order_id].push(i);
            });
            list = rows.map(r => ({
                ...r,
                status_text: getStatusText(r.status),
                total_quantity: (itemMap[r.id] || []).reduce((s, i) => s + Number(i.quantity), 0),
                items: itemMap[r.id] || []
            }));
        }

        const [[{ total }]] = await pool.execute(
            `SELECT COUNT(*) AS total FROM orders o ${whereClause}`,
            params
        );

        success(res, {
            data: list,
            total,
            page,
            limit,
            totalPages: Math.ceil(total / limit)
        }, '获取成功');
    } catch (err) {
        handleError(err, res, '获取订单列表');
    }
});



/**
 * @api {get} /api/orders/:idOrNo 订单详情（支持 id 或 order_no）
 */
router.get('/:idOrNo', async (req, res) => {
    try {
        const userId = req.user.id;
        const order = await findOrder(req.params.idOrNo, userId);
        if (!order) {
            return error(res, '订单不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
        }

        const [items] = await pool.execute(
            `SELECT id, product_id, sku_id, product_title, product_image, spec, unit_price, quantity, subtotal
             FROM order_items WHERE order_id = ?`,
            [order.id]
        );

        success(res, {
            ...order,
            status_text: getStatusText(order.status),
            total_quantity: items.reduce((s, i) => s + Number(i.quantity), 0),
            items
        }, '获取成功');
    } catch (err) {
        handleError(err, res, '获取订单详情');
    }
});



/**
 * @api {post} /api/orders/:idOrNo/cancel 取消订单（仅待付款）
 */
router.post('/:idOrNo/cancel', async (req, res) => {
    const conn = await pool.getConnection();
    try {
        const userId = req.user.id;
        await conn.beginTransaction();

        
        const isNumeric = /^\d+$/.test(String(req.params.idOrNo));
        const sql = isNumeric
            ? 'SELECT * FROM orders WHERE id = ? AND user_id = ? AND is_deleted = 0 FOR UPDATE'
            : 'SELECT * FROM orders WHERE order_no = ? AND user_id = ? AND is_deleted = 0 FOR UPDATE';
        const [rows] = await conn.execute(sql, [req.params.idOrNo, userId]);
        if (rows.length === 0) {
            await conn.rollback();
            return error(res, '订单不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
        }
        const order = rows[0];

        if (!canTransition(order.status, ORDER_STATUS.CANCELLED)) {
            await conn.rollback();
            return error(res, `订单当前状态（${getStatusText(order.status)}）不允许取消`, SHOP_RESPONSE_CODES.INVALID_ORDER_STATUS, HTTP_STATUS.CONFLICT);
        }

        
        await conn.execute(
            'UPDATE orders SET status = ?, cancelled_at = NOW() WHERE id = ?',
            [ORDER_STATUS.CANCELLED, order.id]
        );

        
        const [items] = await conn.execute(
            'SELECT product_id, sku_id, quantity FROM order_items WHERE order_id = ?',
            [order.id]
        );
        for (const it of items) {
            if (it.sku_id) {
                await conn.execute(
                    'UPDATE product_skus SET stock = stock + ? WHERE id = ?',
                    [it.quantity, it.sku_id]
                );
            }
            await conn.execute(
                'UPDATE products SET stock = stock + ?, sales = sales - ? WHERE id = ?',
                [it.quantity, it.quantity, it.product_id]
            );
        }

        
        await conn.execute(
            `INSERT INTO order_status_logs (order_id, from_status, to_status, operator_id, operator_type, remark)
             VALUES (?, ?, ?, ?, 'user', '买家取消订单')`,
            [order.id, order.status, ORDER_STATUS.CANCELLED, userId]
        );

        await conn.commit();
        success(res, null, '取消成功');
    } catch (err) {
        await conn.rollback();
        handleError(err, res, '取消订单');
    } finally {
        conn.release();
    }
});



/**
 * @api {post} /api/orders/:idOrNo/confirm 确认收货（仅待收货）
 */
router.post('/:idOrNo/confirm', async (req, res) => {
    const conn = await pool.getConnection();
    try {
        const userId = req.user.id;
        await conn.beginTransaction();

        const isNumeric = /^\d+$/.test(String(req.params.idOrNo));
        const sql = isNumeric
            ? 'SELECT * FROM orders WHERE id = ? AND user_id = ? AND is_deleted = 0 FOR UPDATE'
            : 'SELECT * FROM orders WHERE order_no = ? AND user_id = ? AND is_deleted = 0 FOR UPDATE';
        const [rows] = await conn.execute(sql, [req.params.idOrNo, userId]);
        if (rows.length === 0) {
            await conn.rollback();
            return error(res, '订单不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
        }
        const order = rows[0];

        if (!canTransition(order.status, ORDER_STATUS.COMPLETED)) {
            await conn.rollback();
            return error(res, `订单当前状态（${getStatusText(order.status)}）不允许确认收货`, SHOP_RESPONSE_CODES.INVALID_ORDER_STATUS, HTTP_STATUS.CONFLICT);
        }

        await conn.execute(
            'UPDATE orders SET status = ?, completed_at = NOW() WHERE id = ?',
            [ORDER_STATUS.COMPLETED, order.id]
        );

        await conn.execute(
            `INSERT INTO order_status_logs (order_id, from_status, to_status, operator_id, operator_type, remark)
             VALUES (?, ?, ?, ?, 'user', '确认收货')`,
            [order.id, order.status, ORDER_STATUS.COMPLETED, userId]
        );

        await conn.commit();
        success(res, null, '确认收货成功');
    } catch (err) {
        await conn.rollback();
        handleError(err, res, '确认收货');
    } finally {
        conn.release();
    }
});



/**
 * @api {get} /api/orders/:idOrNo/logs 订单状态流转日志
 */
router.get('/:idOrNo/logs', async (req, res) => {
    try {
        const userId = req.user.id;
        const order = await findOrder(req.params.idOrNo, userId);
        if (!order) {
            return error(res, '订单不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
        }

        const [logs] = await pool.execute(
            `SELECT id, from_status, to_status, operator_type, remark, created_at
             FROM order_status_logs
             WHERE order_id = ?
             ORDER BY created_at ASC`,
            [order.id]
        );

        const data = logs.map(l => ({
            ...l,
            from_status_text: l.from_status ? getStatusText(l.from_status) : null,
            to_status_text: getStatusText(l.to_status)
        }));

        success(res, data, '获取成功');
    } catch (err) {
        handleError(err, res, '获取订单日志');
    }
});

module.exports = router;
