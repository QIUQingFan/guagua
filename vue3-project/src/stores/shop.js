import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import {
    getShopCategories,
    getProductList,
    getProductDetail,
    getRecommendProducts,
    getMyFavorites,
    favoriteProduct,
    unfavoriteProduct
} from '@/api/shop.js'

/**
 * 商城 Store（M2：商品/分类/搜索/收藏）
 * 购物车、订单状态将在 M3 由独立 store 提供
 */
export const useShopStore = defineStore('shop', () => {
    const categoryTree = ref([])        
    const categoryFlat = ref([])        
    const categoryLoading = ref(false)

    const productList = ref([])
    const productTotal = ref(0)
    const productLoading = ref(false)
    const query = ref({
        page: 1,
        limit: 20,
        keyword: '',
        category_id: null,
        min_price: undefined,
        max_price: undefined,
        sort: 'latest'
    })

    const currentProduct = ref(null)
    const detailLoading = ref(false)

    const recommendProducts = ref([])

    const favoriteList = ref([])
    const favoriteTotal = ref(0)
    const favoriteLoading = ref(false)
    const favoriteIdSet = ref(new Set())

    const totalPages = computed(() =>
        query.value.limit > 0 ? Math.ceil(productTotal.value / query.value.limit) : 0
    )

    const isFavorited = computed(() => (productId) =>
        favoriteIdSet.value.has(Number(productId))
    )

    async function fetchCategories() {
        categoryLoading.value = true
        try {
            const [treeRes, flatRes] = await Promise.all([
                getShopCategories(),
                getShopCategories({ flat: 1 })
            ])
            if (treeRes.success) categoryTree.value = treeRes.data || []
            if (flatRes.success) categoryFlat.value = flatRes.data || []
            return treeRes
        } finally {
            categoryLoading.value = false
        }
    }

    async function fetchProductList(payload = {}) {
        Object.assign(query.value, payload)
        productLoading.value = true
        try {
            const res = await getProductList(query.value)
            if (res.success) {
                productList.value = res.data?.data || []
                productTotal.value = res.data?.total || 0
            }
            return res
        } finally {
            productLoading.value = false
        }
    }

    function resetQuery() {
        query.value = {
            page: 1,
            limit: 20,
            keyword: '',
            category_id: null,
            min_price: undefined,
            max_price: undefined,
            sort: 'latest'
        }
    }

    function setKeyword(keyword) {
        query.value.keyword = keyword || ''
        query.value.page = 1
    }

    function setCategory(categoryId) {
        query.value.category_id = categoryId || null
        query.value.page = 1
    }

    function setSort(sort) {
        query.value.sort = sort
        query.value.page = 1
    }

    function setPage(page) {
        query.value.page = Math.max(parseInt(page) || 1, 1)
    }

    async function fetchProductDetail(id) {
        detailLoading.value = true
        try {
            const res = await getProductDetail(id)
            if (res.success) {
                currentProduct.value = res.data
                if (res.data?.is_favorited) {
                    favoriteIdSet.value.add(Number(id))
                }
            }
            return res
        } finally {
            detailLoading.value = false
        }
    }

    async function fetchRecommend(params = {}) {
        try {
            const res = await getRecommendProducts(params)
            if (res.success) recommendProducts.value = res.data || []
            return res
        } catch (e) {
            return { success: false, message: e.message }
        }
    }

    async function fetchFavorites(params = {}) {
        favoriteLoading.value = true
        try {
            const res = await getMyFavorites(params)
            if (res.success) {
                favoriteList.value = res.data?.data || []
                favoriteTotal.value = res.data?.total || 0
                favoriteIdSet.value = new Set(favoriteList.value.map(i => Number(i.id)))
            }
            return res
        } finally {
            favoriteLoading.value = false
        }
    }

    async function toggleFavorite(productId) {
        const id = Number(productId)
        const favorited = favoriteIdSet.value.has(id)
        try {
            const res = favorited
                ? await unfavoriteProduct(id)
                : await favoriteProduct(id)
            if (res.success) {
                if (favorited) {
                    favoriteIdSet.value.delete(id)
                    favoriteList.value = favoriteList.value.filter(i => Number(i.id) !== id)
                    favoriteTotal.value = Math.max(0, favoriteTotal.value - 1)
                } else {
                    favoriteIdSet.value.add(id)
                }
                if (currentProduct.value && Number(currentProduct.value.id) === id) {
                    currentProduct.value.is_favorited = !favorited
                }
            }
            return { ...res, is_favorited: !favorited }
        } catch (e) {
            return { success: false, message: e.message }
        }
    }

    function reset() {
        categoryTree.value = []
        categoryFlat.value = []
        productList.value = []
        productTotal.value = 0
        currentProduct.value = null
        recommendProducts.value = []
        favoriteList.value = []
        favoriteTotal.value = 0
        favoriteIdSet.value = new Set()
        resetQuery()
    }

    return {
        categoryTree, categoryFlat, categoryLoading,
        productList, productTotal, productLoading, query,
        currentProduct, detailLoading,
        recommendProducts,
        favoriteList, favoriteTotal, favoriteLoading, favoriteIdSet,
        totalPages, isFavorited,
        fetchCategories,
        fetchProductList, resetQuery, setKeyword, setCategory, setSort, setPage,
        fetchProductDetail,
        fetchRecommend,
        fetchFavorites, toggleFavorite,
        reset
    }
})
