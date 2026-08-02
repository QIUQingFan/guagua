/**
 * 订单状态机工具
 * 集中管理订单状态文本映射与合法迁移校验，避免状态字符串散落。
 */

const {
  ORDER_STATUS,
  ORDER_STATUS_TEXT,
  ORDER_TRANSITIONS
} = require('../constants');

/**
 * 判断状态迁移是否合法
 * @param {string|null} from - 原状态（首次下单时为 null）
 * @param {string} to - 目标状态
 * @returns {boolean}
 */
function canTransition(from, to) {
  if (!from) {
    return to === ORDER_STATUS.PENDING_PAYMENT;
  }
  const allowed = ORDER_TRANSITIONS[from];
  if (!allowed) return false;
  return allowed.includes(to);
}

/**
 * 获取状态中文文本
 * @param {string} status
 * @returns {string}
 */
function getStatusText(status) {
  return ORDER_STATUS_TEXT[status] || status || '';
}

/**
 * 获取商品状态中文文本
 * @param {string} status
 * @returns {string}
 */
function getProductStatusText(status) {
  const { PRODUCT_STATUS_TEXT } = require('../constants');
  return PRODUCT_STATUS_TEXT[status] || status || '';
}

/**
 * 判断订单是否处于终态
 * @param {string} status
 * @returns {boolean}
 */
function isTerminalStatus(status) {
  const allowed = ORDER_TRANSITIONS[status];
  return Array.isArray(allowed) && allowed.length === 0;
}

/**
 * 校验状态值是否合法
 * @param {string} status
 * @returns {boolean}
 */
function isValidStatus(status) {
  return Object.prototype.hasOwnProperty.call(ORDER_STATUS_TEXT, status);
}

module.exports = {
  canTransition,
  getStatusText,
  getProductStatusText,
  isTerminalStatus,
  isValidStatus
};
