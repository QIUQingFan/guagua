<template>
  <div class="order-management">
    <div class="table-header">
      <div class="header-left">
        <div class="search-bar">
          <div class="search-field">
            <input v-model="searchParams.order_no" type="text" placeholder="订单号" @keyup.enter="handleSearch" />
          </div>
          <div class="search-field">
            <input v-model="searchParams.user_id" type="text" placeholder="买家ID/瓜呱号" @keyup.enter="handleSearch" />
          </div>
          <div class="search-field">
            <div class="custom-select" @click="toggleStatusDropdown">
              <span class="select-value">{{ statusLabel }}</span>
              <SvgIcon name="down" class="select-arrow" :class="{ rotated: statusDropdownOpen }" />
              <div v-if="statusDropdownOpen" class="select-options">
                <div v-for="opt in STATUS_OPTIONS" :key="opt.value" class="select-option"
                  :class="{ selected: searchParams.status === opt.value }"
                  @click.stop="selectStatus(opt.value)">{{ opt.label }}</div>
              </div>
            </div>
          </div>
          <button class="btn btn-outline btn-sm" @click="handleSearch">筛选</button>
          <button class="btn btn-outline btn-sm" @click="clearSearch">清空</button>
        </div>
      </div>
      <div class="table-actions">
        <button class="btn btn-secondary" @click="fetchList">
          <SvgIcon name="reload" />
          刷新
        </button>
      </div>
    </div>

    <div class="table-container">
      <table class="data-table">
        <thead>
          <tr>
            <th>订单号</th>
            <th>买家</th>
            <th>商品</th>
            <th>应付金额</th>
            <th>状态</th>
            <th>物流</th>
            <th>下单时间</th>
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="item in list" :key="item.id">
            <td>
              <div class="order-no">{{ item.order_no }}</div>
              <div class="order-id muted">ID: {{ item.id }}</div>
            </td>
            <td>
              <div class="buyer">
                <img v-if="item.user_avatar" :src="item.user_avatar" alt="" class="buyer-avatar" v-img-fallback="'avatar'" />
                <div class="buyer-info">
                  <div class="buyer-name">{{ item.user_nickname || '-' }}</div>
                  <div class="buyer-account muted">{{ item.user_account || item.user_id }}</div>
                </div>
              </div>
            </td>
            <td>
              <div class="goods-cell">
                <div class="goods-summary">
                  <img v-if="firstImage(item)" :src="firstImage(item)" alt="" class="goods-thumb" v-img-fallback />
                  <div class="goods-text">
                    <div class="goods-title">{{ firstTitle(item) }}</div>
                    <div class="goods-count muted">共 {{ item.total_quantity }} 件</div>
                  </div>
                </div>
              </div>
            </td>
            <td>
              <div class="pay-amount">¥{{ item.pay_amount }}</div>
              <div class="muted small">含运费 ¥{{ item.shipping_fee }}</div>
            </td>
            <td>
              <span class="status-tag" :class="statusClass(item.status)">{{ item.status_text }}</span>
            </td>
            <td>
              <div v-if="item.tracking_no" class="muted small">
                {{ item.tracking_company }}<br />{{ item.tracking_no }}
              </div>
              <span v-else class="muted">-</span>
            </td>
            <td>{{ formatDate(item.created_at) }}</td>
            <td class="action-cell">
              <button class="btn btn-sm btn-outline" @click="openDetail(item)">详情</button>
              <button v-if="canShip(item.status)" class="btn btn-sm btn-primary" @click="openShipModal(item)">发货</button>
              <button v-if="canRefund(item)" class="btn btn-sm btn-danger" @click="confirmRefund(item)">退款</button>
              <button v-if="canClose(item.status)" class="btn btn-sm btn-danger" @click="confirmClose(item)">关闭</button>
            </td>
          </tr>
          <tr v-if="!loading && list.length === 0">
            <td colspan="8" class="empty-row">暂无订单数据</td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="pagination" v-if="total > 0">
      <div class="pagination-info">共 {{ total }} 条记录，第 {{ page }} / {{ totalPages }} 页</div>
      <div class="pagination-controls">
        <button class="btn btn-sm btn-outline" :disabled="page <= 1" @click="changePage(page - 1)">上一页</button>
        <span class="page-numbers">
          <button v-for="p in pageNumbers" :key="p" class="btn btn-sm"
            :class="p === page ? 'btn-primary' : 'btn-outline'" @click="changePage(p)">{{ p }}</button>
        </span>
        <button class="btn btn-sm btn-outline" :disabled="page >= totalPages" @click="changePage(page + 1)">下一页</button>
      </div>
    </div>

    <div v-if="showShipModal" class="modal-overlay" @click.self="closeShipModal">
      <div class="modal-dialog">
        <div class="modal-header">
          <h3 class="modal-title">订单发货</h3>
          <button class="close-btn" @click="closeShipModal">
            <SvgIcon name="close" width="20" height="20" />
          </button>
        </div>
        <div class="modal-body">
          <div class="form-row">
            <label class="form-label">订单号</label>
            <div class="static-value">{{ shipTarget.order_no }}</div>
          </div>
          <div class="form-row">
            <label class="form-label">物流公司 <span class="required">*</span></label>
            <input v-model="shipForm.tracking_company" type="text" class="form-input" placeholder="如 顺丰/中通/圆通" />
          </div>
          <div class="form-row">
            <label class="form-label">物流单号 <span class="required">*</span></label>
            <input v-model="shipForm.tracking_no" type="text" class="form-input" placeholder="请输入物流单号" />
          </div>
        </div>
        <div class="modal-footer">
          <button class="btn btn-outline" @click="closeShipModal">取消</button>
          <button class="btn btn-primary" :disabled="submitting" @click="submitShip">
            {{ submitting ? '发货中...' : '确认发货' }}
          </button>
        </div>
      </div>
    </div>

    <div v-if="showDetailModal" class="modal-overlay detail-overlay" @click.self="closeDetail">
      <div class="modal-dialog detail-dialog">
        <div class="modal-header">
          <h3 class="modal-title">订单详情</h3>
          <button class="close-btn" @click="closeDetail">
            <SvgIcon name="close" width="20" height="20" />
          </button>
        </div>
        <div class="modal-body detail-body">
          <div v-if="detailLoading" class="detail-loading">加载中...</div>
          <template v-else-if="detail">
            <div class="detail-section">
              <div class="detail-status-row">
                <span class="status-tag" :class="statusClass(detail.status)">{{ detail.status_text }}</span>
                <span class="order-no-text">{{ detail.order_no }}</span>
              </div>
              <div class="detail-grid">
                <div class="detail-item"><span class="dim">下单时间</span>{{ formatDate(detail.created_at) }}</div>
                <div class="detail-item"><span class="dim">付款时间</span>{{ formatDate(detail.paid_at) }}</div>
                <div class="detail-item"><span class="dim">发货时间</span>{{ formatDate(detail.shipped_at) }}</div>
                <div class="detail-item"><span class="dim">完成时间</span>{{ formatDate(detail.completed_at) }}</div>
                <div class="detail-item"><span class="dim">买家备注</span>{{ detail.remark || '-' }}</div>
                <div v-if="detail.trade_no" class="detail-item"><span class="dim">支付宝交易号</span>{{ detail.trade_no }}</div>
                <div v-if="detail.refund_at" class="detail-item"><span class="dim">退款时间</span>{{ formatDate(detail.refund_at) }}</div>
                <div v-if="detail.refund_reason" class="detail-item full"><span class="dim">退款原因</span>{{ detail.refund_reason }}</div>
              </div>
            </div>

            <div class="detail-section">
              <h4 class="detail-subtitle">收货信息</h4>
              <div class="detail-grid">
                <div class="detail-item"><span class="dim">收货人</span>{{ detail.receiver }}</div>
                <div class="detail-item"><span class="dim">联系电话</span>{{ detail.phone }}</div>
                <div class="detail-item full"><span class="dim">收货地址</span>{{ detail.address }}</div>
                <div v-if="detail.tracking_no" class="detail-item full">
                  <span class="dim">物流信息</span>{{ detail.tracking_company }} {{ detail.tracking_no }}
                </div>
              </div>
            </div>

            <div class="detail-section">
              <h4 class="detail-subtitle">商品明细（共 {{ detail.total_quantity }} 件）</h4>
              <div class="detail-goods">
                <div v-for="g in detail.items" :key="g.id" class="goods-line">
                  <img v-if="g.product_image" :src="g.product_image" alt="" class="goods-thumb" v-img-fallback />
                  <div v-else class="goods-thumb placeholder-thumb"></div>
                  <div class="goods-line-info">
                    <div class="goods-line-title">{{ g.product_title }}</div>
                    <div class="muted small">{{ g.spec || '默认规格' }}</div>
                  </div>
                  <div class="goods-line-price">¥{{ g.unit_price }}</div>
                  <div class="goods-line-qty">×{{ g.quantity }}</div>
                  <div class="goods-line-sub">¥{{ g.subtotal }}</div>
                </div>
              </div>
              <div class="detail-amount">
                <div class="amount-row"><span>商品总额</span><span>¥{{ detail.total_amount }}</span></div>
                <div class="amount-row"><span>运费</span><span>¥{{ detail.shipping_fee }}</span></div>
                <div class="amount-row amount-total"><span>应付金额</span><span>¥{{ detail.pay_amount }}</span></div>
                <div v-if="detail.refund_status === 'refunded'" class="amount-row amount-refund">
                  <span>已退款</span><span>¥{{ detail.refund_amount }}</span>
                </div>
              </div>
            </div>

            <div class="detail-section">
              <h4 class="detail-subtitle">状态流转</h4>
              <div class="timeline">
                <div v-for="(log, idx) in detail.logs" :key="log.id" class="timeline-item">
                  <div class="timeline-dot" :class="{ 'dot-active': idx === detail.logs.length - 1 }"></div>
                  <div class="timeline-content">
                    <div class="timeline-title">
                      {{ log.to_status_text }}
                      <span v-if="log.from_status_text" class="muted small">（{{ log.from_status_text }} → ）</span>
                    </div>
                    <div class="muted small">
                      {{ log.operator_type === 'admin' ? '管理员' : (log.operator_type === 'system' ? '系统' : '用户') }}
                      · {{ formatDate(log.created_at) }}
                    </div>
                    <div v-if="log.remark" class="timeline-remark">{{ log.remark }}</div>
                  </div>
                </div>
              </div>
            </div>
          </template>
        </div>
      </div>
    </div>

    <div v-if="loading" class="loading-overlay">
      <div class="loading-spinner">
        <SvgIcon name="loading" />
        <span>加载中...</span>
      </div>
    </div>

    <ConfirmDialog v-model:visible="confirmState.visible" :title="confirmState.title"
      :message="confirmState.message" :type="confirmState.type" :confirm-text="confirmState.confirmText"
      :show-cancel="confirmState.showCancel" @confirm="handleConfirm" @cancel="handleCancel" />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount } from 'vue'
