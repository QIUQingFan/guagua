<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useShopStore } from '@/stores/shop.js'
import { useCartStore } from '@/stores/cart.js'
import { useUserStore } from '@/stores/user.js'
import { useAuthStore } from '@/stores/auth.js'
import SvgIcon from '@/components/SvgIcon.vue'
import { showShopMessage } from '@/utils/shopMessage.js'
import { reportView, reportCart } from '@/api/behavior.js'

const route = useRoute()
const router = useRouter()
const shopStore = useShopStore()
const cartStore = useCartStore()
const userStore = useUserStore()
const authStore = useAuthStore()

const defaultCover = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="400" height="400"%3E%3Crect width="400" height="400" fill="%23eee"/%3E%3Ctext x="50%25" y="50%25" font-size="16" fill="%23999" text-anchor="middle" dy=".3em"%3E%E6%9A%82%E6%97%A0%E5%9B%BE%3C/text%3E%3C/svg%3E'

const currentImageIndex = ref(0)
const selectedSkuId = ref(null)
const quantity = ref(1)
const favoriting = ref(false)
const addingToCart = ref(false)

const product = computed(() => shopStore.currentProduct)

const imageList = computed(() => {
    if (!product.value) return []
    const imgs = (product.value.images || []).map(i => i.url)
    if (imgs.length === 0 && product.value.cover_image) {
        return [product.value.cover_image]
    }
    return imgs.length ? imgs : [defaultCover]
})

const currentImage = computed(() => imageList.value[currentImageIndex.value] || defaultCover)

const selectedSku = computed(() =>
    (product.value?.skus || []).find(s => s.id === selectedSkuId.value) || null
)

const unitPrice = computed(() => {
    if (selectedSku.value) return Number(selectedSku.value.price)
    return product.value ? Number(product.value.price) : 0
})

const availableStock = computed(() => {
    if (selectedSku.value) return Number(selectedSku.value.stock)
    return product.value ? Number(product.value.stock) : 0
})

const isOnSale = computed(() => product.value?.status === 'on_sale')
const isFavorited = computed(() => Boolean(product.value?.is_favorited))

function selectImage(index) {
    currentImageIndex.value = index
}

function selectSku(sku) {
    selectedSkuId.value = sku.id
    if (quantity.value > Number(sku.stock)) {
        quantity.value = Math.max(Number(sku.stock), 1)
    }
}

function changeQuantity(delta) {
    const next = quantity.value + delta
    if (next < 1) return
    if (next > availableStock.value) return
    quantity.value = next
}

async function handleToggleFavorite() {
    if (!userStore.isLoggedIn) {
        authStore.openLoginModal()
        return
    }
    if (!product.value || favoriting.value) return
    favoriting.value = true
    try {
        await shopStore.toggleFavorite(product.value.id)
    } finally {
        favoriting.value = false
    }
}

async function handleAddToCart() {
    if (!userStore.isLoggedIn) {
        authStore.openLoginModal()
        return
    }
    if (!product.value || addingToCart.value) return
    if (product.value.skus && product.value.skus.length > 0 && !selectedSkuId.value) {
        showShopMessage('请先选择商品规格', 'warning')
        return
    }
    addingToCart.value = true
    try {
        const res = await cartStore.add(product.value.id, selectedSkuId.value, quantity.value)
        if (res.success) {
            showShopMessage('已加入购物车', 'success')
            
            reportCart(product.value.id)
        } else {
            showShopMessage(res.message || '加入购物车失败', 'error')
        }
    } finally {
        addingToCart.value = false
    }
}

function handleBuyNow() {
    if (!userStore.isLoggedIn) {
        authStore.openLoginModal()
        return
    }
    if (!product.value) return
    if (product.value.skus && product.value.skus.length > 0 && !selectedSkuId.value) {
        showShopMessage('请先选择商品规格', 'warning')
        return
    }
    const query = {
        product_id: product.value.id,
        quantity: quantity.value
    }
    if (selectedSkuId.value) query.sku_id = selectedSkuId.value
    router.push({ name: 'shop_checkout', query })
}

