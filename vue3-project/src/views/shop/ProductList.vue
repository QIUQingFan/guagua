<script setup>
import { ref, reactive, onMounted, watch, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useShopStore } from '@/stores/shop.js'
import SvgIcon from '@/components/SvgIcon.vue'

const route = useRoute()
const router = useRouter()
const shopStore = useShopStore()

const defaultCover = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="200" height="200"%3E%3Crect width="200" height="200" fill="%23eee"/%3E%3Ctext x="50%25" y="50%25" font-size="14" fill="%23999" text-anchor="middle" dy=".3em"%3E%E6%9A%82%E6%97%A0%E5%9B%BE%3C/text%3E%3C/svg%3E'

const sortOptions = [
    { value: 'latest', label: '最新' },
    { value: 'sales', label: '销量' },
    { value: 'price_asc', label: '价格↑' },
    { value: 'price_desc', label: '价格↓' }
]

const localKeyword = ref('')
const priceRange = reactive({ min: '', max: '' })

const currentPage = computed(() => shopStore.query.page)
const totalPages = computed(() => shopStore.totalPages)

function syncFromRoute() {
    localKeyword.value = route.query.keyword || ''
    shopStore.resetQuery()
    shopStore.query.keyword = route.query.keyword || ''
    shopStore.query.category_id = route.query.category_id ? Number(route.query.category_id) : null
    shopStore.query.sort = route.query.sort || 'latest'
    shopStore.query.page = route.query.page ? Number(route.query.page) : 1
}

async function loadList() {
    await shopStore.fetchProductList()
}

function applySearch() {
    shopStore.setKeyword(localKeyword.value)
    shopStore.query.page = 1
    syncUrl()
    loadList()
}

function changeCategory(categoryId) {
    shopStore.setCategory(categoryId)
    shopStore.query.page = 1
    syncUrl()
    loadList()
}

function changeSort(sort) {
    shopStore.setSort(sort)
    shopStore.query.page = 1
    syncUrl()
    loadList()
}

function applyPrice() {
    shopStore.query.min_price = priceRange.min !== '' ? Number(priceRange.min) : undefined
    shopStore.query.max_price = priceRange.max !== '' ? Number(priceRange.max) : undefined
    shopStore.query.page = 1
    loadList()
}

function resetFilters() {
    localKeyword.value = ''
    priceRange.min = ''
    priceRange.max = ''
    shopStore.resetQuery()
    syncUrl()
    loadList()
}

function changePage(page) {
    if (page < 1 || page > totalPages.value) return
    shopStore.setPage(page)
    syncUrl()
    loadList()
    window.scrollTo({ top: 0, behavior: 'smooth' })
}

function syncUrl() {
    const q = {}
    if (shopStore.query.keyword) q.keyword = shopStore.query.keyword
    if (shopStore.query.category_id) q.category_id = shopStore.query.category_id
    if (shopStore.query.sort && shopStore.query.sort !== 'latest') q.sort = shopStore.query.sort
    if (shopStore.query.page > 1) q.page = shopStore.query.page
    router.replace({ name: 'shop_list', query: q })
}

function goDetail(item) {
    router.push({ name: 'shop_product_detail', params: { id: item.id } })
}

function handleImgError(e) {
    e.target.src = defaultCover
}

const currentCategoryName = computed(() => {
    if (!shopStore.query.category_id) return '全部商品'
    const c = shopStore.categoryFlat.find(i => i.id === shopStore.query.category_id)
    return c ? c.name : '全部商品'
})

watch(() => route.query, () => {
    syncFromRoute()
    loadList()
}, { deep: true })

onMounted(async () => {
    await shopStore.fetchCategories()
    syncFromRoute()
    loadList()
})
</script>