import SvgIcon from '@/components/SvgIcon.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import messageManager from '@/utils/messageManager'
import {
  adminGetOrders,
  adminGetOrderDetail,
  adminShipOrder,
  adminCloseOrder,
  adminRefundOrder
} from '@/api/shop.js'

const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'pending_payment', label: '待付款' },
  { value: 'pending_shipment', label: '待发货' },
  { value: 'shipped', label: '待收货' },
  { value: 'completed', label: '已完成' },
  { value: 'refunded', label: '已退款' },
  { value: 'cancelled', label: '已取消' },
  { value: 'closed', label: '已关闭' }
]

const STATUS_CLASS_MAP = {
  pending_payment: 'tag-warn', pending_shipment: 'tag-pending', shipped: 'tag-info',
  completed: 'tag-on', cancelled: 'tag-off', closed: 'tag-draft', refunded: 'tag-draft'
}
const statusClass = (s) => STATUS_CLASS_MAP[s] || 'tag-off'

const canShip = (s) => s === 'pending_shipment'
const canClose = (s) => s === 'shipped' || s === 'completed'
const canRefund = (item) => ['pending_shipment', 'shipped', 'completed'].includes(item.status) && item.refund_status !== 'refunded'

const list = ref([])
const loading = ref(false)
const submitting = ref(false)
const total = ref(0)
const page = ref(1)
const limit = ref(20)
const totalPages = ref(0)