function goDetail(item) {
    router.push({ name: 'shop_product_detail', params: { id: item.id } })
}

function goBack() {
    if (window.history.length > 1) {
        router.back()
    } else {
        router.push({ name: 'shop_home' })
    }
}

function handleImgError(e) {
    e.target.src = defaultCover
}

async function loadDetail(id) {
    currentImageIndex.value = 0
    selectedSkuId.value = null
    quantity.value = 1
    await shopStore.fetchProductDetail(id)
    
    if (product.value && product.value.id) {
        reportView(product.value.id)
    }
}

watch(() => route.params.id, (id) => {
    if (id) loadDetail(id)
})

onMounted(() => {
    if (route.params.id) loadDetail(route.params.id)
})
</script>

<template>
    <div class="product-detail-page">
        <div class="back-bar">
            <button class="back-btn" @click="goBack">
                <SvgIcon name="left" width="18" height="18" /> 返回
            </button>
        </div>

        <div v-if="shopStore.detailLoading" class="state-text">加载中...</div>

        <div v-else-if="!product" class="state-text">
            <p>商品不存在或已下架</p>
            <button class="icon-btn" @click="router.push({ name: 'shop_home' })">回首页</button>
        </div>

        <template v-else>
            <div class="detail-main">
                <div class="gallery">
                    <div class="main-image">
                        <img :src="currentImage" :alt="product.title" @error="handleImgError" />
                    </div>
                    <div v-if="imageList.length > 1" class="thumbnails">
                        <div
                            v-for="(img, idx) in imageList"
                            :key="idx"
                            class="thumb"
                            :class="{ active: currentImageIndex === idx }"
                            @click="selectImage(idx)"
                        >
                            <img :src="img" :alt="`图片${idx + 1}`" @error="handleImgError" />
                        </div>
                    </div>
                </div>

                <div class="info-panel">
                    <h1 class="title">{{ product.title }}</h1>
                    <p v-if="product.subtitle" class="subtitle">{{ product.subtitle }}</p>

                    <div class="price-box">
                        <span class="price">¥{{ unitPrice.toFixed(2) }}</span>
                        <span
                            v-if="product.original_price && Number(product.original_price) > unitPrice"
                            class="original-price"
                        >¥{{ product.original_price }}</span>
                    </div>

                    <div class="meta-row">
                        <span class="meta-item">销量 {{ product.sales }}</span>
                        <span class="meta-item">库存 {{ availableStock }}</span>
                        <span v-if="product.category_name" class="meta-item">{{ product.category_name }}</span>
                    </div>

                    <div v-if="product.skus && product.skus.length" class="sku-section">
                        <div class="section-label">选择规格</div>
                        <div class="sku-list">
                            <button
                                v-for="sku in product.skus"
                                :key="sku.id"
                                class="sku-btn"
                                :class="{
                                    active: selectedSkuId === sku.id,
                                    disabled: Number(sku.stock) === 0
                                }"
                                :disabled="Number(sku.stock) === 0"
                                @click="selectSku(sku)"
                            >
                                <span class="sku-spec">{{ sku.spec }}</span>
                                <span class="sku-price">¥{{ sku.price }}</span>
                            </button>
                        </div>
                    </div>

                    <div class="quantity-section">
                        <div class="section-label">数量</div>
                        <div class="quantity-control">
                            <button class="qty-btn" :disabled="quantity <= 1" @click="changeQuantity(-1)">-</button>
                            <span class="qty-value">{{ quantity }}</span>
                            <button class="qty-btn" :disabled="quantity >= availableStock" @click="changeQuantity(1)">+</button>
                        </div>
                    </div>

                    <div class="action-bar">
                        <button
                            class="action-btn fav-btn"
                            :class="{ active: isFavorited }"
                            :disabled="favoriting"
                            @click="handleToggleFavorite"
                        >
                            <SvgIcon :name="isFavorited ? 'collected' : 'collect'" width="20" height="20" />
                            {{ isFavorited ? '已收藏' : '收藏' }}
                        </button>
                        <button class="action-btn cart-btn" :disabled="!isOnSale || addingToCart" @click="handleAddToCart">
                            {{ addingToCart ? '加入中...' : '加入购物车' }}
                        </button>
                        <button class="action-btn buy-btn" :disabled="!isOnSale" @click="handleBuyNow">
                            立即购买
                        </button>
                    </div>
                    <p v-if="!isOnSale" class="off-shelf-tip">该商品已下架，暂时无法购买</p>
                </div>
            </div>

            <section v-if="product.description" class="desc-section">
                <h2 class="block-title">商品详情</h2>
                <div class="desc-content">{{ product.description }}</div>
            </section>

            <section v-if="product.related && product.related.length" class="related-section">
                <h2 class="block-title">相关推荐</h2>
                <div class="related-grid">
                    <div
                        v-for="item in product.related"
                        :key="item.id"
                        class="related-card"
                        @click="goDetail(item)"
                    >
                        <div class="related-cover">
                            <img :src="item.cover_image || defaultCover" :alt="item.title" @error="handleImgError" />
                        </div>
                        <div class="related-info">
                            <div class="related-title">{{ item.title }}</div>
                            <div class="related-price">¥{{ item.price }}</div>
                        </div>
                    </div>
                </div>
            </section>
        </template>
    </div>
