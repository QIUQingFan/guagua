<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useOrderStore } from '@/stores/order.js'
import { useUserStore } from '@/stores/user.js'
import { useAuthStore } from '@/stores/auth.js'
import { getOrderList } from '@/api/shop.js'
import { showShopMessage } from '@/utils/shopMessage.js'

const route = useRoute()
const router = useRouter()
const orderStore = useOrderStore()
const userStore = useUserStore()
const authStore = useAuthStore()

const defaultCover = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="120" height="120"%3E%3Crect width="120" height="120" fill="%23eee"/%3E%3Ctext x="50%25" y="50%25" font-size="12" fill="%23999" text-anchor="middle" dy=".3em"%3E%E6%97%A0%E5%9B%BE%3C/text%3E%3C/svg%3E'

const tabs = [
    { label: '全部', status: '' },
    { label: '待付款', status: 'pending_payment' },
    { label: '待发货', status: 'pending_shipment' },
    { label: '待收货', status: 'shipped' },
    { label: '已完成', status: 'completed' },
    { label: '已关闭', status: 'cancelled,closed' }
]

const activeTab = ref(0)
const page = ref(1)
const limit = 10
const hasMore = ref(false)
const loadingMore = ref(false)

const list = computed(() => orderStore.list)
const total = computed(() => orderStore.total)
const isLoading = computed(() => orderStore.isLoading)

const activeStatus = computed(() => tabs[activeTab.value].status)

function pickTabFromQuery() {
    const q = route.query.status
    if (!q) return 0
    const idx = tabs.findIndex(t => t.status === q)
    return idx >= 0 ? idx : 0
}

async function loadList(reset = true) {
    if (!userStore.isLoggedIn) return
    if (reset) {
        page.value = 1
    }
    const params = {
        page: page.value,
        limit
    }
    if (activeStatus.value) params.status = activeStatus.value

    await orderStore.fetchList(params)
    const totalPages = Math.ceil(total.value / limit) || 0
    hasMore.value = page.value < totalPages
}

async function switchTab(idx) {
    if (idx === activeTab.value) return
    activeTab.value = idx
    const query = { ...route.query }
    if (tabs[idx].status) query.status = tabs[idx].status
    else delete query.status
    router.replace({ name: 'shop_orders', query })
    await loadList(true)
}

async function loadMore() {
    page.value += 1
    loadingMore.value = true
    const params = { page: page.value, limit }
    if (activeStatus.value) params.status = activeStatus.value
    try {
        const res = await getOrderList(params)
        if (res.success) {
            orderStore.list.push(...(res.data?.data || []))
            const totalPages = Math.ceil((res.data?.total || 0) / limit) || 0
            hasMore.value = page.value < totalPages
        }
    } finally {
        loadingMore.value = false
    }
}

function goDetail(order) {
    router.push({ name: 'shop_order_detail', params: { id: order.order_no } })
}

function goProduct(item) {
    if (!item.product_id) return
    router.push({ name: 'shop_product_detail', params: { id: item.product_id } })
}

async function handleCancel(order, e) {
    e.stopPropagation()
    if (!confirm(`确定取消订单「${order.order_no}」？`)) return
    const res = await orderStore.cancel(order.order_no)
    if (res.success) {
        showShopMessage('取消成功', 'success')
        await loadList(true)
    } else {
        showShopMessage(res.message || '取消失败', 'error')
    }
}

async function handleConfirm(order, e) {
    e.stopPropagation()
    if (!confirm('确认已收到商品？')) return
    const res = await orderStore.confirm(order.order_no)
    if (res.success) {
        showShopMessage('确认收货成功', 'success')
        await loadList(true)
    } else {
        showShopMessage(res.message || '操作失败', 'error')
    }
}

async function handlePay(order, e) {
    e.stopPropagation()
    showShopMessage('正在生成支付链接...', 'info')
    const res = await orderStore.pay(order.order_no)
    if (res.success && res.data?.pay_url) {
        window.open(res.data.pay_url, '_blank')
        showShopMessage('已在新窗口打开支付宝收银台', 'success')
    } else {
        showShopMessage(res.message || '发起支付失败', 'error')
    }
}

async function handleRefund(order, e) {
    e.stopPropagation()
    const reason = prompt(`确定对订单「${order.order_no}」申请全额退款吗？\n退款金额将原路退回您的支付宝账户。\n（可选）填写退款原因：`, '')
    if (reason === null) return
    const payload = reason === '' ? {} : { reason }
    const res = await orderStore.refund(order.order_no, payload)
    if (res.success) {
        showShopMessage('退款成功，款项已原路退回', 'success')
        await loadList(true)
    } else {
        showShopMessage(res.message || '退款失败', 'error')
    }
}