<template>
    <div class="product-list-page">
        <div class="page-head">
            <h1 class="page-title">{{ currentCategoryName }}</h1>
            <p v-if="shopStore.query.keyword" class="page-sub">
                搜索“{{ shopStore.query.keyword }}” · 共 {{ shopStore.productTotal }} 件
            </p>
            <p v-else class="page-sub">共 {{ shopStore.productTotal }} 件商品</p>
        </div>

        <div class="filter-bar">
            <form class="search-inline" @submit.prevent="applySearch">
                <SvgIcon name="search" width="18" height="18" class="search-icon" />
                <input v-model="localKeyword" type="text" placeholder="搜索商品" class="search-input" />
                <button type="submit" class="icon-btn">搜索</button>
            </form>

            <select
                class="category-select"
                :value="shopStore.query.category_id || ''"
                @change="changeCategory(Number($event.target.value) || null)"
            >
                <option :value="''">全部分类</option>
                <option v-for="c in shopStore.categoryFlat" :key="c.id" :value="c.id">
                    {{ c.name }}
                </option>
            </select>

            <div class="price-filter">
                <input v-model="priceRange.min" type="number" min="0" placeholder="最低价" class="price-input" />
                <span class="price-dash">-</span>
                <input v-model="priceRange.max" type="number" min="0" placeholder="最高价" class="price-input" />
                <button class="icon-btn" @click="applyPrice">确定</button>
            </div>

            <button class="reset-btn" @click="resetFilters">
                <SvgIcon name="clear" width="14" height="14" /> 重置
            </button>
        </div>

        <div class="sort-bar">
            <button
                v-for="s in sortOptions"
                :key="s.value"
                class="sort-btn"
                :class="{ active: shopStore.query.sort === s.value }"
                @click="changeSort(s.value)"
            >{{ s.label }}</button>
        </div>

        <div v-if="shopStore.productLoading" class="state-text">
            <SvgIcon name="loading" width="24" height="24" /> 加载中...
        </div>
        <div v-else-if="shopStore.productList.length === 0" class="state-text empty">
            <p>暂无符合条件的商品</p>
            <button class="icon-btn" @click="resetFilters">清空筛选</button>
        </div>
        <div v-else class="product-grid">
            <div
                v-for="item in shopStore.productList"
                :key="item.id"
                class="product-card"
                @click="goDetail(item)"
            >
                <div class="product-cover">
                    <img :src="item.cover_image || defaultCover" :alt="item.title" @error="handleImgError" />
                    <span v-if="item.stock === 0" class="sold-out">缺货</span>
                </div>
                <div class="product-info">
                    <h3 class="product-title">{{ item.title }}</h3>
                    <p v-if="item.subtitle" class="product-subtitle">{{ item.subtitle }}</p>
                    <div class="product-meta">
                        <span v-if="item.category_name" class="tag">{{ item.category_name }}</span>
                        <span class="product-sales">已售 {{ item.sales }}</span>
                    </div>
                    <div class="product-bottom">
                        <span class="product-price">¥{{ item.price }}</span>
                        <span v-if="item.original_price && Number(item.original_price) > Number(item.price)" class="product-original">¥{{ item.original_price }}</span>
                    </div>
                </div>
            </div>
        </div>

        <div v-if="shopStore.productTotal > 0" class="pagination">
            <button class="page-btn" :disabled="currentPage <= 1" @click="changePage(currentPage - 1)">上一页</button>
            <span class="page-info">{{ currentPage }} / {{ totalPages }}</span>
            <button class="page-btn" :disabled="currentPage >= totalPages" @click="changePage(currentPage + 1)">下一页</button>
        </div>
    </div>
</template>

<style scoped>
.product-list-page {
    padding: 72px 24px 24px;
    width: 100%;
    box-sizing: border-box;
}

.page-head {
    margin-bottom: 16px;
}

.page-title {
    font-size: 24px;
    font-weight: 700;
    margin: 0;
    color: var(--text-color-primary);
}

.page-sub {
    font-size: 13px;
    color: var(--text-color-tertiary, #999);
    margin: 4px 0 0;
}

.filter-bar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 12px;
    padding: 12px;
    background: var(--bg-color-secondary);
    border-radius: 12px;
    margin-bottom: 12px;
}

