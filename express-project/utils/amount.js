/**
 * 金额计算工具
 *
 * 所有金额计算统一走这里，避免浮点精度问题。
 * 设计要点：
 * 1. 内部使用 Number 计算，结果用 toFixed(2) 转为字符串保留 2 位小数
 * 2. 返回字符串而非 Number，避免再次运算时浮点失真
 * 3. 单位为「元」，与数据库 DECIMAL(10,2) 一致
 */

/**
 * 计算单项小计 = 单价 × 数量
 * @param {number|string} price 单价
 * @param {number} quantity 数量
 * @returns {string} 保留 2 位小数的字符串
 */
function calcSubtotal(price, quantity) {
  const p = Number(price);
  const q = Number(quantity);
  if (!Number.isFinite(p) || !Number.isFinite(q)) {
    throw new Error(`金额参数非法: price=${price}, quantity=${quantity}`);
  }
  if (q < 0) {
    throw new Error(`数量不能为负: ${quantity}`);
  }
  return (p * q).toFixed(2);
}

/**
 * 计算多项合计金额
 * @param {Array<number|string>} amounts 金额数组
 * @returns {string} 保留 2 位小数的字符串
 */
function calcTotal(amounts) {
  if (!Array.isArray(amounts) || amounts.length === 0) {
    return '0.00';
  }
  const sum = amounts.reduce((acc, cur) => {
    const n = Number(cur);
    if (!Number.isFinite(n)) {
      throw new Error(`金额参数非法: ${cur}`);
    }
    return acc + n;
  }, 0);
  return sum.toFixed(2);
}

/**
 * 计算应付金额 = 商品总额 + 运费
 * @param {number|string} totalAmount 商品总额
 * @param {number|string} shippingFee 运费
 * @returns {string}
 */
function calcPayAmount(totalAmount, shippingFee = 0) {
  const t = Number(totalAmount);
  const s = Number(shippingFee);
  if (!Number.isFinite(t) || !Number.isFinite(s)) {
    throw new Error(`金额参数非法: totalAmount=${totalAmount}, shippingFee=${shippingFee}`);
  }
  return (t + s).toFixed(2);
}

/**
 * 比较两个金额是否相等（字符串或数字皆可）
 * @param {string|number} a
 * @param {string|number} b
 * @returns {boolean}
 */
function isAmountEqual(a, b) {
  return Number(a).toFixed(2) === Number(b).toFixed(2);
}

/**
 * 校验金额合法性（非负有限数）
 * 注意：JS 中 Number(null) === 0，需显式拦截 null/undefined
 * @param {*} value
 * @returns {boolean}
 */
function isValidAmount(value) {
  if (value === null || value === undefined) return false;
  if (typeof value === 'boolean') return false;
  const n = Number(value);
  return Number.isFinite(n) && n >= 0;
}

module.exports = {
  calcSubtotal,
  calcTotal,
  calcPayAmount,
  isAmountEqual,
  isValidAmount
};