function onAction(key, order, e) {
    if (key === 'pay') return handlePay(order, e)
    if (key === 'cancel') return handleCancel(order, e)
    if (key === 'confirm') return handleConfirm(order, e)
    if (key === 'refund') return handleRefund(order, e)
}

function orderActions(order) {
    const actions = []
    switch (order.status) {
        case 'pending_payment':
            actions.push({ key: 'pay', label: '去支付', type: 'primary' })
            actions.push({ key: 'cancel', label: '取消订单', type: 'default' })
            break
        case 'pending_shipment':
            actions.push({ key: 'refund', label: '申请退款', type: 'default' })
            break
        case 'shipped':
            actions.push({ key: 'confirm', label: '确认收货', type: 'primary' })
            actions.push({ key: 'refund', label: '申请退款', type: 'default' })
            break
        case 'completed':
            if (order.refund_status !== 'refunded') {
                actions.push({ key: 'refund', label: '申请退款', type: 'default' })
            }
            break
        default:
            break
    }
    return actions
}

function statusClass(status) {
    return `status-${status}`
}

function handleImgError(e) {
    e.target.src = defaultCover
}

watch(() => route.query.status, () => {
    const idx = pickTabFromQuery()
    if (idx !== activeTab.value) {
        activeTab.value = idx
        loadList(true)
    }
})

onMounted(() => {
    if (!userStore.isLoggedIn) {
        authStore.openLoginModal()
        return
    }
    activeTab.value = pickTabFromQuery()
    loadList(true)
})
</script>

<template>
    <div class="order-list-page">
        <div class="page-head">
            <h1 class="page-title">我的订单</h1>
        </div>

        <div class="tabs">
            <button
                v-for="(tab, idx) in tabs"
                :key="tab.status"
                class="tab-item"
                :class="{ active: activeTab === idx }"
                @click="switchTab(idx)"
            >
                {{ tab.label }}
            </button>
        </div>

        <div v-if="isLoading && list.length === 0" class="state-text">加载中...</div>

        <div v-else-if="list.length === 0" class="empty-state">
            <p class="empty-text">暂无相关订单</p>
            <button class="primary-btn" @click="router.push({ name: 'shop_home' })">去逛逛</button>
        </div>

        <template v-else>
            <div class="order-list">
                <div
                    v-for="order in list"
                    :key="order.id"
                    class="order-card"
                    @click="goDetail(order)"
                >
                    <div class="order-header">
                        <span class="order-no">订单号：{{ order.order_no }}</span>
                        <span class="order-status" :class="statusClass(order.status)">
                            {{ order.status_text }}
                        </span>
                    </div>

                    <div class="order-goods">
                        <div
                            v-for="item in order.items"
                            :key="item.id || item.product_id"
                            class="goods-item"
                            @click.stop="goProduct(item)"
                        >
                            <div class="goods-cover">
                                <img :src="item.product_image || defaultCover" :alt="item.product_title" @error="handleImgError" />
                            </div>
                            <div class="goods-info">
                                <div class="goods-title">{{ item.product_title }}</div>
                                <div v-if="item.spec" class="goods-spec">{{ item.spec }}</div>
                            </div>
                            <div class="goods-right">
                                <div class="goods-price">¥{{ item.unit_price }}</div>
                                <div class="goods-qty">×{{ item.quantity }}</div>
                            </div>
                        </div>
                    </div>

                    <div class="order-footer">
                        <div class="order-summary">
                            <span class="summary-qty">共 {{ order.total_quantity }} 件</span>
                            <span class="summary-amount">
                                实付：<em>¥{{ order.pay_amount }}</em>
                            </span>
                            <span v-if="order.refund_status === 'refunded'" class="summary-refund">
                                已退款 ¥{{ order.refund_amount }}
                            </span>
                        </div>
                        <div class="order-actions" v-if="orderActions(order).length">
                            <button
                                v-for="act in orderActions(order)"
                                :key="act.key"
                                :class="['action-btn', act.type]"
                                @click.stop="onAction(act.key, order, $event)"
                            >
                                {{ act.label }}
                            </button>
                        </div>
                    </div>
                </div>
            </div>

            <div v-if="hasMore" class="load-more">
                <button class="load-more-btn" :disabled="loadingMore" @click="loadMore">
                    {{ loadingMore ? '加载中...' : '加载更多' }}
                </button>
            </div>
            <div v-else-if="list.length > 0" class="no-more">没有更多了</div>
        </template>
    </div>
</template>

<style scoped>
.order-list-page {
    padding: 72px 24px 24px;
    width: 100%;
    box-sizing: border-box;
}

.page-title {
    font-size: 24px;
    font-weight: 700;
    margin: 0 0 16px;
    color: var(--text-color-primary);
}

.tabs {
    display: flex;
    gap: 8px;
    overflow-x: auto;
    margin-bottom: 16px;
    padding-bottom: 4px;
    -webkit-overflow-scrolling: touch;
}

