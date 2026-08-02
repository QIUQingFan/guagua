<script setup>
import { computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useCartStore } from '@/stores/cart.js'
import { useUserStore } from '@/stores/user.js'
import SvgIcon from '@/components/SvgIcon.vue'
import { showShopMessage } from '@/utils/shopMessage.js'

const router = useRouter()
const cartStore = useCartStore()
const userStore = useUserStore()

const defaultCover = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="120" height="120"%3E%3Crect width="120" height="120" fill="%23eee"/%3E%3Ctext x="50%25" y="50%25" font-size="12" fill="%23999" text-anchor="middle" dy=".3em"%3E%E6%97%A0%E5%9B%BE%3C/text%3E%3C/svg%3E'

const items = computed(() => cartStore.items)
const invalidItems = computed(() => cartStore.invalidItems)
const allSelected = computed(() => cartStore.allSelected)
const selectedAmount = computed(() => cartStore.selectedAmount)
const selectedQuantity = computed(() => cartStore.selectedQuantity)

function isItemInvalid(item) {
    return invalidItems.value.some(i => i.id === item.id)
}

function getInvalidReason(item) {
    const found = invalidItems.value.find(i => i.id === item.id)
    return found ? found.reason : ''
}

async function toggleSelect(item) {
    const next = Number(item.is_selected) !== 1
    await cartStore.toggleSelect(item.id, next)
}

async function toggleSelectAll() {
    await cartStore.toggleSelectAll(!allSelected.value)
}

async function changeQuantity(item, delta) {
    const next = Number(item.quantity) + delta
    if (next < 1) return
    const stock = Number(item.product?.stock || 0)
    if (delta > 0 && next > stock) {
        showShopMessage('已达库存上限', 'warning')
        return
    }
    await cartStore.updateQuantity(item.id, next)
}

async function removeItem(item) {
    if (!confirm(`确定从购物车移除「${item.product?.title || '该商品'}」？`)) return
    const res = await cartStore.removeItem(item.id)
    if (res.success) showShopMessage('已移除', 'success')
}

async function removeInvalid() {
    const ids = invalidItems.value.map(i => i.id)
    if (ids.length === 0) return
    const res = await cartStore.removeItems(ids)
    if (res.success) showShopMessage('已清理失效商品', 'success')
}

function goCheckout() {
    if (selectedQuantity.value === 0) {
        showShopMessage('请先选择商品', 'warning')
        return
    }
    router.push({ name: 'shop_checkout' })
}

function goShopping() {
    router.push({ name: 'shop_home' })
}

function goDetail(item) {
    router.push({ name: 'shop_product_detail', params: { id: item.product_id } })
}

function handleImgError(e) {
    e.target.src = defaultCover
}

onMounted(() => {
    if (userStore.isLoggedIn) {
        cartStore.fetchCart()
    } else {
        cartStore.reset()
    }
})
</script>

<template>
    <div class="cart-page">
        <div class="page-head">
            <h1 class="page-title">购物车</h1>
        </div>

        <div v-if="cartStore.isLoading && items.length === 0" class="state-text">加载中...</div>

        <div v-else-if="items.length === 0" class="empty-state">
            <SvgIcon name="cart" width="64" height="64" class="empty-icon" v-if="false" />
            <div class="empty-emoji">🛒</div>
            <p class="empty-text">购物车空空如也</p>
            <button class="primary-btn" @click="goShopping">去逛逛</button>
        </div>

        <template v-else>
            <div v-if="invalidItems.length > 0" class="invalid-section">
                <div class="invalid-header">
                    <span>失效商品（{{ invalidItems.length }} 件）</span>
                    <button class="link-btn" @click="removeInvalid">清空失效</button>
                </div>
                <div v-for="inv in invalidItems" :key="inv.id" class="invalid-item">
                    <span class="invalid-tag">{{ inv.reason }}</span>
                    <span class="invalid-id">商品ID: {{ inv.product_id }}</span>
                </div>
            </div>

            <div class="cart-list">
                <div v-for="item in items" :key="item.id" class="cart-item" :class="{ invalid: isItemInvalid(item) }">
                    <label class="check-box" v-if="!isItemInvalid(item)">
                        <input
                            type="checkbox"
                            :checked="Number(item.is_selected) === 1"
                            @change="toggleSelect(item)"
                        />
                        <span class="check-mark"></span>
                    </label>
                    <div class="item-cover" @click="goDetail(item)">
                        <img :src="item.product?.cover_image || defaultCover" :alt="item.product?.title" @error="handleImgError" />
                    </div>
                    <div class="item-info">
                        <div class="item-title" @click="goDetail(item)">{{ item.product?.title || '商品已失效' }}</div>
                        <div v-if="item.product?.spec" class="item-spec">{{ item.product.spec }}</div>
                        <div v-if="isItemInvalid(item)" class="item-invalid-reason">{{ getInvalidReason(item) }}</div>
                        <div class="item-bottom">
                            <span class="item-price">¥{{ item.product?.price || '0.00' }}</span>
                            <div v-if="!isItemInvalid(item)" class="qty-control">
                                <button class="qty-btn" :disabled="Number(item.quantity) <= 1" @click="changeQuantity(item, -1)">-</button>
                                <span class="qty-value">{{ item.quantity }}</span>
                                <button class="qty-btn" :disabled="Number(item.quantity) >= Number(item.product?.stock || 0)" @click="changeQuantity(item, 1)">+</button>
                            </div>
                        </div>
                    </div>
                    <div class="item-actions">
                        <div class="item-subtotal" v-if="!isItemInvalid(item)">
                            ¥{{ (Number(item.product?.price || 0) * Number(item.quantity)).toFixed(2) }}
                        </div>
                        <button class="del-btn" @click="removeItem(item)">删除</button>
                    </div>
                </div>
            </div>

            <div class="checkout-bar">
                <div class="checkout-bar-inner">
                    <label class="check-box select-all">
                        <input type="checkbox" :checked="allSelected" @change="toggleSelectAll" />
                        <span class="check-mark"></span>
                        <span class="check-label">全选</span>
                    </label>
                    <div class="bar-right">
                        <div class="total-info">
                            <span class="total-label">合计：</span>
                            <span class="total-amount">¥{{ selectedAmount }}</span>
                        </div>
                        <button class="checkout-btn" :disabled="selectedQuantity === 0" @click="goCheckout">
                            结算（{{ selectedQuantity }}）
                        </button>
                    </div>
                </div>
            </div>
        </template>
    </div>
