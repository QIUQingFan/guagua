/**
 * 管理端 - 订单管理路由
 * 挂载于 /api/admin/orders，由 routes/admin.js 通过 router.use('/orders', adminAuth, ...) 引入
 *
 * 提供能力：
 *  - GET  /              订单列表（用户/订单号/状态筛选 + 买家信息 + 商品项汇总 + 分页）
 *  - GET  /:idOrNo       订单详情（含 items / 买家信息 / 状态流转日志）
 *  - POST /:idOrNo/ship  发货（pending_shipment → shipped，写入物流信息）
 *  - POST /:idOrNo/close 关闭订单（shipped / completed → closed）
 *
 * 说明：
 *  - 管理端操作不限 user_id，可查看所有订单；:idOrNo 纯数字按 id 查，否则按 order_no 查
 *  - 发货/关闭为管理端业务动作，允许的源状态由本路由单独维护（详见 SHIP/CLOSE_SOURCE_STATUSES）
 *  - 所有状态流转写 order_status_logs，operator_type='admin'，operator_id 取自 req.user.id
 */
const express = require('express');
const router = express.Router();
const { pool } = require('../config/config');
const { success, error, handleError } = require('../utils/responseHelper');
const { HTTP_STATUS, RESPONSE_CODES, ORDER_STATUS, OPERATOR_TYPE, SHOP_RESPONSE_CODES, REFUND_STATUS } = require('../constants');
const { getStatusText } = require('../utils/orderStatus');
const { refundOrder } = require('../utils/orderRefund');


const SHIP_SOURCE_STATUSES = [ORDER_STATUS.PENDING_SHIPMENT];

const CLOSE_SOURCE_STATUSES = [ORDER_STATUS.SHIPPED, ORDER_STATUS.COMPLETED];

const REFUND_SOURCE_STATUSES = [ORDER_STATUS.PENDING_SHIPMENT, ORDER_STATUS.SHIPPED, ORDER_STATUS.COMPLETED];


const SORT_FIELD_MAP = {
  id: 'o.id',
  order_no: 'o.order_no',
  status: 'o.status',
  total_amount: 'o.total_amount',
  pay_amount: 'o.pay_amount',
  created_at: 'o.created_at',
  paid_at: 'o.paid_at',
  shipped_at: 'o.shipped_at'
};

/**
 * 根据参数解析订单
 * @param {string} idOrNo
 * @param {Object} conn 可选连接
 * @param {boolean} forUpdate 是否加行锁
 * @returns {Promise<Object|null>}
 */
async function findOrder(idOrNo, conn = pool, forUpdate = false) {
  const isNumeric = /^\d+$/.test(String(idOrNo));
  const lock = forUpdate ? ' FOR UPDATE' : '';
  const sql = isNumeric
    ? `SELECT * FROM orders WHERE id = ? AND is_deleted = 0${lock}`
    : `SELECT * FROM orders WHERE order_no = ? AND is_deleted = 0${lock}`;
  const [rows] = await conn.execute(sql, [String(idOrNo)]);
  return rows.length > 0 ? rows[0] : null;
}