.tab-item {
    flex-shrink: 0;
    background: var(--bg-color-secondary);
    border: none;
    border-radius: 999px;
    padding: 8px 18px;
    font-size: 14px;
    color: var(--text-color-secondary);
    cursor: pointer;
    transition: all 0.2s;
}

.tab-item.active {
    background: var(--primary-color);
    color: #fff;
}

.state-text {
    text-align: center;
    color: var(--text-color-tertiary, #999);
    padding: 60px 0;
}

.empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    padding: 80px 0;
}

.empty-text {
    color: var(--text-color-tertiary, #999);
    font-size: 15px;
    margin: 0;
}

.primary-btn {
    background: var(--primary-color);
    color: #fff;
    border: none;
    border-radius: 999px;
    padding: 10px 32px;
    font-size: 14px;
    cursor: pointer;
}

.order-list {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.order-card {
    background: var(--bg-color-secondary);
    border-radius: 12px;
    padding: 16px;
    cursor: pointer;
    transition: box-shadow 0.2s;
}

.order-card:hover {
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.06);
}

.order-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-bottom: 12px;
    border-bottom: 1px solid var(--border-color-primary, #eee);
    margin-bottom: 12px;
}

.order-no {
    font-size: 13px;
    color: var(--text-color-tertiary, #999);
}

.order-status {
    font-size: 13px;
    font-weight: 600;
    padding: 2px 10px;
    border-radius: 4px;
}

.status-pending_payment {
    color: var(--series-warning);
    background: rgba(245, 158, 11, 0.12);
}

.status-pending_shipment {
    color: var(--series-info);
    background: rgba(59, 130, 246, 0.12);
}

.status-shipped {
    color: var(--primary-color);
    background: rgba(var(--primary-color-rgb), 0.08);
}

.status-completed {
    color: var(--series-positive);
    background: rgba(16, 185, 129, 0.12);
}

.status-cancelled,
.status-closed {
    color: var(--text-color-tertiary);
    background: rgba(107, 114, 128, 0.12);
}

.order-goods {
    display: flex;
    flex-direction: column;
    gap: 10px;
}

.goods-item {
    display: flex;
    gap: 10px;
}

.goods-cover {
    width: 56px;
    height: 56px;
    border-radius: 8px;
    overflow: hidden;
    background: #f5f5f5;
    flex-shrink: 0;
}

.goods-cover img {
    width: 100%;
    height: 100%;
    object-fit: cover;
}

.goods-info {
    flex: 1;
    min-width: 0;
}

.goods-title {
    font-size: 14px;
    color: var(--text-color-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    line-clamp: 2;
}

.goods-spec {
    font-size: 12px;
    color: var(--text-color-tertiary, #999);
    margin-top: 4px;
}

.goods-right {
    text-align: right;
    flex-shrink: 0;
}

.goods-price {
    font-size: 14px;
    color: var(--text-color-primary);
}

.goods-qty {
    font-size: 12px;
    color: var(--text-color-tertiary, #999);
    margin-top: 4px;
}

.order-footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: 12px;
    padding-top: 12px;
    border-top: 1px solid var(--border-color-primary, #eee);
    flex-wrap: wrap;
    gap: 10px;
}

.order-summary {
    display: flex;
    flex-direction: column;
    gap: 2px;
}

.summary-qty {
    font-size: 12px;
    color: var(--text-color-tertiary, #999);
}

.summary-amount {
    font-size: 14px;
    color: var(--text-color-primary);
}

.summary-amount em {
    color: var(--primary-color);
    font-size: 17px;
    font-weight: 700;
    font-style: normal;
}

.summary-refund {
    font-size: 12px;
    color: var(--series-warning, #f59e0b);
    font-weight: 600;
}

.order-actions {
    display: flex;
    gap: 8px;
}

.action-btn {
    border-radius: 999px;
    padding: 6px 18px;
    font-size: 13px;
    cursor: pointer;
    border: 1px solid var(--border-color-primary, #ddd);
}

.action-btn.primary {
    background: var(--primary-color);
    color: #fff;
    border-color: var(--primary-color);
}

.action-btn.default {
    background: var(--bg-color-primary);
    color: var(--text-color-secondary);
}

.action-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

.load-more {
    text-align: center;
    padding: 20px 0;
}

.load-more-btn {
    background: var(--bg-color-secondary);
    border: 1px solid var(--border-color-primary, #eee);
    border-radius: 999px;
    padding: 8px 32px;
    font-size: 14px;
    color: var(--text-color-secondary);
    cursor: pointer;
}

.load-more-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

.no-more {
    text-align: center;
    color: var(--text-color-tertiary, #999);
    font-size: 13px;
    padding: 20px 0;
}

@media (max-width: 768px) {
    .goods-cover {
        width: 48px;
        height: 48px;
    }
}
</style>