.search-inline {
    display: flex;
    align-items: center;
    background: var(--bg-color-primary);
    border-radius: 999px;
    padding: 4px 4px 4px 14px;
    flex: 1;
    min-width: 220px;
    border: 1px solid var(--border-color-primary, #eee);
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
    padding: 6px 10px;
    font-size: 14px;
    color: var(--text-color-primary);
    min-width: 0;
}

.category-select {
    padding: 8px 12px;
    border-radius: 8px;
    border: 1px solid var(--border-color-primary, #eee);
    background: var(--bg-color-primary);
    color: var(--text-color-primary);
    font-size: 14px;
    cursor: pointer;
    outline: none;
}

.price-filter {
    display: flex;
    align-items: center;
    gap: 6px;
}

.price-input {
    width: 80px;
    padding: 7px 10px;
    border-radius: 8px;
    border: 1px solid var(--border-color-primary, #eee);
    background: var(--bg-color-primary);
    color: var(--text-color-primary);
    font-size: 13px;
    outline: none;
}

.price-dash {
    color: var(--text-color-tertiary, #999);
}

.icon-btn {
    background: var(--primary-color);
    color: #fff;
    border: none;
    border-radius: 8px;
    padding: 7px 14px;
    font-size: 13px;
    cursor: pointer;
    white-space: nowrap;
}

.icon-btn:hover {
    opacity: 0.9;
}

.reset-btn {
    display: flex;
    align-items: center;
    gap: 4px;
    background: transparent;
    color: var(--text-color-tertiary, #999);
    border: 1px solid var(--border-color-primary, #eee);
    border-radius: 8px;
    padding: 7px 12px;
    font-size: 13px;
    cursor: pointer;
}

.reset-btn:hover {
    color: var(--primary-color);
    border-color: var(--primary-color);
}

.sort-bar {
    display: flex;
    gap: 8px;
    margin-bottom: 16px;
}

.sort-btn {
    background: var(--bg-color-secondary);
    color: var(--text-color-secondary);
    border: none;
    border-radius: 8px;
    padding: 8px 18px;
    font-size: 14px;
    cursor: pointer;
    transition: all 0.2s;
}

.sort-btn:hover {
    background: var(--bg-color-primary);
}

.sort-btn.active {
    background: var(--primary-color);
    color: #fff;
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
    position: relative;
    width: 100%;
    aspect-ratio: 1;
    overflow: hidden;
    background: #f5f5f5;
}

.product-cover img {
    width: 100%;
    height: 100%;
    object-fit: cover;
}

.sold-out {
    position: absolute;
    top: 8px;
    right: 8px;
    background: rgba(0, 0, 0, 0.6);
    color: #fff;
    font-size: 12px;
    padding: 2px 8px;
    border-radius: 4px;
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
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    line-clamp: 2;
    min-height: 40px;
}

.product-subtitle {
    font-size: 12px;
    color: var(--text-color-tertiary, #999);
    margin: 0 0 8px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}

.product-meta {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 8px;
}

.tag {
    font-size: 11px;
    color: var(--primary-color);
    background: rgba(255, 36, 66, 0.08);
    padding: 2px 6px;
    border-radius: 4px;
}

.product-sales {
    font-size: 12px;
    color: var(--text-color-tertiary, #999);
}

.product-bottom {
    display: flex;
    align-items: baseline;
    gap: 8px;
}

.product-price {
    font-size: 18px;
    font-weight: 700;
    color: var(--primary-color);
}

.product-original {
    font-size: 12px;
    color: var(--text-color-tertiary, #999);
    text-decoration: line-through;
}

.state-text {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    color: var(--text-color-tertiary, #999);
    padding: 60px 0;
    font-size: 14px;
}

.state-text.empty p {
    margin: 0;
}

.pagination {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 16px;
    margin-top: 32px;
}

.page-btn {
    background: var(--bg-color-secondary);
    color: var(--text-color-primary);
    border: none;
    border-radius: 8px;
    padding: 8px 20px;
    font-size: 14px;
    cursor: pointer;
}

.page-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
}

.page-btn:not(:disabled):hover {
    background: var(--primary-color);
    color: #fff;
}

.page-info {
    font-size: 14px;
    color: var(--text-color-secondary);
}

@media (max-width: 768px) {
    .filter-bar {
        flex-direction: column;
        align-items: stretch;
    }
    .search-inline,
    .price-filter {
        width: 100%;
    }
    .product-grid {
        grid-template-columns: repeat(2, 1fr);
        gap: 10px;
    }
}
</style>
