<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useOrderStore } from '@/stores/order.js'
import { useUserStore } from '@/stores/user.js'
import SvgIcon from '@/components/SvgIcon.vue'
import { showShopMessage } from '@/utils/shopMessage.js'

const route = useRoute()
const router = useRouter()
const orderStore = useOrderStore()
const userStore = useUserStore()

const defaultCover = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="120" height="120"%3E%3Crect width="120" height="120" fill="%23eee"/%3E%3Ctext x="50%25" y="50%25" font-size="12" fill="%23999" text-anchor="middle" dy=".3em"%3E%E6%97%A0%E5%9B%BE%3C/text%3E%3C/svg%3E'

const order = computed(() => orderStore.current)
const logs = computed(() => orderStore.logs)
const isLoading = computed(() => orderStore.isLoading)
const submitting = computed(() => orderStore.submitting)

const statusHint = computed(() => {
    if (!order.value) return ''
    switch (order.value.status) {
        case 'pending_payment':
            return '请尽快完成支付，超时订单将自动关闭'
        case 'pending_shipment':
            return '商家正在备货，请耐心等待发货'
        case 'shipped':
            return '商品已发出，收到后请及时确认收货'
        case 'completed':
            return '订单已完成，感谢您的购买'
        case 'cancelled':
            return '订单已取消'
        case 'closed':
            return '订单已关闭'
        default:
            return ''
    }
})

const reversedLogs = computed(() => [...logs.value].reverse())

