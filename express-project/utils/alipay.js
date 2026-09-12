/**
 * 支付宝支付工具模块
 * 
 * 封装 alipay-sdk 的初始化与常用操作：
 *  - 电脑网站支付（alipay.trade.page.pay）：生成收银台跳转链接
 *  - 交易查询（alipay.trade.query）：获取权威支付结果
 *  - 交易退款（alipay.trade.refund）：原路退回买家资金
 *  - 退款查询（alipay.trade.fastpay.refund.query）
 *  - 交易关闭（alipay.trade.close）
 */

const { AlipaySdk } = require('alipay-sdk');
const config = require('../config/config');

const SANDBOX_GATEWAY = 'https://openapi-sandbox.dl.alipaydev.com/gateway.do';
const PROD_GATEWAY = 'https://openapi.alipay.com/gateway.do';

let sdk = null;
let enabled = false;

function init() {
  const c = config.alipay;
  if (!c.enabled) {
    console.warn('[alipay] 未启用：ALIPAY_ENABLED != true，支付相关接口不可用');
    return;
  }
  if (!c.appId || !c.privateKey || !c.alipayPublicKey) {
    console.warn('[alipay] 配置不完整，请检查 ALIPAY_APP_ID / ALIPAY_PRIVATE_KEY / ALIPAY_PUBLIC_KEY');
    return;
  }

  const gateway = c.sandbox ? SANDBOX_GATEWAY : PROD_GATEWAY;
  sdk = new AlipaySdk({
    appId: c.appId,
    privateKey: c.privateKey,
    alipayPublicKey: c.alipayPublicKey,
    signType: c.signType,
    gateway,
    keyType: process.env.ALIPAY_KEY_TYPE || 'PKCS8'
  });
  enabled = true;
  console.log(`[alipay] SDK 初始化成功，环境：${c.sandbox ? '沙箱' : '正式'}，网关：${gateway}`);
}

init();

/** 支付宝支付是否可用 */
function isEnabled() {
  return enabled;
}

function getSdk() {
  if (!enabled) throw new Error('支付宝支付未启用或配置不完整');
  return sdk;
}

/**
 * 生成电脑网站支付跳转链接（alipay.trade.page.pay）
 * @param {Object} p
 * @param {string} p.outTradeNo 商户订单号
 * @param {string|number} p.totalAmount 订单金额（元，两位小数）
 * @param {string} p.subject 订单标题
 * @param {string} [p.body] 订单描述
 * @returns {string} 支付宝收银台跳转链接
 */
function buildPayUrl({ outTradeNo, totalAmount, subject, body }) {
  const c = config.alipay;
  return getSdk().pageExecute('alipay.trade.page.pay', 'GET', {
    bizContent: {
      out_trade_no: outTradeNo,
      product_code: 'FAST_INSTANT_TRADE_PAY',
      total_amount: String(Number(totalAmount).toFixed(2)),
      subject,
      body: body || subject,
      qr_pay_mode: '1'
    },
    returnUrl: c.returnUrl,
    notifyUrl: c.notifyUrl
  });
}

/**
 * 查询交易（alipay.trade.query）
 * @param {Object} p { outTradeNo, tradeNo? }
 * @returns {Promise<Object>} 支付宝返回（code=10000 表示请求成功）
 */
async function queryTrade({ outTradeNo, tradeNo }) {
  return getSdk().exec('alipay.trade.query', {
    bizContent: { out_trade_no: outTradeNo, trade_no: tradeNo || undefined }
  });
}

/**
 * 发起退款（alipay.trade.refund），资金原路退回买家
 * @param {Object} p
 * @param {string} p.outTradeNo 商户订单号
 * @param {string} [p.tradeNo] 支付宝交易号
 * @param {string|number} p.refundAmount 退款金额（不能超过实付金额）
 * @param {string} p.outRequestNo 退款请求号（幂等键，重试时保持不变，防重复退款）
 * @param {string} [p.refundReason] 退款原因
 * @returns {Promise<Object>} 支付宝返回
 */
async function refund({ outTradeNo, tradeNo, refundAmount, outRequestNo, refundReason }) {
  return getSdk().exec('alipay.trade.refund', {
    bizContent: {
      out_trade_no: outTradeNo,
      trade_no: tradeNo || undefined,
      refund_amount: String(Number(refundAmount).toFixed(2)),
      out_request_no: outRequestNo,
      refund_reason: refundReason
    }
  });
}

/**
 * 查询退款（alipay.trade.fastpay.refund.query）
 * @param {Object} p { outTradeNo, outRequestNo, tradeNo? }
 */
async function queryRefund({ outTradeNo, outRequestNo, tradeNo }) {
  return getSdk().exec('alipay.trade.fastpay.refund.query', {
    bizContent: { out_trade_no: outTradeNo, trade_no: tradeNo || undefined, out_request_no: outRequestNo }
  });
}

/**
 * 关闭交易（alipay.trade.close）
 * @param {Object} p { outTradeNo, tradeNo? }
 */
async function closeTrade({ outTradeNo, tradeNo }) {
  return getSdk().exec('alipay.trade.close', {
    bizContent: { out_trade_no: outTradeNo, trade_no: tradeNo || undefined }
  });
}

/**
 * 验签：异步通知（POST）或同步返回（GET）的参数
 * @param {Object} params 支付宝回传的全部参数（含 sign）
 * @returns {boolean}
 */
function verifyNotify(params) {
  return getSdk().checkNotifySign(params);
}

module.exports = {
  isEnabled,
  buildPayUrl,
  queryTrade,
  refund,
  queryRefund,
  closeTrade,
  verifyNotify
};
