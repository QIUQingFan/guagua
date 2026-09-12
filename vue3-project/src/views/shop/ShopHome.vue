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

// 分类卡片图标底色
const tileTints = [
    { bg: 'rgba(220, 18, 87, 0.10)', color: '#dc1257' },
    { bg: 'rgba(59, 130, 246, 0.10)', color: '#3b82f6' },
    { bg: 'rgba(245, 158, 11, 0.14)', color: '#d97706' },
    { bg: 'rgba(16, 185, 129, 0.12)', color: '#059669' },
    { bg: 'rgba(124, 58, 237, 0.10)', color: '#7c3aed' }
]

// 服务保障条
const features = [
    { icon: 'verified', title: '正品保障', sub: '平台严选' },
    { icon: 'tick', title: '快速发货', sub: '卖家直发' },
    { icon: 'clock', title: '售后无忧', sub: '7天可退' },
    { icon: 'chat', title: '在线咨询', sub: '实时沟通' }
]

// 商品进入动画延迟
function cardDelay(i) {
    return { animationDelay: `${Math.min(i * 0.05, 0.6)}s` }
}

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
        <!-- 顶部横幅 -->
        <section class="hero reveal">
            <div class="hero-top">
                <div class="brand">
                    <h1 class="hero-title">闲杂好物<span class="hero-chip">商城</span></h1>
                    <p class="hero-subtitle">淘你所爱 · 放心交易 · 物尽其用</p>
                </div>
                <div class="hero-nav">
                    <button class="nav-link" @click="goOrders">
                        <SvgIcon name="menu" class="nav-icon" width="15" height="15" />
                        我的订单
                    </button>
                    <button class="nav-link cart-link" @click="goCart">
                        <SvgIcon name="shop" class="nav-icon" width="15" height="15" />
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
                    placeholder="搜索手机、书籍、家居好物..."
                    class="search-input"
                />
                <button type="submit" class="search-btn">搜索</button>
            </form>

            <div class="hero-tags">
                <span class="hero-tag">支持自提</span>
                <span class="hero-tag">可小刀</span>
                <span class="hero-tag">同城发货</span>
                <span class="hero-tag">假一赔三</span>
            </div>

            <div class="hero-stamp">放心交易<br />物超所值</div>
        </section>

        <!-- 服务保障 -->
        <section class="feature-strip reveal" :style="{ animationDelay: '0.08s' }">
            <div v-for="f in features" :key="f.title" class="feature-item">
                <SvgIcon :name="f.icon" class="feature-icon" width="22" height="22" />
                <div class="feature-text">
                    <div class="feature-title">{{ f.title }}</div>
                    <div class="feature-sub">{{ f.sub }}</div>
                </div>
            </div>
        </section>

        <!-- 商品分类 -->
        <section class="section reveal" :style="{ animationDelay: '0.12s' }">
            <div class="section-header">
                <h2 class="section-title">商品分类</h2>
                <button class="section-more" @click="goAllProducts">
                    全部商品
                    <SvgIcon name="right" width="13" height="13" />
                </button>
            </div>
            <div v-if="shopStore.categoryLoading" class="loading-text">加载分类中...</div>
            <div v-else-if="shopStore.categoryTree.length === 0" class="empty-text">暂无分类</div>
            <div v-else class="category-grid">
                <div
                    v-for="(cat, i) in shopStore.categoryTree"
                    :key="cat.id"
                    class="category-card"
                    :class="{ active: activeCategoryId === cat.id }"
                    :style="cardDelay(i)"
                    @click="goCategory(cat.id)"
                >
                    <div class="category-icon" :style="{
                        background: tileTints[i % tileTints.length].bg,
                        color: tileTints[i % tileTints.length].color
                    }">
                        <SvgIcon name="category" width="24" height="24" />
                    </div>
                    <div class="category-name">{{ cat.name }}</div>
                    <div v-if="cat.children && cat.children.length" class="category-sub">
                        {{ cat.children.length }} 个子分类
                    </div>
                </div>
            </div>
        </section>

        <!-- 热门推荐 -->
        <section class="section reveal" :style="{ animationDelay: '0.18s' }">
            <div class="section-header">
                <h2 class="section-title">热门推荐</h2>
                <button class="section-more" @click="goAllProducts">
                    查看更多
                    <SvgIcon name="right" width="13" height="13" />
                </button>
            </div>
            <div v-if="shopStore.recommendProducts.length === 0" class="empty-text">暂无推荐商品</div>
            <div v-else class="product-grid">
                <div
                    v-for="(item, i) in shopStore.recommendProducts"
                    :key="item.id"
                    class="product-card reveal"
                    :style="cardDelay(i)"
                    @click="goDetail(item)"
                >
                    <div class="product-cover">
                        <img :src="item.cover_image || defaultCover" :alt="item.title" @error="handleImgError" />
                        <div class="cover-mask">
                            <span class="cover-action">去看看</span>
                        </div>
                    </div>
                    <div class="product-info">
                        <h3 class="product-title">{{ item.title }}</h3>
                        <p v-if="item.subtitle" class="product-subtitle">{{ item.subtitle }}</p>
                        <div class="product-bottom">
                            <span class="product-price">
                                <span class="currency">¥</span>{{ item.price }}
                            </span>
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
    max-width: 1200px;
    margin: 0 auto;
    box-sizing: border-box;
}