</template>

<style scoped>
.product-detail-page {
    padding: 72px 24px 24px;
    width: 100%;
    box-sizing: border-box;
}

.back-bar {
    margin-bottom: 12px;
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

.back-btn:hover {
    color: var(--primary-color);
}

.detail-main {
    display: grid;
    grid-template-columns: 420px 1fr;
    gap: 32px;
    margin-bottom: 32px;
}

.gallery {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.main-image {
    width: 100%;
    aspect-ratio: 1;
    border-radius: 12px;
    overflow: hidden;
    background: #f5f5f5;
}

.main-image img {
    width: 100%;
    height: 100%;
    object-fit: cover;
}

.thumbnails {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
}

.thumb {
    width: 64px;
    height: 64px;
    border-radius: 8px;
    overflow: hidden;
    cursor: pointer;
    border: 2px solid transparent;
    background: #f5f5f5;
}

.thumb.active {
    border-color: var(--primary-color);
}

.thumb img {
    width: 100%;
    height: 100%;
    object-fit: cover;
}

.info-panel {
    display: flex;
    flex-direction: column;
}

.title {
    font-size: 22px;
    font-weight: 700;
    margin: 0 0 8px;
    color: var(--text-color-primary);
    line-height: 1.4;
}

.subtitle {
    font-size: 14px;
    color: var(--text-color-tertiary, #999);
    margin: 0 0 16px;
}

.price-box {
    background: var(--bg-color-secondary);
    border-radius: 12px;
    padding: 16px;
    margin-bottom: 16px;
    display: flex;
    align-items: baseline;
    gap: 12px;
}

.price {
    font-size: 30px;
    font-weight: 800;
    color: var(--primary-color);
}

.original-price {
    font-size: 16px;
    color: var(--text-color-tertiary, #999);
    text-decoration: line-through;
}

.meta-row {
    display: flex;
    gap: 20px;
    margin-bottom: 20px;
    padding-bottom: 16px;
    border-bottom: 1px solid var(--border-color-primary, #eee);
}

.meta-item {
    font-size: 13px;
    color: var(--text-color-tertiary, #999);
}

.sku-section,
.quantity-section {
    margin-bottom: 20px;
}

.section-label {
    font-size: 14px;
    font-weight: 600;
    color: var(--text-color-secondary);
    margin-bottom: 10px;
}

.sku-list {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
}

.sku-btn {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    background: var(--bg-color-secondary);
    border: 2px solid transparent;
    border-radius: 8px;
    padding: 8px 16px;
    cursor: pointer;
    transition: all 0.2s;
    min-width: 90px;
}

.sku-btn:not(.disabled):hover {
    border-color: var(--primary-color);
}

.sku-btn.active {
    border-color: var(--primary-color);
    background: rgba(255, 36, 66, 0.06);
}

.sku-btn.disabled {
    opacity: 0.4;
    cursor: not-allowed;
}

.sku-spec {
    font-size: 13px;
    color: var(--text-color-primary);
}

.sku-price {
    font-size: 13px;
    font-weight: 600;
    color: var(--primary-color);
}

.quantity-control {
    display: flex;
    align-items: center;
    gap: 0;
    border: 1px solid var(--border-color-primary, #eee);
    border-radius: 8px;
    width: fit-content;
    overflow: hidden;
}

.qty-btn {
    width: 36px;
    height: 36px;
    border: none;
    background: var(--bg-color-secondary);
    color: var(--text-color-primary);
    font-size: 18px;
    cursor: pointer;
}

.qty-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
}

.qty-btn:not(:disabled):hover {
    background: var(--primary-color);
    color: #fff;
}

.qty-value {
    width: 48px;
    text-align: center;
    font-size: 15px;
    color: var(--text-color-primary);
}

.action-bar {
    display: flex;
    gap: 12px;
    margin-top: 24px;
}

.action-btn {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    border: none;
    border-radius: 999px;
    padding: 12px 0;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
}

.fav-btn {
    background: var(--bg-color-secondary);
    color: var(--text-color-secondary);
    flex: 0 0 120px;
}

.fav-btn.active {
    color: var(--primary-color);
}

.cart-btn {
    background: rgba(245, 158, 11, 0.12);
    color: var(--series-warning);
}

.buy-btn {
    background: var(--primary-color);
    color: #fff;
}

.action-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

.action-btn:not(:disabled):hover {
    opacity: 0.9;
}

.off-shelf-tip {
    color: var(--text-color-tertiary, #999);
    font-size: 13px;
    margin-top: 10px;
}

.desc-section,
.related-section {
    margin-bottom: 32px;
}

.block-title {
    font-size: 18px;
    font-weight: 700;
    margin: 0 0 16px;
    color: var(--text-color-primary);
    padding-left: 12px;
    border-left: 4px solid var(--primary-color);
}

.desc-content {
    background: var(--bg-color-secondary);
    border-radius: 12px;
    padding: 20px;
    font-size: 14px;
    line-height: 1.8;
    color: var(--text-color-secondary);
    white-space: pre-wrap;
}

.related-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: 12px;
}

.related-card {
    background: var(--bg-color-secondary);
    border-radius: 10px;
    overflow: hidden;
    cursor: pointer;
    transition: all 0.2s;
}

.related-card:hover {
    transform: translateY(-2px);
}

.related-cover {
    width: 100%;
    aspect-ratio: 1;
    background: #f5f5f5;
}

.related-cover img {
    width: 100%;
    height: 100%;
    object-fit: cover;
}

.related-info {
    padding: 8px 10px;
}

.related-title {
    font-size: 13px;
    color: var(--text-color-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.related-price {
    font-size: 15px;
    font-weight: 700;
    color: var(--primary-color);
    margin-top: 4px;
}

.state-text {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    color: var(--text-color-tertiary, #999);
    padding: 80px 0;
    font-size: 14px;
}

.icon-btn {
    background: var(--primary-color);
    color: #fff;
    border: none;
    border-radius: 8px;
    padding: 8px 18px;
    font-size: 14px;
    cursor: pointer;
}

@media (max-width: 768px) {
    .detail-main {
        grid-template-columns: 1fr;
        gap: 16px;
    }
    .main-image {
        max-width: 100%;
    }
    .action-bar {
        flex-wrap: wrap;
    }
    .fav-btn {
        flex: 1 1 100%;
    }
    .related-grid {
        grid-template-columns: repeat(3, 1fr);
    }
}
</style>
