import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import {
    getCart,
    addToCart,
    updateCartItem,
    deleteCartItem,
    clearCart,
    selectAllCart
} from '@/api/shop.js'

/**
 * 购物车 Store
 * 对应后端 GET /api/cart 返回 { items, summary, invalid_items }
 */
export const useCartStore = defineStore('cart', () => {
    const items = ref([])
    const summary = ref({
        selected_count: 0,
        selected_quantity: 0,
        selected_amount: '0.00',
        total_quantity: 0
    })
    const invalidItems = ref([])
    const isLoading = ref(false)
    const isInitialized = ref(false)

    const totalCount = computed(() =>
        items.value.reduce((sum, i) => sum + Number(i.quantity), 0)
    )

    const selectedItems = computed(() =>
        items.value.filter(i => Number(i.is_selected) === 1)
    )

    const selectedQuantity = computed(() =>
        selectedItems.value.reduce((sum, i) => sum + Number(i.quantity), 0)
    )

    const selectedAmount = computed(() =>
        selectedItems.value
            .reduce((sum, i) => sum + Number(i.product?.price || 0) * Number(i.quantity), 0)
            .toFixed(2)
    )

    const allSelected = computed(
        () => items.value.length > 0 && items.value.every(i => Number(i.is_selected) === 1)
    )

    const hasInvalid = computed(() => invalidItems.value.length > 0)

    async function fetchCart() {
        isLoading.value = true
        try {
            const res = await getCart()
            if (res.success) {
                items.value = res.data?.items || []
                summary.value = res.data?.summary || summary.value
                invalidItems.value = res.data?.invalid_items || []
            }
            isInitialized.value = true
            return res
        } finally {
            isLoading.value = false
        }
    }

    async function add(productId, skuId = null, quantity = 1) {
        const res = await addToCart({ product_id: productId, sku_id: skuId, quantity })
        if (res.success) await fetchCart()
        return res
    }

    async function updateItem(id, data) {
        const res = await updateCartItem(id, data)
        if (res.success) {
            const item = items.value.find(i => i.id === id)
            if (item) Object.assign(item, data)
            await fetchCart()
        }
        return res
    }

    async function updateQuantity(id, quantity) {
        return updateItem(id, { quantity })
    }

    async function toggleSelect(id, isSelected) {
        const res = await updateCartItem(id, { is_selected: isSelected ? 1 : 0 })
        if (res.success) {
            const item = items.value.find(i => i.id === id)
            if (item) item.is_selected = isSelected ? 1 : 0
            await fetchCart()
        }
        return res
    }

    async function removeItem(id) {
        const res = await deleteCartItem(id)
        if (res.success) {
            items.value = items.value.filter(i => i.id !== id)
            await fetchCart()
        }
        return res
    }

    async function removeItems(ids) {
        const res = await clearCart(ids)
        if (res.success) await fetchCart()
        return res
    }

    async function clear() {
        const res = await clearCart()
        if (res.success) await fetchCart()
        return res
    }

    async function toggleSelectAll(value) {
        const res = await selectAllCart(value ? 1 : 0)
        if (res.success) {
            items.value.forEach(i => { i.is_selected = value ? 1 : 0 })
            await fetchCart()
        }
        return res
    }

    function reset() {
        items.value = []
        invalidItems.value = []
        summary.value = {
            selected_count: 0,
            selected_quantity: 0,
            selected_amount: '0.00',
            total_quantity: 0
        }
        isInitialized.value = false
    }

    return {
        items, summary, invalidItems, isLoading, isInitialized,
        totalCount, selectedItems, selectedQuantity, selectedAmount,
        allSelected, hasInvalid,
        fetchCart, add, updateItem, updateQuantity, toggleSelect,
        removeItem, removeItems, clear, toggleSelectAll, reset
    }
})