const searchParams = reactive({ order_no: '', user_id: '', status: '' })

const statusDropdownOpen = ref(false)
const toggleStatusDropdown = () => { statusDropdownOpen.value = !statusDropdownOpen.value }
const selectStatus = (v) => { searchParams.status = v; statusDropdownOpen.value = false }
const statusLabel = computed(() => {
  const o = STATUS_OPTIONS.find(i => i.value === searchParams.status)
  return o ? o.label : '全部状态'
})

const showShipModal = ref(false)
const shipTarget = reactive({ id: null, order_no: '', status: '' })
const shipForm = reactive({ tracking_company: '', tracking_no: '' })

const showDetailModal = ref(false)
const detailLoading = ref(false)
const detail = ref(null)

const confirmState = reactive({
  visible: false, title: '确认操作', message: '', type: 'warning',
  confirmText: '确认', showCancel: true, resolve: null
})
const handleConfirm = () => { if (confirmState.resolve) confirmState.resolve(true) }
const handleCancel = () => { if (confirmState.resolve) confirmState.resolve(false) }

const firstImage = (item) => item.items && item.items.length > 0 ? item.items[0].product_image : ''
const firstTitle = (item) => item.items && item.items.length > 0 ? item.items[0].product_title : '-'

const formatDate = (d) => {
  if (!d) return '-'
  const dt = new Date(d)
  if (isNaN(dt.getTime())) return d
  const pad = (n) => String(n).padStart(2, '0')
  return `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())} ${pad(dt.getHours())}:${pad(dt.getMinutes())}`
}

