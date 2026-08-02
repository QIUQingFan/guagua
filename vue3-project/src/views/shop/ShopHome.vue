<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useShopStore } from '@/stores/shop.js'
import { useCartStore } from '@/stores/cart.js'
import { useUserStore } from '@/stores/user.js'
import SvgIcon from '@/components/SvgIcon.vue'

const router = useRouter()
const shopStore = useShopStore()
const cartStore = useCartStore()
const userStore = useUserStore()

const keyword = ref('')
const activeCategoryId = ref(null)

const defaultCover = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="200" height="200"%3E%3Crect width="200" height="200" fill="%23eee"/%3E%3Ctext x="50%25" y="50%25" font-size="14" fill="%23999" text-anchor="middle" dy=".3em"%3E%E6%9A%82%E6%97%A0%E5%9B%BE%3C/text%3E%3C/svg%3E'

const cartCount = computed(() => cartStore.totalCount)

function handleSearch() {
    router.push({
        name: 'shop_list',
        query: keyword.value.trim() ? { keyword: keyword.value.trim() } : {}
    })
}

function goCategory(categoryId) {
    activeCategoryId.value = categoryId
    router.push({ name: 'shop_list', query: { category_id: categoryId } })
}

function goAllProducts() {
    router.push({ name: 'shop_list' })
}

function goDetail(item) {
    router.push({ name: 'shop_product_detail', params: { id: item.id } })
}

function goCart() {
    router.push({ name: 'shop_cart' })
}

function goOrders() {
    router.push({ name: 'shop_orders' })
}

function handleImgError(e) {
    e.target.src = defaultCover
}

onMounted(async () => {
    await Promise.all([
        shopStore.fetchCategories(),
        shopStore.fetchRecommend({ type: 'hot', limit: 10 })
    ])
    if (userStore.isLoggedIn) {
        cartStore.fetchCart()
    }
})
</script>

<template>
    <div class="shop-home">
        <section class="hero">
            <div class="hero-top">
                <div>
                    <h1 class="hero-title">商城</h1>
                    <p class="hero-subtitle">闲杂好物 · 放心交易</p>
                </div>
                <div class="hero-nav">
                    <button class="nav-link" @click="goOrders">我的订单</button>
                    <button class="nav-link cart-link" @click="goCart">
                        购物车
                        <span v-if="cartCount > 0" class="cart-badge">{{ cartCount }}</span>
                    </button>
                </div>
            </div>
            <form class="search-box" @submit.prevent="handleSearch">
                <SvgIcon name="search" class="search-icon" width="20" height="20" />
                <input
                    v-model="keyword"
                    type="text"
                    placeholder="搜索闲杂好物..."
                    class="search-input"
                />
                <button type="submit" class="search-btn">搜索</button>
            </form>
        </section>

        <section class="section">
            <div class="section-header">
                <h2 class="section-title">商品分类</h2>
                <span class="section-more" @click="goAllProducts">全部商品 ›</span>
            </div>
            <div v-if="shopStore.categoryLoading" class="loading-text">加载分类中...</div>
            <div v-else-if="shopStore.categoryTree.length === 0" class="empty-text">暂无分类</div>
            <div v-else class="category-grid">
                <div
                    v-for="cat in shopStore.categoryTree"
                    :key="cat.id"
                    class="category-card"
                    :class="{ active: activeCategoryId === cat.id }"
                    @click="goCategory(cat.id)"
                >
                    <div class="category-icon">
                        <SvgIcon name="category" width="28" height="28" />
                    </div>
                    <div class="category-name">{{ cat.name }}</div>
                    <div v-if="cat.children && cat.children.length" class="category-sub">
                        {{ cat.children.length }} 个子分类
                    </div>
                </div>
            </div>
        </section>

        <section class="section">
            <div class="section-header">
                <h2 class="section-title">热门推荐</h2>
                <span class="section-more" @click="goAllProducts">查看更多 ›</span>
            </div>
            <div v-if="shopStore.recommendProducts.length === 0" class="empty-text">暂无推荐商品</div>
            <div v-else class="product-grid">
                <div
                    v-for="item in shopStore.recommendProducts"
                    :key="item.id"
                    class="product-card"
                    @click="goDetail(item)"
                >
                    <div class="product-cover">
                        <img :src="item.cover_image || defaultCover" :alt="item.title" @error="handleImgError" />
                    </div>
                    <div class="product-info">
                        <h3 class="product-title">{{ item.title }}</h3>
                        <p v-if="item.subtitle" class="product-subtitle">{{ item.subtitle }}</p>
                        <div class="product-bottom">
                            <span class="product-price">¥{{ item.price }}</span>
                            <span class="product-sales">已售 {{ item.sales }}</span>
                        </div>
                    </div>
                </div>
            </div>
        </section>
    </div>