function formatTime(t) {
    if (!t) return '-'
    const d = new Date(t.replace(' ', 'T'))
    if (isNaN(d.getTime())) return t
    const pad = n => String(n).padStart(2, '0')
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

function statusClass(status) {
    return `status-${status}`
}

function goProduct(item) {
    if (!item.product_id) return
    router.push({ name: 'shop_product_detail', params: { id: item.product_id } })
}

async function handleCancel() {
    if (!order.value) return
    if (!confirm(`确定取消订单「${order.value.order_no}」？`)) return
    const res = await orderStore.cancel(order.value.order_no)
    if (res.success) {
        showShopMessage('取消成功', 'success')
        await loadLogs()
    } else {
        showShopMessage(res.message || '取消失败', 'error')
    }
}

async function handleConfirm() {
    if (!order.value) return
    if (!confirm('确认已收到商品？')) return
    const res = await orderStore.confirm(order.value.order_no)
    if (res.success) {
        showShopMessage('确认收货成功', 'success')
        await loadLogs()
    } else {
        showShopMessage(res.message || '操作失败', 'error')
    }
}

function handlePay() {
    showShopMessage('在线支付功能开发中，敬请期待', 'info')
}

async function loadLogs() {
    if (!order.value) return
    await orderStore.fetchLogs(order.value.order_no)
}

function goBack() {
    if (window.history.length > 1) {
        router.back()
    } else {
        router.push({ name: 'shop_orders' })
    }
}

function goOrderList() {
    router.push({ name: 'shop_orders' })
}

function handleImgError(e) {
    e.target.src = defaultCover
}

async function loadAll() {
    if (!userStore.isLoggedIn) {
        showShopMessage('请先登录', 'warning')
        router.push({ name: 'shop_home' })
        return
    }
    const key = route.params.id
    if (!key) {
        showShopMessage('订单参数错误', 'error')
        router.replace({ name: 'shop_orders' })
        return
    }
    const res = await orderStore.fetchDetail(key)
    if (!res.success) {
        showShopMessage(res.message || '订单不存在', 'error')
        router.replace({ name: 'shop_orders' })
        return
    }
    await loadLogs()
}

onMounted(loadAll)
</script>

<template>
    <div class="order-detail-page">
        <div class="back-bar">
            <button class="back-btn" @click="goBack">
                <SvgIcon name="left" width="18" height="18" /> 返回
            </button>
            <button class="link-btn" @click="goOrderList">订单列表</button>
        </div>

        <div v-if="isLoading && !order" class="state-text">加载中...</div>

        <div v-else-if="!order" class="state-text">
            <p>订单不存在</p>
        </div>

        <template v-else>
            <section class="status-header" :class="statusClass(order.status)">
                <div class="status-title">{{ order.status_text }}</div>
                <div v-if="statusHint" class="status-hint">{{ statusHint }}</div>
                <div v-if="order.tracking_no" class="tracking-info">
                    物流：{{ order.tracking_company || '-' }} {{ order.tracking_no }}
                </div>
            </section>

            <section class="block">
                <h2 class="block-title">收货信息</h2>
                <div class="address-info">
                    <div class="address-top">
                        <span class="receiver">{{ order.receiver }}</span>
                        <span class="phone">{{ order.phone }}</span>
                    </div>
                    <div class="address-detail">{{ order.address }}</div>
                </div>
            </section>

            <section class="block">
                <h2 class="block-title">商品清单</h2>
                <div class="goods-list">
                    <div
                        v-for="item in order.items"
                        :key="item.id"
                        class="goods-item"
                        @click="goProduct(item)"
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
                            <div class="goods-subtotal">¥{{ item.subtotal }}</div>
                        </div>
                    </div>
                </div>
            </section>

            <section class="block amount-block">
                <div class="amount-row">
                    <span>商品总额</span>
                    <span>¥{{ order.total_amount }}</span>
                </div>
                <div class="amount-row">
                    <span>运费</span>
                    <span class="free">{{ Number(order.shipping_fee) === 0 ? '免运费' : '¥' + order.shipping_fee }}</span>
                </div>
                <div class="amount-row total">
                    <span>实付款</span>
                    <span class="pay-amount">¥{{ order.pay_amount }}</span>
                </div>
            </section>

            <section class="block info-block">
                <h2 class="block-title">订单信息</h2>
                <div class="info-row">
                    <span class="info-label">订单编号</span>
                    <span class="info-value">{{ order.order_no }}</span>
                </div>
                <div class="info-row">
                    <span class="info-label">下单时间</span>
                    <span class="info-value">{{ formatTime(order.created_at) }}</span>
                </div>
                <div v-if="order.paid_at" class="info-row">
                    <span class="info-label">付款时间</span>
                    <span class="info-value">{{ formatTime(order.paid_at) }}</span>
                </div>
                <div v-if="order.shipped_at" class="info-row">
                    <span class="info-label">发货时间</span>
                    <span class="info-value">{{ formatTime(order.shipped_at) }}</span>
                </div>
                <div v-if="order.completed_at" class="info-row">
                    <span class="info-label">完成时间</span>
                    <span class="info-value">{{ formatTime(order.completed_at) }}</span>
                </div>
                <div v-if="order.cancelled_at" class="info-row">
                    <span class="info-label">取消时间</span>
                    <span class="info-value">{{ formatTime(order.cancelled_at) }}</span>
                </div>
                <div v-if="order.remark" class="info-row">
                    <span class="info-label">买家备注</span>
                    <span class="info-value">{{ order.remark }}</span>
                </div>
            </section>

            <section v-if="logs.length > 0" class="block timeline-block">
                <h2 class="block-title">订单轨迹</h2>
                <div class="timeline">
                    <div
                        v-for="(log, idx) in reversedLogs"
                        :key="log.id"
                        class="timeline-item"
                        :class="{ first: idx === 0 }"
                    >
                        <div class="timeline-dot"></div>
                        <div class="timeline-content">
                            <div class="timeline-status">
                                {{ log.to_status_text }}
                                <span v-if="log.from_status_text" class="timeline-from">
                                    （由{{ log.from_status_text }}变更）
                                </span>
                            </div>
                            <div v-if="log.remark" class="timeline-remark">{{ log.remark }}</div>
                            <div class="timeline-time">{{ formatTime(log.created_at) }}</div>
                        </div>
                    </div>
                </div>
            </section>

            <div class="action-bar" v-if="['pending_payment', 'shipped'].includes(order.status)">
                <div class="action-bar-inner">
                    <button
                        v-if="order.status === 'pending_payment'"
                        class="action-btn default"
                        :disabled="submitting"
                        @click="handleCancel"
                    >
                        取消订单
                    </button>
                    <button
                        v-if="order.status === 'pending_payment'"
                        class="action-btn primary"
                        @click="handlePay"
                    >
                        去支付
                    </button>
                    <button
                        v-if="order.status === 'shipped'"
                        class="action-btn primary"
                        :disabled="submitting"
                        @click="handleConfirm"
                    >
                        {{ submitting ? '处理中...' : '确认收货' }}
                    </button>
                </div>
            </div>
        </template>
    </div>
</template>

<style scoped>
.order-detail-page {
    padding: 72px 24px 24px;
    width: 100%;
    box-sizing: border-box;
}

.back-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 16px;
}

.back-btn {
    display: flex;
    align-items: center;
    gap: 4px;
    background: transparent;
    color: var(--text-color-secondary);
    border: none;
    cursor: pointer;
    font-size: 14px;
    padding: 6px 0;
}

.link-btn {
    background: none;
    border: none;
    color: var(--primary-color);
    font-size: 13px;
    cursor: pointer;
}