/* ============ 进入动画 ============ */
@keyframes fadeUp {
    from { opacity: 0; transform: translateY(14px); }
    to   { opacity: 1; transform: translateY(0); }
}

.reveal {
    opacity: 0;
    animation: fadeUp 0.5s ease forwards;
}

@media (prefers-reduced-motion: reduce) {
    .reveal { animation: none; opacity: 1; }
}

/* ============ 顶部横幅 ============ */
.hero {
    position: relative;
    background: var(--bg-color-primary);
    border: 1px solid var(--border-color-primary);
    border-radius: 20px;
    padding: 32px;
    margin-bottom: 20px;
    box-shadow: var(--shadow-card);
    overflow: hidden;
}

/* 右上角圆点纹理（纯色圆点，非渐变） */
.hero::before {
    content: '';
    position: absolute;
    top: 0;
    right: 0;
    width: 180px;
    height: 180px;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='22' height='22'%3E%3Ccircle cx='2' cy='2' r='1.6' fill='%23dc1257' fill-opacity='0.10'/%3E%3C/svg%3E");
    background-size: 22px 22px;
    pointer-events: none;
}

.hero-top {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    margin-bottom: 24px;
}

.brand {
    position: relative;
    z-index: 1;
}

.hero-title {
    font-size: 30px;
    font-weight: 800;
    letter-spacing: 0.5px;
    margin: 0 0 8px;
    color: var(--text-color-primary);
}

.hero-chip {
    display: inline-block;
    margin-left: 10px;
    padding: 3px 10px;
    font-size: 12px;
    font-weight: 600;
    vertical-align: 4px;
    color: var(--primary-color);
    background: rgba(var(--primary-color-rgb), 0.10);
    border-radius: 999px;
}

.hero-subtitle {
    font-size: 14px;
    color: var(--text-color-tertiary);
    margin: 0;
    letter-spacing: 1px;
}

.hero-nav {
    display: flex;
    gap: 8px;
    flex-shrink: 0;
    position: relative;
    z-index: 1;
}

.nav-link {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background: var(--bg-color-primary);
    border: 1px solid var(--border-color-primary);
    color: var(--text-color-secondary);
    border-radius: 999px;
    padding: 8px 16px;
    font-size: 13px;
    font-weight: 500;
    cursor: pointer;
    position: relative;
    transition: border-color 0.2s, color 0.2s, background 0.2s;
}

.nav-link:hover {
    border-color: rgba(var(--primary-color-rgb), 0.45);
    color: var(--primary-color);
    background: rgba(var(--primary-color-rgb), 0.04);
}

.nav-icon {
    color: currentColor;
}

