<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useCartStore } from '@/stores/cart.js'
import { useOrderStore } from '@/stores/order.js'
import { useUserStore } from '@/stores/user.js'
import { getAddresses, getProductDetail } from '@/api/shop.js'
import SvgIcon from '@/components/SvgIcon.vue'
import { showShopMessage } from '@/utils/shopMessage.js'

const route = useRoute()
const router = useRouter()
const cartStore = useCartStore()
const orderStore = useOrderStore()
const userStore = useUserStore()

const defaultCover = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="120" height="120"%3E%3Crect width="120" height="120" fill="%23eee"/%3E%3Ctext x="50%25" y="50%25" font-size="12" fill="%23999" text-anchor="middle" dy=".3em"%3E%E6%97%A0%E5%9B%BE%3C/text%3E%3C/svg%3E'

const isBuyNow = computed(() => !!route.query.product_id)

const buyNowProduct = ref(null)
const buyNowQuantity = computed(() => Number(route.query.quantity) || 1)
const buyNowSkuId = computed(() => route.query.sku_id ? Number(route.query.sku_id) : null)

const addresses = ref([])
const selectedAddressId = ref(null)
const addressLoading = ref(false)

const selectedAddress = computed(() =>
    addresses.value.find(a => a.id === selectedAddressId.value) || null
)

const orderItems = computed(() => {
    if (isBuyNow.value) {
        if (!buyNowProduct.value) return []
        const p = buyNowProduct.value
        return [{
            product_id: p.id,
            sku_id: buyNowSkuId.value,
            quantity: buyNowQuantity.value,
            product_title: p.title,
            product_image: p.cover_image,
            spec: buyNowSkuId.value ? (p.skus?.find(s => s.id === buyNowSkuId.value)?.spec) : null,
            unit_price: buyNowSkuId.value ? (p.skus?.find(s => s.id === buyNowSkuId.value)?.price) : p.price,
            product: p
        }]
    }
    return cartStore.selectedItems.map(i => ({
        product_id: i.product_id,
        sku_id: i.sku_id,
        quantity: Number(i.quantity),
        product_title: i.product?.title,
        product_image: i.product?.cover_image,
        spec: i.product?.spec,
        unit_price: i.product?.price,
        product: i.product
    }))
})

const totalAmount = computed(() =>
    orderItems.value
        .reduce((sum, i) => sum + Number(i.unit_price || 0) * Number(i.quantity), 0)
        .toFixed(2)
)

const totalQuantity = computed(() =>
    orderItems.value.reduce((sum, i) => sum + Number(i.quantity), 0)
)

const remark = ref('')
const submitting = computed(() => orderStore.submitting)

async function loadAddresses() {
    addressLoading.value = true
    try {
        const res = await getAddresses()
        if (res.success) {
            addresses.value = res.data || []
            const def = addresses.value.find(a => a.is_default) || addresses.value[0]
            selectedAddressId.value = def ? def.id : null
        }
    } finally {
        addressLoading.value = false
    }
}

async function loadBuyNowProduct() {
    const productId = Number(route.query.product_id)
    const res = await getProductDetail(productId)
    if (res.success) {
        buyNowProduct.value = res.data
    } else {
        showShopMessage('商品信息获取失败', 'error')
        router.push({ name: 'shop_home' })
    }
}

async function submitOrder() {
    if (!userStore.isLoggedIn) {
        showShopMessage('请先登录', 'warning')
        return
    }
    if (!selectedAddressId.value) {
        showShopMessage('请选择收货地址', 'warning')
        return
    }
    if (orderItems.value.length === 0) {
        showShopMessage('没有可结算的商品', 'warning')
        return
    }

    const payload = {
        items: orderItems.value.map(i => ({
            product_id: i.product_id,
            sku_id: i.sku_id,
            quantity: i.quantity
        })),
        address_id: selectedAddressId.value,
        remark: remark.value || undefined,
        from_cart: !isBuyNow.value
    }

    const res = await orderStore.placeOrder(payload)
    if (res.success) {
        showShopMessage('下单成功', 'success')
        if (!isBuyNow.value) {
            cartStore.fetchCart()
        }
        router.replace({
            name: 'shop_order_detail',
            params: { id: res.data.order_no }
        })
    } else {
        showShopMessage(res.message || '下单失败', 'error')
    }
}