.state-text {
    text-align: center;
    color: var(--text-color-tertiary, #999);
    padding: 80px 0;
    font-size: 14px;
}

.status-header {
    background: var(--primary-color);
    color: var(--text-color-inverse);
    border-radius: 12px;
    padding: 24px 20px;
    margin-bottom: 12px;
}

.status-header.status-pending_payment {
    background: var(--series-warning);
}

.status-header.status-pending_shipment {
    background: var(--series-info);
}

.status-header.status-completed {
    background: var(--series-positive);
}

.status-header.status-cancelled,
.status-header.status-closed {
    background: var(--series-neutral);
}

.status-title {
    font-size: 22px;
    font-weight: 700;
    margin-bottom: 6px;
}

.status-hint {
    font-size: 13px;
    opacity: 0.9;
}

.tracking-info {
    font-size: 12px;
    opacity: 0.85;
    margin-top: 8px;
}

.block {
    background: var(--bg-color-secondary);
    border-radius: 12px;
    padding: 16px;
    margin-bottom: 12px;
}

.block-title {
    font-size: 16px;
    font-weight: 600;
    margin: 0 0 12px;
    color: var(--text-color-primary);
}

.address-info {
    display: flex;
    flex-direction: column;
    gap: 6px;
}

.address-top {
    display: flex;
    gap: 12px;
    align-items: center;
}

.receiver {
    font-weight: 600;
    color: var(--text-color-primary);
    font-size: 15px;
}

.phone {
    font-size: 14px;
    color: var(--text-color-secondary);
}

.address-detail {
    font-size: 13px;
    color: var(--text-color-secondary);
    line-height: 1.5;
}

.goods-list {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.goods-item {
    display: flex;
    gap: 12px;
    cursor: pointer;
}

.goods-cover {
    width: 64px;
    height: 64px;
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
    margin-top: 2px;
}

.goods-subtotal {
    font-size: 13px;
    color: var(--primary-color);
    font-weight: 600;
    margin-top: 4px;
}

.amount-block {
    padding: 12px 16px;
}

.amount-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 6px 0;
    font-size: 14px;
    color: var(--text-color-secondary);
}

.amount-row.total {
    border-top: 1px solid var(--border-color-primary, #eee);
    margin-top: 4px;
    padding-top: 10px;
    font-weight: 600;
    color: var(--text-color-primary);
}

.free {
    color: var(--text-color-tertiary, #999);
}

.pay-amount {
    color: var(--primary-color);
    font-size: 18px;
    font-weight: 700;
}

.info-block {
    padding: 16px;
}

.info-row {
    display: flex;
    padding: 6px 0;
    font-size: 13px;
}

.info-label {
    width: 80px;
    color: var(--text-color-tertiary, #999);
    flex-shrink: 0;
}

.info-value {
    color: var(--text-color-secondary);
    word-break: break-all;
}

.timeline-block {
    padding: 16px;
}

.timeline {
    position: relative;
    padding-left: 20px;
}

.timeline-item {
    position: relative;
    padding-bottom: 20px;
    padding-left: 12px;
}

.timeline-item:not(:last-child)::before {
    content: '';
    position: absolute;
    left: 4px;
    top: 12px;
    bottom: 0;
    width: 2px;
    background: var(--border-color-primary, #eee);
}

.timeline-dot {
    position: absolute;
    left: 0;
    top: 4px;
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--text-color-tertiary, #ccc);
    border: 2px solid var(--bg-color-secondary);
}

.timeline-item.first .timeline-dot {
    background: var(--primary-color);
}

.timeline-content {
    display: flex;
    flex-direction: column;
    gap: 2px;
}

.timeline-status {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-color-primary);
}

.timeline-from {
    font-size: 12px;
    font-weight: 400;
    color: var(--text-color-tertiary, #999);
}

.timeline-remark {
    font-size: 12px;
    color: var(--text-color-secondary);
}

.timeline-time {
    font-size: 12px;
    color: var(--text-color-tertiary, #999);
}

.action-bar {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    background: var(--bg-color-primary);
    border-top: 1px solid var(--border-color-primary, #eee);
    z-index: 100;
}

.action-bar-inner {
    max-width: 1200px;
    margin: 0 auto;
    padding: 12px 24px;
    display: flex;
    justify-content: flex-end;
    gap: 12px;
    box-sizing: border-box;
}

.action-btn {
    border-radius: 999px;
    padding: 10px 28px;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
}

.action-btn.primary {
    background: var(--primary-color);
    color: #fff;
    border: none;
}

.action-btn.default {
    background: var(--bg-color-primary);
    color: var(--text-color-secondary);
    border: 1px solid var(--border-color-primary, #ddd);
}

.action-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

@media (min-width: 961px) {
    .action-bar {
        left: 228px;
        width: calc(100% - 228px);
    }
}
</style>