.cart-badge {
    position: absolute;
    top: -6px;
    right: -6px;
    min-width: 17px;
    height: 17px;
    line-height: 17px;
    padding: 0 5px;
    background: var(--primary-color);
    color: #fff;
    border-radius: 999px;
    font-size: 11px;
    font-weight: 700;
}

/* 搜索框 */
.search-box {
    position: relative;
    z-index: 1;
    display: flex;
    align-items: center;
    background: var(--bg-color-secondary);
    border: 1px solid var(--border-color-primary);
    border-radius: 999px;
    padding: 6px 6px 6px 20px;
    max-width: 620px;
    margin: 0 auto;
    transition: border-color 0.2s, box-shadow 0.2s, background 0.2s;
}

.search-box:focus-within {
    border-color: rgba(var(--primary-color-rgb), 0.5);
    background: var(--bg-color-primary);
    box-shadow: 0 0 0 4px rgba(var(--primary-color-rgb), 0.06);
}

.search-icon {
    color: var(--text-color-quaternary);
    flex-shrink: 0;
}

.search-input {
    flex: 1;
    border: none;
    outline: none;
    background: transparent;
    padding: 9px 14px;
    font-size: 15px;
    color: var(--text-color-primary);
    min-width: 0;
}

.search-input::placeholder {
    color: var(--text-color-quaternary);
}

.search-btn {
    background: var(--primary-color);
    color: #fff;
    border: none;
    border-radius: 999px;
    padding: 9px 26px;
    font-size: 14px;
    font-weight: 600;
    letter-spacing: 1px;
    cursor: pointer;
    flex-shrink: 0;
    transition: background 0.2s, transform 0.15s;
}

.search-btn:hover {
    background: var(--primary-color-dark);
}

.search-btn:active {
    transform: scale(0.96);
}

/* 特性标签 */
.hero-tags {
    position: relative;
    z-index: 1;
    display: flex;
    justify-content: center;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 16px;
}

.hero-tag {
    font-size: 12px;
    color: var(--text-color-tertiary);
    background: var(--bg-color-secondary);
    border: 1px dashed var(--border-color-primary);
    border-radius: 999px;
    padding: 4px 12px;
}

/* 角标印章 */
.hero-stamp {
    position: absolute;
    right: 28px;
    bottom: 20px;
    z-index: 1;
    padding: 8px 10px;
    border: 2px solid rgba(var(--primary-color-rgb), 0.35);
    color: var(--primary-color);
    border-radius: 6px;
    font-size: 11px;
    font-weight: 700;
    line-height: 1.5;
    text-align: center;
    letter-spacing: 1px;
    transform: rotate(-6deg);
    opacity: 0.85;
}

/* ============ 服务保障条 ============ */
.feature-strip {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 12px;
    background: var(--bg-color-primary);
    border: 1px solid var(--border-color-primary);
    border-radius: 16px;
    padding: 18px 8px;
    margin-bottom: 28px;
    box-shadow: var(--shadow-card);
}

.feature-item {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 10px;
    padding: 0 8px;
}

.feature-icon {
    color: var(--primary-color);
    flex-shrink: 0;
}

.feature-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-color-primary);
}

.feature-sub {
    font-size: 11px;
    color: var(--text-color-quaternary);
    margin-top: 2px;
}

/* ============ 区块 ============ */
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
    font-weight: 800;
    letter-spacing: 0.5px;
    margin: 0;
    color: var(--text-color-primary);
    display: flex;
    align-items: center;
    gap: 10px;
}

.section-title::before {
    content: '';
    display: inline-block;
    width: 5px;
    height: 18px;
    background: var(--primary-color);
    border-radius: 3px;
}

.section-more {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 13px;
    font-weight: 500;
    color: var(--text-color-tertiary);
    background: var(--bg-color-primary);
    border: 1px solid var(--border-color-primary);
    border-radius: 999px;
    padding: 6px 14px;
    cursor: pointer;
    transition: color 0.2s, border-color 0.2s, background 0.2s;
}

.section-more:hover {
    color: var(--primary-color);
    border-color: rgba(var(--primary-color-rgb), 0.4);
    background: rgba(var(--primary-color-rgb), 0.04);
}