function goAddressManage() {
    router.push({ name: 'shop_addresses' })
}

function goBack() {
    router.back()
}

function handleImgError(e) {
    e.target.src = defaultCover
}

onMounted(async () => {
    if (!userStore.isLoggedIn) {
        showShopMessage('请先登录', 'warning')
        router.push({ name: 'shop_home' })
        return
    }

    if (isBuyNow.value) {
        await loadBuyNowProduct()
    } else {
        if (!cartStore.isInitialized) {
            await cartStore.fetchCart()
        }
        if (cartStore.selectedItems.length === 0) {
            showShopMessage('请先在购物车选择商品', 'warning')
            router.replace({ name: 'shop_cart' })
            return
        }
    }

    await loadAddresses()
    if (addresses.value.length === 0) {
        showShopMessage('请先添加收货地址', 'warning')
    }
})
</script>

<template>
    <div class="checkout-page">
        <div class="back-bar">
            <button class="back-btn" @click="goBack">
                <SvgIcon name="left" width="18" height="18" /> 返回
            </button>
            <h1 class="page-title">确认订单</h1>
        </div>

        <section class="block">
            <div class="block-header">
                <h2 class="block-title">收货地址</h2>
                <button class="link-btn" @click="goAddressManage">管理地址</button>
            </div>

            <div v-if="addressLoading" class="state-text">加载中...</div>

            <div v-else-if="addresses.length === 0" class="empty-address">
                <p>还没有收货地址</p>
                <button class="primary-btn" @click="goAddressManage">去添加</button>
            </div>

            <div v-else class="address-list">
                <label
                    v-for="addr in addresses"
                    :key="addr.id"
                    class="address-card"
                    :class="{ active: selectedAddressId === addr.id }"
                >
                    <input
                        type="radio"
                        name="address"
                        :value="addr.id"
                        v-model="selectedAddressId"
                    />
                    <div class="address-info">
                        <div class="address-top">
                            <span class="receiver">{{ addr.receiver }}</span>
                            <span class="phone">{{ addr.phone }}</span>
                            <span v-if="addr.is_default" class="default-tag">默认</span>
                        </div>
                        <div class="address-detail">
                            {{ addr.province }}{{ addr.city }}{{ addr.district }}{{ addr.detail }}
                        </div>
                    </div>
                </label>
            </div>
        </section>

        <section class="block">
            <h2 class="block-title">商品清单</h2>
            <div v-if="orderItems.length === 0" class="state-text">没有可结算的商品</div>
            <div v-else class="goods-list">
                <div v-for="(item, idx) in orderItems" :key="idx" class="goods-item">
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
        </section>

        <section class="block">
            <h2 class="block-title">订单备注</h2>
            <textarea
                v-model="remark"
                class="remark-input"
                placeholder="选填，给商家留言（最多100字）"
                maxlength="100"
                rows="2"
            ></textarea>
        </section>

        <section class="block amount-block">
            <div class="amount-row">
                <span>商品金额</span>
                <span>¥{{ totalAmount }}</span>
            </div>
            <div class="amount-row">
                <span>运费</span>
                <span class="free">免运费</span>
            </div>
            <div class="amount-row total">
                <span>应付金额</span>
                <span class="pay-amount">¥{{ totalAmount }}</span>
            </div>
        </section>

        <div class="submit-bar">
            <div class="submit-bar-inner">
                <div class="submit-left">
                    <span class="submit-qty">共 {{ totalQuantity }} 件</span>
                    <span class="submit-total">合计：<em>¥{{ totalAmount }}</em></span>
                </div>
                <button class="submit-btn" :disabled="submitting || !selectedAddressId || orderItems.length === 0" @click="submitOrder">
                    {{ submitting ? '提交中...' : '提交订单' }}
                </button>
            </div>
        </div>
    </div>
