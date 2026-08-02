/**
 * 订单号生成器
 */
const crypto = require('crypto');

const ORDER_NO_PREFIX = 'SO';
const ORDER_NO_LENGTH = 24;
const COUNTER_MOD = 10000;       
const RANDOM_BOUND = 10000;      

let counter = 0;

/**
 * 生成订单号
 * @returns {string} 24 位订单号
 */
function generateOrderNo() {
  const now = new Date();
  const ts = now.getFullYear().toString() +
    String(now.getMonth() + 1).padStart(2, '0') +
    String(now.getDate()).padStart(2, '0') +
    String(now.getHours()).padStart(2, '0') +
    String(now.getMinutes()).padStart(2, '0') +
    String(now.getSeconds()).padStart(2, '0');
  counter = (counter + 1) % COUNTER_MOD;
  const counterStr = String(counter).padStart(4, '0');
  const rand = crypto.randomInt(0, RANDOM_BOUND).toString().padStart(4, '0');
  return `${ORDER_NO_PREFIX}${ts}${counterStr}${rand}`;
}

/**
 * 重置计数器（仅供测试使用）
 * @param {number} [value=0]
 */
function _resetCounter(value = 0) {
  counter = value;
}

/**
 * 校验订单号格式
 * @param {string} orderNo
 * @returns {boolean}
 */
function isValidOrderNo(orderNo) {
  if (typeof orderNo !== 'string') return false;
  if (orderNo.length !== ORDER_NO_LENGTH) return false;
  if (!orderNo.startsWith(ORDER_NO_PREFIX)) return false;
  const rest = orderNo.slice(ORDER_NO_PREFIX.length);
  return /^\d+$/.test(rest);
}

module.exports = {
  generateOrderNo,
  isValidOrderNo,
  _resetCounter,
  ORDER_NO_PREFIX,
  ORDER_NO_LENGTH
};