const pageNumbers = computed(() => {
  const arr = []
  const start = Math.max(1, page.value - 2)
  const end = Math.min(totalPages.value, page.value + 2)
  for (let i = start; i <= end; i++) arr.push(i)
  return arr
})

const fetchList = async () => {
  loading.value = true
  try {
    const params = { page: page.value, limit: limit.value }
    if (searchParams.order_no) params.order_no = searchParams.order_no
    if (searchParams.user_id) params.user_id = searchParams.user_id
    if (searchParams.status) params.status = searchParams.status
    const res = await adminGetOrders(params)
    if (res.success) {
      list.value = res.data.data || []
      total.value = res.data.pagination?.total || 0
      totalPages.value = res.data.pagination?.pages || 0
    } else {
      messageManager.error(res.message || '获取订单列表失败')
    }
  } catch (e) {
    messageManager.error('获取订单列表失败')
  } finally {
    loading.value = false
  }
}

const handleSearch = () => { page.value = 1; fetchList() }
const clearSearch = () => {
  searchParams.order_no = ''
  searchParams.user_id = ''
  searchParams.status = ''
  page.value = 1
  fetchList()
}
const changePage = (p) => {
  if (p < 1 || p > totalPages.value) return
  page.value = p
  fetchList()
}

const openShipModal = (item) => {
  shipTarget.id = item.id
  shipTarget.order_no = item.order_no
  shipTarget.status = item.status
  shipForm.tracking_company = ''
  shipForm.tracking_no = ''
  showShipModal.value = true
}
const closeShipModal = () => { showShipModal.value = false }

