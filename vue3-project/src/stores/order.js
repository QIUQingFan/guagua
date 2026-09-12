import { defineStore } from 'pinia'
import { ref } from 'vue'
import {
    createOrder,
    getOrderList,
    getOrderDetail,
    cancelOrder,
    confirmOrder,
    getOrderLogs,
    payOrder,
    getPayStatus,
    refundOrder
} from '@/api/shop.js'

/**
 * 订单 Store
 * 对应后端 /api/orders 系列接口
 */
export const useOrderStore = defineStore('order', () => {
    const list = ref([])
    const total = ref(0)
    const current = ref(null)
    const logs = ref([])
    const isLoading = ref(false)
    const submitting = ref(false)

    /**
     * 下单（不缓存结果，返回给调用方处理跳转）
     * @param {Object} payload { items, address_id, remark, from_cart }
     */
    async function placeOrder(payload) {
        submitting.value = true
        try {
            return await createOrder(payload)
        } finally {
            submitting.value = false
        }
    }

    /**
     * 获取订单列表
     * @param {Object} params { page, limit, status }
     */
    async function fetchList(params) {
        isLoading.value = true
        try {
            const res = await getOrderList(params)
            if (res.success) {
                list.value = res.data?.data || []
                total.value = res.data?.total || 0
            }
            return res
        } finally {
            isLoading.value = false
        }
    }

    /**
     * 获取订单详情
     * @param {string|number} idOrNo 订单ID或订单号
     */
    async function fetchDetail(idOrNo) {
        isLoading.value = true
        try {
            const res = await getOrderDetail(idOrNo)
            if (res.success) current.value = res.data
            return res
        } finally {
            isLoading.value = false
        }
    }

    /**
     * 获取订单状态流转日志
     */
    async function fetchLogs(idOrNo) {
        const res = await getOrderLogs(idOrNo)
        if (res.success) logs.value = res.data || []
        return res
    }

    /**
     * 取消订单
     */
    async function cancel(idOrNo) {
        const res = await cancelOrder(idOrNo)
        if (res.success && current.value?.id) {
            await fetchDetail(getOrderKey(current.value))
        }
        return res
    }

    /**
     * 确认收货
     */
    async function confirm(idOrNo) {
        const res = await confirmOrder(idOrNo)
        if (res.success && current.value?.id) {
            await fetchDetail(getOrderKey(current.value))
        }
        return res
    }

    /**
     * 发起支付，返回支付跳转链接
     */
    async function pay(idOrNo) {
        submitting.value = true
        try {
            return await payOrder(idOrNo)
        } finally {
            submitting.value = false
        }
    }

    /**
     * 查询支付结果
     */
    async function queryPayStatus(idOrNo) {
        const res = await getPayStatus(idOrNo)
        if (res.success && res.data?.paid && current.value?.id) {
            await fetchDetail(getOrderKey(current.value))
        }
        return res
    }

    /**
     * 申请退款
     */
    async function refund(idOrNo, data) {
        submitting.value = true
        try {
            const res = await refundOrder(idOrNo, data)
            if (res.success && current.value?.id) {
                await fetchDetail(getOrderKey(current.value))
            }
            return res
        } finally {
            submitting.value = false
        }
    }

    function getOrderKey(order) {
        return order.order_no || order.id
    }

    function reset() {
        list.value = []
        total.value = 0
        current.value = null
        logs.value = []
    }

    return {
        list, total, current, logs, isLoading, submitting,
        placeOrder, fetchList, fetchDetail, fetchLogs,
        cancel, confirm, pay, queryPayStatus, refund,
        getOrderKey, reset
    }
})