</template>

<style scoped>
.shop-home {
    padding: 72px 24px 24px;
    width: 100%;
    box-sizing: border-box;
}

.hero {
    background: var(--primary-color);
    border-radius: 16px;
    padding: 40px 24px;
    text-align: center;
    color: var(--text-color-inverse);
    margin-bottom: 24px;
}

.hero-top {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    margin-bottom: 8px;
    text-align: left;
}

.hero-nav {
    display: flex;
    gap: 8px;
    flex-shrink: 0;
}

.nav-link {
    background: rgba(255, 255, 255, 0.18);
    border: none;
    color: #fff;
    border-radius: 999px;
    padding: 6px 14px;
    font-size: 13px;
    cursor: pointer;
    position: relative;
    transition: background 0.2s;
}

.nav-link:hover {
    background: rgba(255, 255, 255, 0.3);
}

.cart-badge {
    position: absolute;
    top: -4px;
    right: -6px;
    min-width: 16px;
    height: 16px;
    line-height: 16px;
    padding: 0 4px;
    background: #fff;
    color: var(--primary-color);
    border-radius: 999px;
    font-size: 11px;
    font-weight: 700;
}

.hero-title {
    font-size: 32px;
    font-weight: 800;
    margin: 0 0 8px;
}

.hero-subtitle {
    font-size: 15px;
    opacity: 0.9;
    margin: 0 0 24px;
}

.search-box {
    display: flex;
    align-items: center;
    background: #fff;
    border-radius: 999px;
    padding: 6px 6px 6px 18px;
    max-width: 560px;
    margin: 0 auto;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);
}

.search-icon {
    color: #999;
    flex-shrink: 0;
}

.search-input {
    flex: 1;
    border: none;
    outline: none;
    background: transparent;
    padding: 8px 12px;
    font-size: 15px;
    color: #333;
    min-width: 0;
}

.search-btn {
    background: var(--primary-color);
    color: #fff;
    border: none;
    border-radius: 999px;
    padding: 8px 24px;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    flex-shrink: 0;
}

.search-btn:hover {
    opacity: 0.9;
}

.section {
    margin-bottom: 32px;
}

.section-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 16px;
}

.section-title {
    font-size: 20px;
    font-weight: 700;
    margin: 0;
    color: var(--text-color-primary);
}

.section-more {
    font-size: 14px;
    color: var(--primary-color);
    cursor: pointer;
}

.section-more:hover {
    opacity: 0.8;
}

.category-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: 12px;
}

.category-card {
    background: var(--bg-color-secondary);
    border: 1px solid var(--border-color-primary, transparent);
    border-radius: 12px;
    padding: 20px 12px;
    text-align: center;
    cursor: pointer;
    transition: all 0.2s;
}

.category-card:hover {
    transform: translateY(-2px);
    border-color: var(--primary-color);
}

.category-card.active {
    border-color: var(--primary-color);
    background: rgba(var(--primary-color-rgb), 0.08);
}

.category-icon {
    color: var(--primary-color);
    margin-bottom: 8px;
}

.category-name {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-color-primary);
}

.category-sub {
    font-size: 12px;
    color: var(--text-color-tertiary);
    margin-top: 4px;
}

.product-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 16px;
}

.product-card {
    background: var(--bg-color-secondary);
    border-radius: 12px;
    overflow: hidden;
    cursor: pointer;
    transition: all 0.2s;
}

.product-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 18px rgba(0, 0, 0, 0.08);
}

.product-cover {
    width: 100%;
    aspect-ratio: 1;
    overflow: hidden;
    background: var(--bg-color-tertiary);
}

.product-cover img {
    width: 100%;
    height: 100%;
    object-fit: cover;
}

.product-info {
    padding: 12px;
}

.product-title {
    font-size: 14px;
    font-weight: 600;
    margin: 0 0 4px;
    color: var(--text-color-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.product-subtitle {
    font-size: 12px;
    color: var(--text-color-tertiary);
    margin: 0 0 8px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.product-bottom {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
}

.product-price {
    font-size: 18px;
    font-weight: 700;
    color: var(--primary-color);
}

.product-sales {
    font-size: 12px;
    color: var(--text-color-tertiary);
}

.loading-text,
.empty-text {
    text-align: center;
    color: var(--text-color-tertiary);
    padding: 32px 0;
    font-size: 14px;
}

@media (max-width: 768px) {
    .hero {
        padding: 28px 16px;
    }
    .hero-title {
        font-size: 24px;
    }
    .product-grid {
        grid-template-columns: repeat(2, 1fr);
        gap: 10px;
    }
    .category-grid {
        grid-template-columns: repeat(3, 1fr);
    }
}
</style>