const submitShip = async () => {
  if (!shipForm.tracking_company.trim() || !shipForm.tracking_no.trim()) {
    messageManager.warning('请填写物流公司和物流单号')
    return
  }
  submitting.value = true
  try {
    const res = await adminShipOrder(shipTarget.id, {
      tracking_company: shipForm.tracking_company.trim(),
      tracking_no: shipForm.tracking_no.trim()
    })
    if (res.success) {
      messageManager.success('发货成功')
      showShipModal.value = false
      fetchList()
    } else {
      messageManager.error(res.message || '发货失败')
    }
  } catch (e) {
    messageManager.error('发货失败')
  } finally {
    submitting.value = false
  }
}

const confirmClose = async (item) => {
  const ok = await new Promise((resolve) => {
    confirmState.message = `确定要关闭订单「${item.order_no}」吗？关闭后订单将终止。`
    confirmState.confirmText = '确认关闭'
    confirmState.type = 'warning'
    confirmState.resolve = resolve
    confirmState.visible = true
  })
  if (!ok) return
  try {
    const res = await adminCloseOrder(item.id, {})
    if (res.success) {
      messageManager.success('订单已关闭')
      fetchList()
    } else {
      messageManager.error(res.message || '关闭失败')
    }
  } catch (e) {
    messageManager.error('关闭失败')
  }
}

const confirmRefund = async (item) => {
  const reason = prompt(
    `确定对订单「${item.order_no}」发起全额退款（¥${item.pay_amount}）吗？\n款项将原路退回买家支付宝账户。\n（可选）填写退款原因：`,
    ''
  )
  if (reason === null) return
  const payload = reason === '' ? {} : { reason }
  try {
    const res = await adminRefundOrder(item.id, payload)
    if (res.success) {
      messageManager.success('退款成功，款项已原路退回买家')
      fetchList()
    } else {
      messageManager.error(res.message || '退款失败')
    }
  } catch (e) {
    messageManager.error('退款失败')
  }
}

const openDetail = async (item) => {
  showDetailModal.value = true
  detail.value = null
  detailLoading.value = true
  try {
    const res = await adminGetOrderDetail(item.id)
    if (res.success) {
      detail.value = res.data
    } else {
      messageManager.error(res.message || '获取详情失败')
      showDetailModal.value = false
    }
  } catch (e) {
    messageManager.error('获取详情失败')
    showDetailModal.value = false
  } finally {
    detailLoading.value = false
  }
}
const closeDetail = () => { showDetailModal.value = false }

const onDocClick = () => { statusDropdownOpen.value = false }

onMounted(() => {
  fetchList()
  document.addEventListener('click', onDocClick)
})
onBeforeUnmount(() => {
  document.removeEventListener('click', onDocClick)
})
</script>

<style scoped>
.order-management {
  background: var(--bg-color-primary);
  height: 100%;
  display: flex;
  flex-direction: column;
  min-height: 0;
  position: relative;
  transition: background-color 0.3s ease;
}

.table-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  padding: 15px 30px;
  border-bottom: 1px solid var(--border-color-primary);
  background-color: var(--bg-color-secondary);
  gap: 20px;
  transition: background-color 0.3s ease, border-color 0.3s ease;
}

.header-left {
  flex: 1;
}

.table-actions {
  display: flex;
  gap: 10px;
  flex-shrink: 0;
}

.search-bar {
  display: flex;
  align-items: center;
  gap: 15px;
  flex-wrap: wrap;
}