router.get('/', async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit) || 20));
    const offset = (page - 1) * limit;

    const conditions = ['o.is_deleted = 0'];
    const params = [];


    if (req.query.user_id) {
      conditions.push('(o.user_id = ? OR u.user_id = ?)');
      const uv = String(req.query.user_id).trim();
      params.push(uv, uv);
    }

    if (req.query.order_no) {
      conditions.push('o.order_no LIKE ?');
      params.push(`%${String(req.query.order_no).trim()}%`);
    }

    if (req.query.status) {
      const statuses = String(req.query.status).split(',').map(s => s.trim()).filter(Boolean);
      if (statuses.length > 0) {
        const placeholders = statuses.map(() => '?').join(',');
        conditions.push(`o.status IN (${placeholders})`);
        params.push(...statuses);
      }
    }

    const where = 'WHERE ' + conditions.join(' AND ');


    const sortField = SORT_FIELD_MAP[req.query.sortField] || 'o.created_at';
    const sortOrder = String(req.query.sortOrder).toLowerCase() === 'asc' ? 'ASC' : 'DESC';
    const orderClause = `ORDER BY ${sortField} ${sortOrder}`;

    const [[{ total }]] = await pool.execute(
      `SELECT COUNT(*) AS total
       FROM orders o
       LEFT JOIN users u ON o.user_id = u.id
       ${where}`,
      params
    );

    const [rows] = await pool.execute(
      `SELECT o.id, o.order_no, o.user_id, o.status, o.total_amount, o.shipping_fee, o.pay_amount,
              o.trade_no, o.refund_status, o.refund_amount, o.refund_reason, o.refund_at,
              o.receiver, o.phone, o.tracking_company, o.tracking_no, o.remark,
              o.paid_at, o.shipped_at, o.completed_at, o.cancelled_at, o.created_at,
              u.nickname AS user_nickname, u.user_id AS user_account, u.avatar AS user_avatar
       FROM orders o
       LEFT JOIN users u ON o.user_id = u.id
       ${where}
       ${orderClause}
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

    success(res, {
      data: list,
      pagination: { page, limit, total, pages: Math.ceil(total / limit) }
    }, '获取成功');
  } catch (err) {
    handleError(err, res, '获取订单列表');
  }
});


router.get('/:idOrNo', async (req, res) => {
  try {
    const order = await findOrder(req.params.idOrNo);
    if (!order) {
      return error(res, '订单不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }


    const [userRows] = await pool.execute(
      'SELECT id, user_id, nickname, avatar FROM users WHERE id = ?',
      [order.user_id]
    );


    const [items] = await pool.execute(
      `SELECT id, product_id, sku_id, product_title, product_image, spec, unit_price, quantity, subtotal
       FROM order_items WHERE order_id = ?`,
      [order.id]
    );


    const [logs] = await pool.execute(
      `SELECT id, from_status, to_status, operator_id, operator_type, remark, created_at
       FROM order_status_logs
       WHERE order_id = ?
       ORDER BY created_at ASC`,
      [order.id]
    );

    success(res, {
      ...order,
      status_text: getStatusText(order.status),
      total_quantity: items.reduce((s, i) => s + Number(i.quantity), 0),
      user: userRows.length > 0 ? userRows[0] : null,
      items,
      logs: logs.map(l => ({
        ...l,
        from_status_text: l.from_status ? getStatusText(l.from_status) : null,
        to_status_text: getStatusText(l.to_status)
      }))
    }, '获取成功');
  } catch (err) {
    handleError(err, res, '获取订单详情');
  }
});


/**
 * @api {post} /api/admin/orders/:idOrNo/ship 发货
 * @apiBody {String} tracking_company 物流公司
 * @apiBody {String} tracking_no 物流单号
 * 允许源状态：pending_shipment → shipped
 * 仅已支付（待发货）订单可发货，待付款订单不允许发货。
 */
router.post('/:idOrNo/ship', async (req, res) => {
  const conn = await pool.getConnection();
  try {
    const adminId = req.user.id;
    const body = req.body || {};

    if (!body.tracking_company || !body.tracking_no) {
      return error(res, '请填写物流公司和物流单号', RESPONSE_CODES.VALIDATION_ERROR, HTTP_STATUS.BAD_REQUEST);
    }

    await conn.beginTransaction();

    const order = await findOrder(req.params.idOrNo, conn, true);
    if (!order) {
      await conn.rollback();
      return error(res, '订单不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }

    if (!SHIP_SOURCE_STATUSES.includes(order.status)) {
      await conn.rollback();
      return error(
        res,
        `订单当前状态（${getStatusText(order.status)}）不允许发货，仅待发货可发货`,
        SHOP_RESPONSE_CODES.INVALID_ORDER_STATUS,
        HTTP_STATUS.CONFLICT
      );
    }

    await conn.execute(
      `UPDATE orders
       SET status = ?, tracking_company = ?, tracking_no = ?, shipped_at = NOW()
       WHERE id = ?`,
      [ORDER_STATUS.SHIPPED, String(body.tracking_company), String(body.tracking_no), order.id]
    );

    await conn.execute(
      `INSERT INTO order_status_logs (order_id, from_status, to_status, operator_id, operator_type, remark)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [order.id, order.status, ORDER_STATUS.SHIPPED, adminId, OPERATOR_TYPE.ADMIN, `发货：${body.tracking_company} ${body.tracking_no}`]
    );

    await conn.commit();
    success(res, {
      id: order.id,
      order_no: order.order_no,
      status: ORDER_STATUS.SHIPPED,
      status_text: getStatusText(ORDER_STATUS.SHIPPED)
    }, '发货成功');
  } catch (err) {
    await conn.rollback();
    handleError(err, res, '订单发货');
  } finally {
    conn.release();
  }
});


