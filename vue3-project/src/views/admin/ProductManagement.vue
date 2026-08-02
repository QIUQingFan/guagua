<template>
  <div class="product-management">
    <div class="table-header">
      <div class="header-left">
        <div class="search-bar">
          <div class="search-field">
            <input v-model="searchParams.keyword" type="text" placeholder="商品标题/副标题" @keyup.enter="handleSearch" />
          </div>
          <div class="search-field">
            <div class="custom-select" @click="toggleCategoryDropdown">
              <span class="select-value">{{ categoryLabel }}</span>
              <SvgIcon name="down" class="select-arrow" :class="{ rotated: categoryDropdownOpen }" />
              <div v-if="categoryDropdownOpen" class="select-options">
                <div class="select-option" :class="{ selected: !searchParams.category_id }"
                  @click.stop="selectCategory('')">全部分类</div>
                <div v-for="c in categoryOptions" :key="c.id" class="select-option"
                  :class="{ selected: Number(searchParams.category_id) === c.id }"
                  @click.stop="selectCategory(c.id)">{{ c.name }}</div>
              </div>
            </div>
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
          <div class="search-field price-range">
            <input v-model="searchParams.min_price" type="number" placeholder="最低价" @keyup.enter="handleSearch" />
            <span class="range-sep">-</span>
            <input v-model="searchParams.max_price" type="number" placeholder="最高价" @keyup.enter="handleSearch" />
          </div>
          <button class="btn btn-outline btn-sm" @click="handleSearch">筛选</button>
          <button class="btn btn-outline btn-sm" @click="clearSearch">清空</button>
        </div>
      </div>
      <div class="table-actions">
        <button class="btn btn-primary" @click="goCreate">
          <SvgIcon name="publish" />
          新增商品
        </button>
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
            <th>ID</th>
            <th>主图</th>
            <th>标题</th>
            <th>分类</th>
            <th>价格</th>
            <th>库存</th>
            <th>销量</th>
            <th>状态</th>
            <th>创建时间</th>
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="item in list" :key="item.id">
            <td>{{ item.id }}</td>
            <td>
              <img v-if="item.cover_image" :src="item.cover_image" alt="封面" class="table-image" v-img-fallback />
              <span v-else class="muted">-</span>
            </td>
            <td class="title-cell">
              <div class="title-text">{{ item.title }}</div>
              <div v-if="item.subtitle" class="subtitle-text">{{ item.subtitle }}</div>
            </td>
            <td>{{ item.category_name || '-' }}</td>
            <td>
              <div class="price-text">¥{{ item.price }}</div>
              <div v-if="item.original_price" class="original-price">¥{{ item.original_price }}</div>
            </td>
            <td :class="{ 'stock-warn': item.stock <= 0 }">{{ item.stock }}</td>
            <td>{{ item.sales }}</td>
            <td>
              <span class="status-tag" :class="statusClass(item.status)">{{ statusText(item.status) }}</span>
            </td>
            <td>{{ formatDate(item.created_at) }}</td>
            <td class="action-cell">
              <SvgIcon name="edit" class="action-icon" title="编辑" @click="goEdit(item.id)" />
              <SvgIcon v-if="item.status === 'on_sale'" name="collect" class="action-icon" title="下架"
                @click="toggleStatus(item)" />
              <SvgIcon v-else name="verified" class="action-icon" title="上架" @click="toggleStatus(item)" />
              <SvgIcon name="data" class="action-icon" title="调整库存" @click="openStockModal(item)" />
              <SvgIcon name="delete" class="action-icon" title="删除" @click="confirmDelete(item)" />
            </td>
          </tr>
          <tr v-if="!loading && list.length === 0">
            <td colspan="10" class="empty-row">暂无商品数据</td>
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

    <div v-if="showStockModal" class="modal-overlay" @click.self="closeStockModal">
      <div class="modal-dialog">
        <div class="modal-header">
          <h3 class="modal-title">调整库存</h3>
          <button class="close-btn" @click="closeStockModal">
            <SvgIcon name="close" width="20" height="20" />
          </button>
        </div>
        <div class="modal-body">
          <div class="form-row">
            <label class="form-label">商品</label>
            <div class="static-value">{{ stockTarget.title }}（当前库存 {{ stockTarget.stock }}）</div>
          </div>
          <div class="form-row">
            <label class="form-label">调整方式</label>
            <div class="radio-group">
              <label class="radio-item">
                <input type="radio" v-model="stockMode" value="absolute" /> 设为绝对值
              </label>
              <label class="radio-item">
                <input type="radio" v-model="stockMode" value="delta" /> 增减（负数为减少）
              </label>
            </div>
          </div>
          <div class="form-row">
            <label class="form-label">{{ stockMode === 'absolute' ? '库存数量' : '增减数量' }}</label>
            <input v-model.number="stockInput" type="number" class="form-input" placeholder="请输入数量" />
          </div>
        </div>
        <div class="modal-footer">
          <button class="btn btn-outline" @click="closeStockModal">取消</button>
          <button class="btn btn-primary" :disabled="submitting" @click="submitStock">
            {{ submitting ? '保存中...' : '确认调整' }}
          </button>
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
import { useRouter } from 'vue-router'
import SvgIcon from '@/components/SvgIcon.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import messageManager from '@/utils/messageManager'
import {
  adminGetProducts,
  adminDeleteProduct,
  adminUpdateProductStatus,
  adminUpdateProductStock,
  getShopCategories
} from '@/api/shop.js'