</template>

<style scoped>
.checkout-page {
    padding: 72px 24px 24px;
    width: 100%;
    box-sizing: border-box;
}

.back-bar {
    display: flex;
    align-items: center;
    gap: 12px;
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

.page-title {
    font-size: 20px;
    font-weight: 700;
    margin: 0;
    color: var(--text-color-primary);
}

.block {
    background: var(--bg-color-secondary);
    border-radius: 12px;
    padding: 16px;
    margin-bottom: 12px;
}

.block-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 12px;
}

.block-title {
    font-size: 16px;
    font-weight: 600;
    margin: 0 0 12px;
    color: var(--text-color-primary);
}

.block-header .block-title {
    margin: 0;
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
    padding: 20px 0;
    font-size: 14px;
}

.empty-address {
    text-align: center;
    padding: 20px 0;
}

.empty-address p {
    color: var(--text-color-tertiary, #999);
    margin: 0 0 12px;
}

.primary-btn {
    background: var(--primary-color);
    color: #fff;
    border: none;
    border-radius: 999px;
    padding: 8px 24px;
    font-size: 14px;
    cursor: pointer;
}

.address-list {
    display: flex;
    flex-direction: column;
    gap: 10px;
}

.address-card {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    padding: 12px;
    border: 2px solid var(--border-color-primary, #eee);
    border-radius: 10px;
    cursor: pointer;
    transition: border-color 0.2s;
}

.address-card.active {
    border-color: var(--primary-color);
}

.address-card input {
    margin-top: 3px;
    accent-color: var(--primary-color);
}

.address-info {
    flex: 1;
}

.address-top {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 4px;
}

.receiver {
    font-weight: 600;
    color: var(--text-color-primary);
}

.phone {
    font-size: 13px;
    color: var(--text-color-secondary);
}

.default-tag {
    font-size: 11px;
    color: var(--primary-color);
    border: 1px solid var(--primary-color);
    border-radius: 4px;
    padding: 0 4px;
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
    background: var(--bg-color-primary, #f5f5f5);
    display: inline-block;
    padding: 2px 6px;
    border-radius: 4px;
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

.remark-input {
    width: 100%;
    border: 1px solid var(--border-color-primary, #eee);
    border-radius: 8px;
    padding: 10px;
    font-size: 14px;
    color: var(--text-color-primary);
    background: var(--bg-color-primary);
    resize: none;
    outline: none;
    box-sizing: border-box;
    font-family: inherit;
}

.remark-input:focus {
    border-color: var(--primary-color);
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

.submit-bar {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    background: var(--bg-color-primary);
    border-top: 1px solid var(--border-color-primary, #eee);
    z-index: 100;
}

.submit-bar-inner {
    max-width: 1200px;
    margin: 0 auto;
    padding: 12px 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    box-sizing: border-box;
}

.submit-left {
    display: flex;
    flex-direction: column;
    gap: 2px;
}

.submit-qty {
    font-size: 12px;
    color: var(--text-color-tertiary, #999);
}

.submit-total {
    font-size: 14px;
    color: var(--text-color-primary);
}

.submit-total em {
    color: var(--primary-color);
    font-size: 20px;
    font-weight: 700;
    font-style: normal;
}

.submit-btn {
    background: var(--primary-color);
    color: #fff;
    border: none;
    border-radius: 999px;
    padding: 12px 36px;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
}

.submit-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

@media (min-width: 961px) {
    .submit-bar {
        left: 228px;
        width: calc(100% - 228px);
    }
}
</style>