/**
 * @api {post} /api/admin/orders/:idOrNo/close 关闭订单
 * @apiBody {String} [remark] 关闭备注
 * 允许源状态：shipped / completed → closed
 */
router.post('/:idOrNo/close', async (req, res) => {
  const conn = await pool.getConnection();
  try {
    const adminId = req.user.id;
    const body = req.body || {};

    await conn.beginTransaction();

    const order = await findOrder(req.params.idOrNo, conn, true);
    if (!order) {
      await conn.rollback();
      return error(res, '订单不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }

    if (!CLOSE_SOURCE_STATUSES.includes(order.status)) {
      await conn.rollback();
      return error(
        res,
        `订单当前状态（${getStatusText(order.status)}）不允许关闭，仅待收货/已完成可关闭`,
        SHOP_RESPONSE_CODES.INVALID_ORDER_STATUS,
        HTTP_STATUS.CONFLICT
      );
    }

    await conn.execute(
      'UPDATE orders SET status = ? WHERE id = ?',
      [ORDER_STATUS.CLOSED, order.id]
    );

    const remark = body.remark ? `关闭：${String(body.remark).slice(0, 200)}` : '管理员关闭订单';
    await conn.execute(
      `INSERT INTO order_status_logs (order_id, from_status, to_status, operator_id, operator_type, remark)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [order.id, order.status, ORDER_STATUS.CLOSED, adminId, OPERATOR_TYPE.ADMIN, remark]
    );

    await conn.commit();
    success(res, {
      id: order.id,
      order_no: order.order_no,
      status: ORDER_STATUS.CLOSED,
      status_text: getStatusText(ORDER_STATUS.CLOSED)
    }, '关闭成功');
  } catch (err) {
    await conn.rollback();
    handleError(err, res, '关闭订单');
  } finally {
    conn.release();
  }
});


/**
 * @api {post} /api/admin/orders/:idOrNo/refund 订单退款
 * @apiBody {String} [reason] 退款原因
 * 允许源状态：pending_shipment / shipped / completed → refunded
 * 金额全额原路退回买家支付宝账户，并回补库存。
 */
router.post('/:idOrNo/refund', async (req, res) => {
  const conn = await pool.getConnection();
  try {
    const adminId = req.user.id;
    const body = req.body || {};

    await conn.beginTransaction();

    const order = await findOrder(req.params.idOrNo, conn, true);
    if (!order) {
      await conn.rollback();
      return error(res, '订单不存在', RESPONSE_CODES.NOT_FOUND, HTTP_STATUS.NOT_FOUND);
    }

    if (!REFUND_SOURCE_STATUSES.includes(order.status)) {
      await conn.rollback();
      return error(
        res,
        `订单当前状态（${getStatusText(order.status)}）不允许退款，仅待发货/待收货/已完成可退款`,
        SHOP_RESPONSE_CODES.INVALID_ORDER_STATUS,
        HTTP_STATUS.CONFLICT
      );
    }

    if (order.refund_status === REFUND_STATUS.REFUNDED) {
      await conn.rollback();
      return error(res, '该订单已退款，请勿重复操作', SHOP_RESPONSE_CODES.ALREADY_REFUNDED, HTTP_STATUS.CONFLICT);
    }

    const { already } = await refundOrder({
      conn,
      order,
      operatorId: adminId,
      operatorType: OPERATOR_TYPE.ADMIN,
      reason: body.reason ? String(body.reason).slice(0, 200) : '商家退款'
    });

    await conn.commit();
    if (already) {
      return success(res, { id: order.id, order_no: order.order_no }, '该订单已退款');
    }
    success(res, {
      id: order.id,
      order_no: order.order_no,
      status: ORDER_STATUS.REFUNDED,
      status_text: getStatusText(ORDER_STATUS.REFUNDED),
      refund_amount: order.pay_amount
    }, '退款成功，款项已原路退回买家');
  } catch (err) {
    await conn.rollback();
    if (err.message && (err.message.startsWith('支付宝退款失败') || err.message.startsWith('调用支付宝退款失败'))) {
      return error(res, err.message, SHOP_RESPONSE_CODES.ALIPAY_REFUND_FAILED, HTTP_STATUS.BAD_REQUEST);
    }
    handleError(err, res, '订单退款');
  } finally {
    conn.release();
  }
});

module.exports = router;