const router = useRouter()

const STATUS_OPTIONS = [
  { value: '', label: '全部状态' },
  { value: 'draft', label: '草稿' },
  { value: 'pending_review', label: '待审核' },
  { value: 'on_sale', label: '上架' },
  { value: 'off_sale', label: '下架' },
  { value: 'sold_out', label: '售罄' }
]

const STATUS_TEXT_MAP = {
  draft: '草稿', pending_review: '待审核', on_sale: '上架', off_sale: '下架', sold_out: '售罄'
}
const statusText = (s) => STATUS_TEXT_MAP[s] || s
const statusClass = (s) => ({
  draft: 'tag-draft', pending_review: 'tag-pending', on_sale: 'tag-on',
  off_sale: 'tag-off', sold_out: 'tag-warn'
})[s] || 'tag-off'

const list = ref([])
const loading = ref(false)
const submitting = ref(false)
const total = ref(0)
const page = ref(1)
const limit = ref(20)
const totalPages = ref(0)
const categoryOptions = ref([])

const searchParams = reactive({
  keyword: '', category_id: '', status: '', min_price: '', max_price: ''
})

const categoryDropdownOpen = ref(false)
const statusDropdownOpen = ref(false)
const toggleCategoryDropdown = () => { categoryDropdownOpen.value = !categoryDropdownOpen.value }
const toggleStatusDropdown = () => { statusDropdownOpen.value = !statusDropdownOpen.value }
const selectCategory = (v) => { searchParams.category_id = v; categoryDropdownOpen.value = false }
const selectStatus = (v) => { searchParams.status = v; statusDropdownOpen.value = false }

const categoryLabel = computed(() => {
  if (!searchParams.category_id) return '全部分类'
  const c = categoryOptions.value.find(i => i.id === Number(searchParams.category_id))
  return c ? c.name : '全部分类'
})
const statusLabel = computed(() => {
  const o = STATUS_OPTIONS.find(i => i.value === searchParams.status)
  return o ? o.label : '全部状态'
})

const showStockModal = ref(false)
const stockTarget = reactive({ id: null, title: '', stock: 0 })
const stockMode = ref('absolute')
const stockInput = ref(0)

const confirmState = reactive({
  visible: false, title: '确认操作', message: '', type: 'warning',
  confirmText: '确认', showCancel: true, resolve: null
})
const handleConfirm = () => { if (confirmState.resolve) confirmState.resolve(true) }
const handleCancel = () => { if (confirmState.resolve) confirmState.resolve(false) }

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
    if (searchParams.keyword) params.keyword = searchParams.keyword
    if (searchParams.category_id) params.category_id = searchParams.category_id
    if (searchParams.status) params.status = searchParams.status
    if (searchParams.min_price !== '') params.min_price = searchParams.min_price
    if (searchParams.max_price !== '') params.max_price = searchParams.max_price
    const res = await adminGetProducts(params)
    if (res.success) {
      list.value = res.data.data || []
      total.value = res.data.pagination?.total || 0
      totalPages.value = res.data.pagination?.pages || 0
    } else {
      messageManager.error(res.message || '获取商品列表失败')
    }
  } catch (e) {
    messageManager.error('获取商品列表失败')
  } finally {
    loading.value = false
  }
}

const fetchCategories = async () => {
  try {
    const res = await getShopCategories({ flat: 1 })
    categoryOptions.value = res.success ? (res.data || []) : []
  } catch (e) {
    categoryOptions.value = []
  }
}

const handleSearch = () => { page.value = 1; fetchList() }
const clearSearch = () => {
  searchParams.keyword = ''
  searchParams.category_id = ''
  searchParams.status = ''
  searchParams.min_price = ''
  searchParams.max_price = ''
  page.value = 1
  fetchList()
}
const changePage = (p) => {
  if (p < 1 || p > totalPages.value) return
  page.value = p
  fetchList()
}

