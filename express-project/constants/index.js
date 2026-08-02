/**
 * 应用常量定义
 */


const HTTP_STATUS = {
  OK: 200,
  CREATED: 201,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  INTERNAL_SERVER_ERROR: 500
};


const RESPONSE_CODES = {
  SUCCESS: 200,
  ERROR: 500,
  VALIDATION_ERROR: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409
};


const ERROR_MESSAGES = {
  VALIDATION_FAILED: '数据验证失败',
  UNAUTHORIZED: '未授权访问',
  FORBIDDEN: '权限不足',
  NOT_FOUND: '资源不存在',
  DUPLICATE_ENTRY: '数据已存在',
  DATABASE_ERROR: '数据库操作失败',
  UPLOAD_FAILED: '图片上传失败',
  INVALID_TOKEN: '无效的令牌',
  TOKEN_EXPIRED: '令牌已过期',
  INTERNAL_SERVER_ERROR: '服务器内部错误',
  BAD_REQUEST: '请求参数错误',
  REQUEST_FAILED: '请求失败',
  SESSION_EXPIRED: '会话已过期',
  NETWORK_ERROR: '网络连接错误',
  REQUEST_CONFIG_ERROR: '请求配置错误'
};




const PRODUCT_STATUS = {
  DRAFT: 'draft',
  PENDING_REVIEW: 'pending_review',
  ON_SALE: 'on_sale',
  OFF_SALE: 'off_sale',
  SOLD_OUT: 'sold_out'
};


const PRODUCT_STATUS_TEXT = {
  draft: '草稿',
  pending_review: '待审核',
  on_sale: '上架',
  off_sale: '下架',
  sold_out: '售罄'
};


const ORDER_STATUS = {
  PENDING_PAYMENT: 'pending_payment',
  PENDING_SHIPMENT: 'pending_shipment',
  SHIPPED: 'shipped',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
  CLOSED: 'closed'
};


const ORDER_STATUS_TEXT = {
  pending_payment: '待付款',
  pending_shipment: '待发货',
  shipped: '待收货',
  completed: '已完成',
  cancelled: '已取消',
  closed: '已关闭'
};


const ORDER_TRANSITIONS = {
  pending_payment: ['pending_shipment', 'cancelled'],
  pending_shipment: ['shipped', 'cancelled', 'closed'],
  shipped: ['completed', 'closed'],
  completed: ['closed'],
  cancelled: [],
  closed: []
};


const OPERATOR_TYPE = {
  USER: 'user',
  ADMIN: 'admin',
  SYSTEM: 'system'
};


const SHOP_RESPONSE_CODES = {
  OUT_OF_STOCK: 4091,          
  PRODUCT_OFF_SHELF: 4092,     
  INVALID_ORDER_STATUS: 4093,  
  CART_ITEM_LIMIT: 4094,       
  PRICE_MISMATCH: 4095         
};


const CART_MAX_QUANTITY = 99;

module.exports = {
  HTTP_STATUS,
  RESPONSE_CODES,
  ERROR_MESSAGES,
  PRODUCT_STATUS,
  PRODUCT_STATUS_TEXT,
  ORDER_STATUS,
  ORDER_STATUS_TEXT,
  ORDER_TRANSITIONS,
  OPERATOR_TYPE,
  SHOP_RESPONSE_CODES,
  CART_MAX_QUANTITY
};