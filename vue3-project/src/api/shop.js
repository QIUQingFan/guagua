import request from './request.js'

/**
 * 获取商城分类
 * @param {Object} params - { flat: 1 返回扁平列表, 0 返回树形 }
 */
export function getShopCategories(params = {}) {
    return request.get('/shop-categories', { params })
}

/**
 * 获取商城分类详情
 */
export function getShopCategoryDetail(id) {
    return request.get(`/shop-categories/${id}`)
}

/**
 * 管理端 - 获取分类列表（含未启用，分页）
 */
export function adminGetShopCategories(params = {}) {
    return request.get('/shop-categories/admin/list', { params })
}

/**
 * 管理端 - 新建分类
 */
export function adminCreateShopCategory(data) {
    return request.post('/shop-categories', data)
}

/**
 * 管理端 - 更新分类
 */
export function adminUpdateShopCategory(id, data) {
    return request.put(`/shop-categories/${id}`, data)
}

/**
 * 管理端 - 删除分类
 */
export function adminDeleteShopCategory(id) {
    return request.delete(`/shop-categories/${id}`)
}

/**
 * 商品列表（搜索/筛选/排序/分页）
 * @param {Object} params - { page, limit, keyword, category_id, min_price, max_price, sort }
 */
export function getProductList(params) {
    return request.get('/products', { params })
}

/**
 * 商品详情
 */
export function getProductDetail(id) {
    return request.get(`/products/${id}`)
}

/**
 * 推荐商品
 * @param {Object} params - { type: hot|related, limit }
 */
export function getRecommendProducts(params = {}) {
    return request.get('/products/recommend', { params })
}

/**
 * 收藏商品
 */
export function favoriteProduct(productId) {
    return request.post(`/product-favorites/${productId}`)
}

/**
 * 取消收藏
 */
export function unfavoriteProduct(productId) {
    return request.delete(`/product-favorites/${productId}`)
}

/**
 * 我的收藏列表
 * @param {Object} params - { page, limit }
 */
export function getMyFavorites(params = {}) {
    return request.get('/product-favorites', { params })
}

export function getCart() {
    return request.get('/cart')
}

export function addToCart(data) {
    return request.post('/cart', data)
}

export function updateCartItem(id, data) {
    return request.put(`/cart/${id}`, data)
}

export function deleteCartItem(id) {
    return request.delete(`/cart/${id}`)
}

export function clearCart(ids) {
    return request.delete('/cart', { data: { ids } })
}

export function selectAllCart(isSelected) {
    return request.put('/cart/select-all', { is_selected: isSelected })
}

export function getAddresses() {
    return request.get('/addresses')
}

export function createAddress(data) {
    return request.post('/addresses', data)
}

export function updateAddress(id, data) {
    return request.put(`/addresses/${id}`, data)
}

export function deleteAddress(id) {
    return request.delete(`/addresses/${id}`)
}

export function createOrder(data) {
    return request.post('/orders', data)
}

export function getOrderList(params) {
    return request.get('/orders', { params })
}

export function getOrderDetail(idOrNo) {
    return request.get(`/orders/${idOrNo}`)
}

export function cancelOrder(idOrNo) {
    return request.post(`/orders/${idOrNo}/cancel`)
}

export function confirmOrder(idOrNo) {
    return request.post(`/orders/${idOrNo}/confirm`)
}

/**
 * 发起支付宝支付，返回收银台跳转链接
 * @param {string} idOrNo 订单id或订单号
 */
export function payOrder(idOrNo) {
    return request.post(`/orders/${idOrNo}/pay`)
}

/**
 * 查询支付结果
 * @param {string} idOrNo 订单id或订单号
 */
export function getPayStatus(idOrNo) {
    return request.get(`/orders/${idOrNo}/pay-status`)
}

/**
 * 申请退款
 * @param {string} idOrNo 订单id或订单号
 * @param {Object} data { reason }
 */
export function refundOrder(idOrNo, data = {}) {
    return request.post(`/orders/${idOrNo}/refund`, data)
}

export function getOrderLogs(idOrNo) {
    return request.get(`/orders/${idOrNo}/logs`)
}

export function adminGetProducts(params) {
    return request.get('/admin/products', { params })
}

/**
 * 管理端 - 商品详情（含 images / skus）
 */
export function adminGetProductDetail(id) {
    return request.get(`/admin/products/${id}`)
}

export function adminCreateProduct(data) {
    return request.post('/admin/products', data)
}

export function adminUpdateProduct(id, data) {
    return request.put(`/admin/products/${id}`, data)
}

export function adminDeleteProduct(id) {
    return request.delete(`/admin/products/${id}`)
}

export function adminUpdateProductStatus(id, status) {
    return request.patch(`/admin/products/${id}/status`, { status })
}

export function adminUpdateProductStock(id, data) {
    return request.patch(`/admin/products/${id}/stock`, data)
}

export function adminGetOrders(params) {
    return request.get('/admin/orders', { params })
}

/**
 * 管理端 - 订单详情（含 items / 买家信息 / 状态流转日志）
 * @param {string|number} idOrNo 订单 id 或订单号
 */
export function adminGetOrderDetail(idOrNo) {
    return request.get(`/admin/orders/${idOrNo}`)
}

export function adminShipOrder(id, data) {
    return request.post(`/admin/orders/${id}/ship`, data)
}

export function adminCloseOrder(id, data) {
    return request.post(`/admin/orders/${id}/close`, data)
}

/**
 * 管理端 - 订单退款
 * @param {string|number} id 订单id或订单号
 * @param {Object} data { reason }
 */
export function adminRefundOrder(id, data = {}) {
    return request.post(`/admin/orders/${id}/refund`, data)
}

export default {
    getShopCategories,
    getShopCategoryDetail,
    adminGetShopCategories,
    adminCreateShopCategory,
    adminUpdateShopCategory,
    adminDeleteShopCategory,
    getProductList,
    getProductDetail,
    getRecommendProducts,
    favoriteProduct,
    unfavoriteProduct,
    getMyFavorites
}