.search-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.search-field input {
  padding: 6px 10px;
  border: 1px solid var(--border-color-secondary);
  background-color: var(--bg-color-secondary);
  border-radius: 999px;
  font-size: 12px;
  min-width: 140px;
  height: 32px;
  color: var(--text-color-primary);
  box-sizing: border-box;
  transition: background-color 0.3s ease, border-color 0.3s ease;
}

.search-field input:focus {
  outline: none;
  border-color: var(--primary-color);
}

.custom-select {
  position: relative;
  display: inline-block;
  min-width: 130px;
  height: 32px;
  cursor: pointer;
}

.select-value {
  display: flex;
  align-items: center;
  padding: 6px 30px 6px 10px;
  border: 1px solid var(--border-color-secondary);
  background-color: var(--bg-color-secondary);
  border-radius: 999px;
  font-size: 12px;
  color: var(--text-color-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  height: 32px;
  box-sizing: border-box;
  transition: background-color 0.3s ease, border-color 0.3s ease;
}

.custom-select:hover .select-value {
  border-color: var(--primary-color);
}

.select-arrow {
  position: absolute;
  right: 8px;
  top: 50%;
  transform: translateY(-50%);
  width: 12px;
  height: 12px;
  color: var(--text-color-secondary);
  transition: transform 0.2s;
  pointer-events: none;
}

.select-arrow.rotated {
  transform: translateY(-50%) rotate(180deg);
}

.select-options {
  position: absolute;
  top: 100%;
  left: 0;
  right: 0;
  background: var(--bg-color-primary);
  border: 1px solid var(--border-color-secondary);
  border-radius: 6px;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
  z-index: 1000;
  max-height: 240px;
  overflow-y: auto;
  margin-top: 2px;
}

.select-option {
  padding: 8px 12px;
  font-size: 12px;
  color: var(--text-color-primary);
  cursor: pointer;
  transition: background-color 0.2s;
}

.select-option:hover {
  background-color: var(--bg-color-secondary);
}

.select-option.selected {
  background-color: var(--bg-color-secondary);
  font-weight: 500;
}

.table-container {
  flex: 1;
  overflow: auto;
  min-height: 0;
}

.data-table {
  width: 100%;
  border-collapse: collapse;
  table-layout: auto;
}

.data-table th,
.data-table td {
  padding: 12px 15px;
  text-align: left;
  border-bottom: 1px solid var(--border-color-primary);
  vertical-align: middle;
  transition: border-bottom 0.3s ease;
}

.data-table th {
  background-color: var(--bg-color-secondary);
  font-weight: 600;
  color: var(--text-color-primary);
  border-bottom: 1px solid transparent;
  transition: background-color 0.3s ease;
  position: sticky;
  top: 0;
  z-index: 1;
  white-space: nowrap;
}

.data-table tr {
  transition: background-color 0.3s ease;
}

.data-table tr:hover {
  background-color: var(--bg-color-secondary);
}

.muted {
  color: var(--text-color-secondary);
}

.small {
  font-size: 12px;
}

.order-no {
  font-weight: 500;
  color: var(--text-color-primary);
  white-space: nowrap;
}

.order-id {
  font-size: 12px;
  margin-top: 2px;
}

.buyer {
  display: flex;
  align-items: center;
  gap: 8px;
}

.buyer-avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  object-fit: cover;
  flex-shrink: 0;
}

.buyer-name {
  font-size: 13px;
  color: var(--text-color-primary);
  white-space: nowrap;
}

.buyer-account {
  font-size: 12px;
}

.goods-summary {
  display: flex;
  align-items: center;
  gap: 8px;
  max-width: 220px;
}

.goods-thumb {
  width: 40px;
  height: 40px;
  object-fit: cover;
  border-radius: 4px;
  flex-shrink: 0;
}

.placeholder-thumb {
  background: var(--bg-color-secondary);
}

.goods-text {
  min-width: 0;
}

