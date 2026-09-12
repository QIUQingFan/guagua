/**
 * 支付宝支付回调路由
 * 挂载于 /api/alipay（不经过登录鉴权，由支付宝服务器/浏览器直接访问）
 *
 *  - POST /notify  支付宝异步通知：支付结果以此为准，必须验签，返回纯文本 success/fail
 *  - GET  /return  同步跳转返回：用户支付完成后浏览器跳回，验签后 302 到前端订单页
 *
 */
const express = require('express');
const router = express.Router();
const { pool } = require('../config/config');
const { ORDER_STATUS } = require('../constants');
const { verifyNotify } = require('../utils/alipay');
const config = require('../config/config');

const PAID_STATUSES = ['TRADE_SUCCESS', 'TRADE_FINISHED'];

/**
 * 根据商户订单号查找订单
 * @param {string} outTradeNo
 * @param {Object} conn
 * @param {boolean} forUpdate 是否加行锁
 */
async function findOrderByOrderNo(outTradeNo, conn, forUpdate = false) {
  const lock = forUpdate ? ' FOR UPDATE' : '';
  const [rows] = await conn.execute(
    `SELECT * FROM orders WHERE order_no = ? AND is_deleted = 0${lock}`,
    [outTradeNo]
  );
  return rows.length > 0 ? rows[0] : null;
}

/**
 * @api {post} /api/alipay/notify 支付宝异步通知
 */
router.post('/notify', async (req, res) => {
  const params = req.body || {};
  if (Object.keys(params).length === 0) {
    return res.send('fail');
  }

  try {
    const ok = verifyNotify(params);
    if (!ok) {
      console.warn('[alipay.notify] 验签失败，拒绝处理:', params.out_trade_no);
      return res.send('fail');
    }

    const { out_trade_no, trade_no, trade_status, total_amount } = params;

    if (!out_trade_no || !PAID_STATUSES.includes(trade_status)) {
      return res.send('success');
    }

    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();
      const order = await findOrderByOrderNo(out_trade_no, conn, true);
      if (!order) {
        await conn.rollback();
        return res.send('fail');
      }

      if (order.status === ORDER_STATUS.PENDING_PAYMENT) {
        await conn.execute(
          'UPDATE orders SET status = ?, trade_no = ?, paid_at = NOW() WHERE id = ?',
          [ORDER_STATUS.PENDING_SHIPMENT, trade_no || null, order.id]
        );
        await conn.execute(
          `INSERT INTO order_status_logs (order_id, from_status, to_status, operator_id, operator_type, remark)
           VALUES (?, ?, ?, NULL, 'system', ?)`,
          [
            order.id,
            ORDER_STATUS.PENDING_PAYMENT,
            ORDER_STATUS.PENDING_SHIPMENT,
            `支付宝支付成功，交易号 ${trade_no || '-'}，金额 ${total_amount || order.pay_amount} 元`
          ]
        );
        console.log(`[alipay.notify] 订单 ${out_trade_no} 支付成功，状态置为待发货`);
      } else {
        console.log(`[alipay.notify] 订单 ${out_trade_no} 已处理，忽略重复通知`);
      }

      await conn.commit();
      res.send('success');
    } catch (e) {
      await conn.rollback();
      console.error('[alipay.notify] 处理失败:', e);
      res.send('fail');
    } finally {
      conn.release();
    }
  } catch (e) {
    console.error('[alipay.notify] 异常:', e);
    res.send('fail');
  }
});

/**
 * @api {get} /api/alipay/return 同步跳转返回
 * 用户支付完成后浏览器跳回
 * 验签通过后 302 重定向到前端订单详情页，由前端刷新真实支付结果。
 */
router.get('/return', async (req, res) => {
  const params = req.query || {};
  const frontendUrl = config.alipay.frontendUrl;
  const orderNo = params.out_trade_no;
  const target = orderNo
    ? `${frontendUrl}/shop/orders/${encodeURIComponent(orderNo)}`
    : `${frontendUrl}/shop/orders`;

  try {
    const ok = verifyNotify(params);
    if (!ok) {
      console.warn('[alipay.return] 验签失败，仍跳转回订单页:', orderNo);
    }
  } catch (e) {
    console.error('[alipay.return] 异常:', e);
  }
  res.redirect(target);
});

module.exports = router;