/* ============ 分类卡片 ============ */
.category-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: 12px;
}

.category-card {
    background: var(--bg-color-primary);
    border: 1px solid var(--border-color-primary);
    border-radius: 16px;
    padding: 22px 12px 18px;
    text-align: center;
    cursor: pointer;
    opacity: 0;
    animation: fadeUp 0.5s ease forwards;
    transition: transform 0.22s, box-shadow 0.22s, border-color 0.22s;
}

.category-card:hover {
    transform: translateY(-4px);
    box-shadow: var(--shadow-elevated);
    border-color: rgba(var(--primary-color-rgb), 0.35);
}

.category-card.active {
    border-color: var(--primary-color);
    box-shadow: 0 0 0 3px rgba(var(--primary-color-rgb), 0.08);
}

.category-icon {
    width: 52px;
    height: 52px;
    margin: 0 auto 12px;
    border-radius: 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: transform 0.22s;
}

.category-card:hover .category-icon {
    transform: scale(1.08) rotate(-4deg);
}

.category-name {
    font-size: 15px;
    font-weight: 600;
    color: var(--text-color-primary);
}

.category-sub {
    font-size: 12px;
    color: var(--text-color-quaternary);
    margin-top: 4px;
}

/* ============ 商品卡片 ============ */
.product-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 16px;
}

.product-card {
    background: var(--bg-color-primary);
    border: 1px solid var(--border-color-primary);
    border-radius: 16px;
    overflow: hidden;
    cursor: pointer;
    opacity: 0;
    animation: fadeUp 0.5s ease forwards;
    transition: transform 0.25s, box-shadow 0.25s, border-color 0.25s;
}

.product-card:hover {
    transform: translateY(-5px);
    box-shadow: var(--shadow-elevated);
    border-color: rgba(var(--primary-color-rgb), 0.35);
}

.product-cover {
    position: relative;
    width: 100%;
    aspect-ratio: 4 / 3;
    overflow: hidden;
    background: var(--bg-color-tertiary);
}

.product-cover img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    transition: transform 0.45s ease;
}

.product-card:hover .product-cover img {
    transform: scale(1.06);
}

.cover-mask {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(15, 23, 42, 0.28);
    opacity: 0;
    transition: opacity 0.25s;
}

.product-card:hover .cover-mask {
    opacity: 1;
}

.cover-action {
    color: #fff;
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 2px;
    background: var(--primary-color);
    padding: 7px 18px;
    border-radius: 999px;
    transform: translateY(6px);
    transition: transform 0.25s;
}

.product-card:hover .cover-action {
    transform: translateY(0);
}

.product-info {
    padding: 14px 14px 16px;
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
    margin: 0 0 10px;
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
    font-size: 20px;
    font-weight: 800;
    color: var(--primary-color);
}

.currency {
    font-size: 13px;
    font-weight: 700;
    margin-right: 1px;
}

.product-sales {
    font-size: 12px;
    color: var(--text-color-quaternary);
}

.loading-text,
.empty-text {
    text-align: center;
    color: var(--text-color-tertiary);
    padding: 32px 0;
    font-size: 14px;
}

/* ============ 响应式 ============ */
@media (max-width: 768px) {
    .shop-home {
        padding: 64px 16px 20px;
    }
    .hero {
        padding: 24px 18px;
        border-radius: 16px;
    }
    .hero-title {
        font-size: 24px;
    }
    .hero-stamp {
        display: none;
    }
    .hero::before {
        width: 120px;
        height: 120px;
    }
    .feature-strip {
        grid-template-columns: repeat(2, 1fr);
        gap: 14px 8px;
        padding: 16px 4px;
    }
    .feature-item {
        justify-content: flex-start;
        padding: 0 12px;
    }
    .product-grid {
        grid-template-columns: repeat(2, 1fr);
        gap: 10px;
    }
    .category-grid {
        grid-template-columns: repeat(3, 1fr);
        gap: 10px;
    }
}
</style>