.goods-title {
  font-size: 13px;
  color: var(--text-color-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.goods-count {
  font-size: 12px;
  margin-top: 2px;
}

.pay-amount {
  font-weight: 600;
  color: var(--danger-color);
}

.empty-row {
  text-align: center;
  color: var(--text-color-secondary);
  padding: 40px 15px;
}

.status-tag {
  display: inline-block;
  padding: 2px 10px;
  border-radius: 999px;
  font-size: 12px;
  white-space: nowrap;
}

.tag-on {
  background-color: rgba(103, 194, 58, 0.15);
  color: #67C23A;
}

.tag-off {
  background-color: rgba(245, 108, 108, 0.15);
  color: #F56C6C;
}

.tag-warn {
  background-color: rgba(230, 162, 60, 0.15);
  color: #E6A23C;
}

.tag-pending {
  background-color: rgba(64, 158, 255, 0.15);
  color: #409EFF;
}

.tag-info {
  background-color: rgba(64, 158, 255, 0.15);
  color: #409EFF;
}

.tag-draft {
  background-color: rgba(144, 147, 153, 0.15);
  color: #909399;
}

.action-cell {
  white-space: nowrap;
}

.action-cell .btn {
  margin-right: 6px;
}

.action-cell .btn:last-child {
  margin-right: 0;
}

.pagination {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 10px 30px;
  border-top: 1px solid var(--border-color-primary);
  background-color: var(--bg-color-secondary);
  transition: background-color 0.3s ease, border-color 0.3s ease;
}

.pagination-info {
  color: var(--text-color-secondary);
  font-size: 14px;
  user-select: none;
}

.pagination-controls {
  display: flex;
  align-items: center;
  gap: 10px;
}

.page-numbers {
  display: flex;
  gap: 5px;
}

.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: var(--overlay-bg);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.modal-dialog {
  background: var(--bg-color-primary);
  border-radius: 12px;
  width: 90%;
  max-width: 460px;
  max-height: 90vh;
  overflow: hidden;
  border: 1px solid var(--border-color-primary);
  display: flex;
  flex-direction: column;
}

.detail-overlay {
  align-items: flex-start;
  padding: 40px 20px;
}

.detail-dialog {
  max-width: 720px;
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 18px 24px;
  border-bottom: 1px solid var(--border-color-primary);
  flex-shrink: 0;
}

.modal-title {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
  color: var(--text-color-primary);
}

.close-btn {
  background: none;
  border: none;
  color: var(--text-color-secondary);
  cursor: pointer;
  padding: 4px 8px;
  border-radius: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.close-btn:hover {
  color: var(--text-color-primary);
}

.modal-body {
  padding: 20px 24px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.detail-body {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.detail-loading {
  padding: 40px 0;
  text-align: center;
  color: var(--text-color-secondary);
}

.form-row {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.form-label {
  font-size: 14px;
  color: var(--text-color-primary);
  font-weight: 500;
}

.required {
  color: var(--danger-color);
}

.static-value {
  font-size: 14px;
  color: var(--text-color-secondary);
  padding: 8px 0;
}

.form-input {
  padding: 8px 12px;
  border: 1px solid var(--border-color-secondary);
  background-color: var(--bg-color-secondary);
  border-radius: 6px;
  font-size: 14px;
  height: 38px;
  color: var(--text-color-primary);
  box-sizing: border-box;
  transition: border-color 0.2s;
}

.form-input:focus {
  outline: none;
  border-color: var(--primary-color);
}

.modal-footer {
  padding: 16px 24px 20px;
  display: flex;
  gap: 12px;
  justify-content: flex-end;
  border-top: 1px solid var(--border-color-primary);
  flex-shrink: 0;
}

.detail-section {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.detail-status-row {
  display: flex;
  align-items: center;
  gap: 12px;
}

.order-no-text {
  font-size: 14px;
  color: var(--text-color-secondary);
}

.detail-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px 20px;
}

.detail-item {
  font-size: 14px;
  color: var(--text-color-primary);
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.detail-item.full {
  grid-column: 1 / -1;
}

.dim {
  font-size: 12px;
  color: var(--text-color-secondary);
}

.detail-subtitle {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-color-primary);
  padding-bottom: 8px;
  border-bottom: 1px solid var(--border-color-primary);
}

.detail-goods {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.goods-line {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 0;
}

.goods-line .goods-thumb {
  width: 44px;
  height: 44px;
}

.goods-line-info {
  flex: 1;
  min-width: 0;
}

.goods-line-title {
  font-size: 13px;
  color: var(--text-color-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.goods-line-price,
.goods-line-qty,
.goods-line-sub {
  font-size: 13px;
  color: var(--text-color-primary);
  flex-shrink: 0;
}

.goods-line-sub {
  font-weight: 600;
  min-width: 70px;
  text-align: right;
}

.detail-amount {
  margin-top: 8px;
  padding-top: 12px;
  border-top: 1px solid var(--border-color-primary);
  display: flex;
  flex-direction: column;
  gap: 6px;
  align-items: flex-end;
}

.amount-row {
  display: flex;
  gap: 30px;
  font-size: 13px;
  color: var(--text-color-secondary);
}

.amount-row span:last-child {
  min-width: 80px;
  text-align: right;
  color: var(--text-color-primary);
}

.amount-total {
  font-size: 15px;
  margin-top: 4px;
}

.amount-total span:last-child {
  color: var(--danger-color);
  font-weight: 600;
  font-size: 17px;
}

.amount-refund span:last-child {
  color: #E6A23C;
  font-weight: 600;
  font-size: 15px;
}

.timeline {
  display: flex;
  flex-direction: column;
  gap: 0;
}

.timeline-item {
  display: flex;
  gap: 12px;
  padding-bottom: 16px;
  position: relative;
}

.timeline-item:not(:last-child)::before {
  content: '';
  position: absolute;
  left: 4px;
  top: 12px;
  bottom: 0;
  width: 2px;
  background-color: var(--border-color-primary);
}

.timeline-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background-color: var(--border-color-primary);
  flex-shrink: 0;
  margin-top: 4px;
  z-index: 1;
}

.dot-active {
  background-color: var(--primary-color);
}

.timeline-content {
  flex: 1;
}

.timeline-title {
  font-size: 14px;
  color: var(--text-color-primary);
  font-weight: 500;
}

.timeline-remark {
  font-size: 13px;
  color: var(--text-color-secondary);
  margin-top: 4px;
  padding: 6px 10px;
  background-color: var(--bg-color-secondary);
  border-radius: 4px;
}

.btn {
  padding: 8px 16px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  transition: all 0.2s;
  text-decoration: none;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-primary {
  background-color: var(--primary-color);
  color: white;
}

.btn-primary:hover:not(:disabled) {
  background-color: var(--primary-color-dark);
}

.btn-secondary {
  background-color: var(--text-color-tertiary);
  color: white;
}

.btn-secondary:hover:not(:disabled) {
  background-color: var(--text-color-secondary);
}

.btn-outline {
  background-color: transparent;
  color: var(--text-color-secondary);
  border: 1px solid var(--border-color-primary);
}

.btn-outline:hover:not(:disabled) {
  background-color: var(--bg-color-secondary);
}

.btn-danger {
  background-color: var(--danger-color);
  color: white;
}

.btn-danger:hover:not(:disabled) {
  background-color: var(--danger-color-dark);
}

.btn-sm {
  padding: 5px 10px;
  font-size: 12px;
}

.btn svg {
  width: 14px;
  height: 14px;
}

.loading-overlay {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: var(--overlay-bg);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 100;
}

.loading-spinner {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  color: var(--text-color-secondary);
}

.loading-spinner svg {
  width: 32px;
  height: 32px;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  from {
    transform: rotate(0deg);
  }

  to {
    transform: rotate(360deg);
  }
}
</style>