const goCreate = () => router.push('/admin/products/create')
const goEdit = (id) => router.push(`/admin/products/edit/${id}`)

const toggleStatus = async (item) => {
  const next = item.status === 'on_sale' ? 'off_sale' : 'on_sale'
  try {
    const res = await adminUpdateProductStatus(item.id, next)
    if (res.success) {
      messageManager.success(next === 'on_sale' ? '已上架' : '已下架')
      fetchList()
    } else {
      messageManager.error(res.message || '操作失败')
    }
  } catch (e) {
    messageManager.error('操作失败')
  }
}

const openStockModal = (item) => {
  stockTarget.id = item.id
  stockTarget.title = item.title
  stockTarget.stock = item.stock
  stockMode.value = 'absolute'
  stockInput.value = item.stock
  showStockModal.value = true
}
const closeStockModal = () => { showStockModal.value = false }

const submitStock = async () => {
  if (!Number.isFinite(stockInput.value) || stockInput.value === null) {
    messageManager.warning('请输入有效数量')
    return
  }
  const payload = stockMode.value === 'absolute'
    ? { stock: stockInput.value }
    : { delta: stockInput.value }
  submitting.value = true
  try {
    const res = await adminUpdateProductStock(stockTarget.id, payload)
    if (res.success) {
      messageManager.success('库存已更新')
      showStockModal.value = false
      fetchList()
    } else {
      messageManager.error(res.message || '更新失败')
    }
  } catch (e) {
    messageManager.error('更新失败')
  } finally {
    submitting.value = false
  }
}

const confirmDelete = async (item) => {
  const ok = await new Promise((resolve) => {
    confirmState.message = `确定要删除商品「${item.title}」吗？删除后前台将不可见。`
    confirmState.confirmText = '删除'
    confirmState.type = 'error'
    confirmState.resolve = resolve
    confirmState.visible = true
  })
  if (!ok) return
  try {
    const res = await adminDeleteProduct(item.id)
    if (res.success) {
      messageManager.success('删除成功')
      fetchList()
    } else {
      messageManager.error(res.message || '删除失败')
    }
  } catch (e) {
    messageManager.error('删除失败')
  }
}

const onDocClick = () => {
  categoryDropdownOpen.value = false
  statusDropdownOpen.value = false
}

onMounted(() => {
  fetchList()
  fetchCategories()
  document.addEventListener('click', onDocClick)
})
onBeforeUnmount(() => {
  document.removeEventListener('click', onDocClick)
})
</script>

<style scoped>
.product-management {
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
  min-width: 130px;
  height: 32px;
  color: var(--text-color-primary);
  box-sizing: border-box;
  transition: background-color 0.3s ease, border-color 0.3s ease;
}

.search-field input:focus {
  outline: none;
  border-color: var(--primary-color);
}

.price-range {
  flex-direction: row;
  align-items: center;
  gap: 6px;
}

.price-range input {
  min-width: 90px;
}

.range-sep {
  color: var(--text-color-secondary);
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

.table-image {
  width: 44px;
  height: 44px;
  object-fit: cover;
  border-radius: 4px;
}

.title-cell {
  max-width: 220px;
}

.title-text {
  font-weight: 500;
  color: var(--text-color-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.subtitle-text {
  font-size: 12px;
  color: var(--text-color-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin-top: 2px;
}

.price-text {
  font-weight: 600;
  color: var(--danger-color);
}

.original-price {
  font-size: 12px;
  color: var(--text-color-secondary);
  text-decoration: line-through;
}

.stock-warn {
  color: var(--danger-color);
  font-weight: 600;
}

.muted {
  color: var(--text-color-secondary);
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

.tag-draft {
  background-color: rgba(144, 147, 153, 0.15);
  color: #909399;
}

.action-cell {
  white-space: nowrap;
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

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 18px 24px;
  border-bottom: 1px solid var(--border-color-primary);
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

.radio-group {
  display: flex;
  gap: 20px;
}

.radio-item {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 14px;
  color: var(--text-color-primary);
  cursor: pointer;
}

.modal-footer {
  padding: 16px 24px 20px;
  display: flex;
  gap: 12px;
  justify-content: flex-end;
  border-top: 1px solid var(--border-color-primary);
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

.btn-sm {
  padding: 6px 12px;
  font-size: 12px;
}

.btn svg {
  width: 14px;
  height: 14px;
}

.action-icon {
  width: 22px;
  height: 22px;
  color: var(--text-color-secondary);
  cursor: pointer;
  margin-right: 6px;
}

.action-icon:last-child {
  margin-right: 0;
}

.action-icon:hover {
  color: var(--primary-color);
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
