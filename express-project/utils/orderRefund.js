/**
 * 订单退款服务：支付宝原路退回 + 订单状态流转 + 库存回补
 */

const { ORDER_STATUS, REFUND_STATUS, OPERATOR_TYPE } = require('../constants');
const alipay = require('./alipay');

/**
 * 执行退款
 * @param {Object} param0
 * @param {Object} param0.conn   数据库连接
 * @param {Object} param0.order  订单行
 * @param {number} param0.operatorId  操作人 id
 * @param {string} param0.operatorType user | admin | system
 * @param {string} [param0.reason]     退款原因
 * @returns {Promise<{already: boolean, tradeNo: string|null}>}
 */
async function refundOrder({ conn, order, operatorId, operatorType, reason }) {
  if (!alipay.isEnabled()) {
    throw new Error('支付宝支付尚未配置，无法退款');
  }

  // 幂等：已退款直接返回，防止重复发起支付宝退款
  if (order.refund_status === REFUND_STATUS.REFUNDED) {
    return { already: true, tradeNo: order.trade_no };
  }

  const refundAmount = Number(order.pay_amount).toFixed(2);
  // 退款请求号：唯一，保证同一订单的退款幂等
  const outRequestNo = `${order.order_no}_R${Date.now()}`;

  let result;
  try {
    result = await alipay.refund({
      outTradeNo: order.order_no,
      tradeNo: order.trade_no || undefined,
      refundAmount,
      outRequestNo,
      refundReason: reason || '用户申请退款'
    });
  } catch (e) {
    throw new Error(`调用支付宝退款失败：${e.message}`);
  }

  if (!result || result.code !== '10000') {
    const msg = (result && (result.subMsg || result.sub_code)) || '未知错误';
    throw new Error(`支付宝退款失败：${msg}`);
  }

  // 更新订单为已退款
  await conn.execute(
    `UPDATE orders
     SET status = ?, refund_status = ?, refund_amount = ?, refund_no = ?, refund_reason = ?, refund_at = NOW()
     WHERE id = ?`,
    [ORDER_STATUS.REFUNDED, REFUND_STATUS.REFUNDED, refundAmount, outRequestNo, reason || null, order.id]
  );

  await conn.execute(
    `INSERT INTO order_status_logs (order_id, from_status, to_status, operator_id, operator_type, remark)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [
      order.id,
      order.status,
      ORDER_STATUS.REFUNDED,
      operatorId,
      operatorType,
      `退款成功：${refundAmount} 元${reason ? `（${reason}）` : ''}，支付宝交易号 ${result.trade_no || order.trade_no || '-'}`
    ]
  );

  // 库存回补
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

  return { already: false, tradeNo: result.trade_no };
}

module.exports = { refundOrder };