</template>

<style scoped>
.cart-page {
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

.empty-emoji {
    font-size: 64px;
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

.invalid-section {
    background: rgba(245, 108, 108, 0.06);
    border-radius: 12px;
    padding: 12px 16px;
    margin-bottom: 16px;
}

.invalid-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 13px;
    color: var(--text-color-tertiary, #999);
    margin-bottom: 8px;
}

.link-btn {
    background: none;
    border: none;
    color: var(--primary-color);
    cursor: pointer;
    font-size: 13px;
}

.invalid-item {
    display: flex;
    gap: 8px;
    font-size: 12px;
    color: var(--text-color-tertiary, #999);
    padding: 4px 0;
}

.invalid-tag {
    color: #f56c6c;
}

.cart-list {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.cart-item {
    display: flex;
    align-items: center;
    gap: 12px;
    background: var(--bg-color-secondary);
    border-radius: 12px;
    padding: 12px;
}

.cart-item.invalid {
    opacity: 0.6;
}

.check-box {
    position: relative;
    display: flex;
    align-items: center;
    cursor: pointer;
    flex-shrink: 0;
    width: 20px;
    height: 20px;
}

.check-box input {
    position: absolute;
    opacity: 0;
    width: 100%;
    height: 100%;
    margin: 0;
    cursor: pointer;
}

.check-mark {
    width: 20px;
    height: 20px;
    border: 2px solid #ccc;
    border-radius: 50%;
    display: inline-block;
    position: relative;
    transition: all 0.2s;
}

.check-box input:checked + .check-mark {
    background: var(--primary-color);
    border-color: var(--primary-color);
}

.check-box input:checked + .check-mark::after {
    content: '';
    position: absolute;
    left: 6px;
    top: 2px;
    width: 5px;
    height: 10px;
    border: solid #fff;
    border-width: 0 2px 2px 0;
    transform: rotate(45deg);
}

.item-cover {
    width: 80px;
    height: 80px;
    border-radius: 8px;
    overflow: hidden;
    background: #f5f5f5;
    cursor: pointer;
    flex-shrink: 0;
}

.item-cover img {
    width: 100%;
    height: 100%;
    object-fit: cover;
}

.item-info {
    flex: 1;
    min-width: 0;
}

.item-title {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-color-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    cursor: pointer;
}

.item-spec {
    font-size: 12px;
    color: var(--text-color-tertiary, #999);
    margin-top: 4px;
    background: var(--bg-color-primary, #f5f5f5);
    display: inline-block;
    padding: 2px 8px;
    border-radius: 4px;
}

.item-invalid-reason {
    font-size: 12px;
    color: #f56c6c;
    margin-top: 4px;
}

.item-bottom {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-top: 8px;
}

.item-price {
    font-size: 16px;
    font-weight: 700;
    color: var(--primary-color);
}

.qty-control {
    display: flex;
    align-items: center;
    border: 1px solid var(--border-color-primary, #eee);
    border-radius: 6px;
    overflow: hidden;
}

.qty-btn {
    width: 28px;
    height: 28px;
    border: none;
    background: var(--bg-color-primary, #f5f5f5);
    color: var(--text-color-primary);
    font-size: 16px;
    cursor: pointer;
}

.qty-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
}

.qty-value {
    width: 40px;
    text-align: center;
    font-size: 14px;
    color: var(--text-color-primary);
}

.item-actions {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 8px;
    flex-shrink: 0;
}

.item-subtotal {
    font-size: 15px;
    font-weight: 700;
    color: var(--primary-color);
}

.del-btn {
    background: none;
    border: none;
    color: var(--text-color-tertiary, #999);
    font-size: 13px;
    cursor: pointer;
}

.del-btn:hover {
    color: #f56c6c;
}

.checkout-bar {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    background: var(--bg-color-primary);
    border-top: 1px solid var(--border-color-primary, #eee);
    z-index: 100;
}

.checkout-bar-inner {
    max-width: 1200px;
    margin: 0 auto;
    padding: 12px 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    box-sizing: border-box;
}

.select-all {
    width: auto;
    gap: 8px;
}

.check-label {
    font-size: 14px;
    color: var(--text-color-primary);
}

.bar-right {
    display: flex;
    align-items: center;
    gap: 16px;
}

.total-info {
    display: flex;
    align-items: baseline;
    gap: 4px;
}

.total-label {
    font-size: 14px;
    color: var(--text-color-secondary);
}

.total-amount {
    font-size: 20px;
    font-weight: 700;
    color: var(--primary-color);
}

.checkout-btn {
    background: var(--primary-color);
    color: #fff;
    border: none;
    border-radius: 999px;
    padding: 10px 32px;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
}

.checkout-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

@media (min-width: 961px) {
    .checkout-bar {
        left: 228px;
        width: calc(100% - 228px);
    }
}

@media (max-width: 768px) {
    .item-cover {
        width: 64px;
        height: 64px;
    }
    .item-spec {
        max-width: 100%;
    }
}
</style>
