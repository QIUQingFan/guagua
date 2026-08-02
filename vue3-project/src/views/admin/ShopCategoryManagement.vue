<template>
  <div class="shop-category-management">
    <div class="table-header">
      <div class="header-left">
        <div class="search-bar">
          <div class="search-field">
            <input v-model="searchParams.name" type="text" placeholder="分类名称" @keyup.enter="handleSearch" />
          </div>
          <div class="search-field">
            <div class="custom-select" @click="toggleActiveDropdown">
              <span class="select-value">{{ activeLabel }}</span>
              <SvgIcon name="down" class="select-arrow" :class="{ rotated: activeDropdownOpen }" />
              <div v-if="activeDropdownOpen" class="select-options">
                <div class="select-option" :class="{ selected: searchParams.is_active === '' }"
                  @click.stop="selectActive('')">全部</div>
                <div class="select-option" :class="{ selected: searchParams.is_active === 1 }"
                  @click.stop="selectActive(1)">启用</div>
                <div class="select-option" :class="{ selected: searchParams.is_active === 0 }"
                  @click.stop="selectActive(0)">停用</div>
              </div>
            </div>
          </div>
          <button class="btn btn-outline btn-sm" @click="handleSearch">筛选</button>
          <button class="btn btn-outline btn-sm" @click="clearSearch">清空</button>
        </div>
      </div>
      <div class="table-actions">
        <button class="btn btn-primary" @click="openCreate">
          <SvgIcon name="publish" />
          新增分类
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
            <th>分类名称</th>
            <th>父分类</th>
            <th>排序</th>
            <th>图标</th>
            <th>状态</th>
            <th>创建时间</th>
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="item in list" :key="item.id">
            <td>{{ item.id }}</td>
            <td>{{ item.name }}</td>
            <td>{{ parentName(item.parent_id) }}</td>
            <td>{{ item.sort }}</td>
            <td>
              <img v-if="item.icon" :src="item.icon" alt="icon" class="table-image" v-img-fallback />
              <span v-else class="muted">-</span>
            </td>
            <td>
              <span class="status-tag" :class="item.is_active ? 'tag-on' : 'tag-off'">
                {{ item.is_active ? '启用' : '停用' }}
              </span>
            </td>
            <td>{{ formatDate(item.created_at) }}</td>
            <td>
              <SvgIcon name="edit" class="action-icon" title="编辑" @click="openEdit(item)" />
              <SvgIcon name="delete" class="action-icon" title="删除" @click="confirmDelete(item)" />
            </td>
          </tr>
          <tr v-if="!loading && list.length === 0">
            <td colspan="8" class="empty-row">暂无分类数据</td>
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

    <div v-if="showForm" class="modal-overlay" @click.self="closeForm">
      <div class="modal-dialog">
        <div class="modal-header">
          <h3 class="modal-title">{{ editingId ? '编辑分类' : '新增分类' }}</h3>
          <button class="close-btn" @click="closeForm">
            <SvgIcon name="close" width="20" height="20" />
          </button>
        </div>
        <div class="modal-body">
          <div class="form-row">
            <label class="form-label">分类名称 <span class="required">*</span></label>
            <input v-model="formData.name" type="text" class="form-input" maxlength="64"
              placeholder="请输入分类名称" />
          </div>
          <div class="form-row">
            <label class="form-label">父分类</label>
            <div class="custom-select form-select" @click="toggleParentDropdown">
              <span class="select-value">{{ parentLabel }}</span>
              <SvgIcon name="down" class="select-arrow" :class="{ rotated: parentDropdownOpen }" />
              <div v-if="parentDropdownOpen" class="select-options">
                <div class="select-option" :class="{ selected: formData.parent_id === 0 }"
                  @click.stop="selectParent(0)">顶级分类</div>
                <div v-for="c in parentOptions" :key="c.id" class="select-option"
                  :class="{ selected: formData.parent_id === c.id }" @click.stop="selectParent(c.id)">
                  {{ c.name }}
                </div>
              </div>
            </div>
          </div>
          <div class="form-row">
            <label class="form-label">排序</label>
            <input v-model.number="formData.sort" type="number" class="form-input" placeholder="越大越靠前" />
          </div>
          <div class="form-row">
            <label class="form-label">图标 URL</label>
            <input v-model="formData.icon" type="text" class="form-input" placeholder="可选，分类图标地址" />
          </div>
          <div class="form-row">
            <label class="form-label">状态</label>
            <div class="custom-select form-select" @click="toggleFormActiveDropdown">
              <span class="select-value">{{ formData.is_active ? '启用' : '停用' }}</span>
              <SvgIcon name="down" class="select-arrow" :class="{ rotated: formActiveDropdownOpen }" />
              <div v-if="formActiveDropdownOpen" class="select-options">
                <div class="select-option" :class="{ selected: formData.is_active === 1 }"
                  @click.stop="selectFormActive(1)">启用</div>
                <div class="select-option" :class="{ selected: formData.is_active === 0 }"
                  @click.stop="selectFormActive(0)">停用</div>
              </div>
            </div>
          </div>
        </div>
        <div class="modal-footer">
          <button class="btn btn-outline" @click="closeForm">取消</button>
          <button class="btn btn-primary" :disabled="submitting" @click="submitForm">
            {{ submitting ? '保存中...' : '保存' }}
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
import SvgIcon from '@/components/SvgIcon.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import messageManager from '@/utils/messageManager'
import {
  adminGetShopCategories,
  adminCreateShopCategory,
  adminUpdateShopCategory,
  adminDeleteShopCategory
} from '@/api/shop.js'

const list = ref([])
const loading = ref(false)
const submitting = ref(false)
const total = ref(0)
const page = ref(1)
const limit = ref(20)
const totalPages = ref(0)

const searchParams = reactive({ name: '', is_active: '' })

const showForm = ref(false)
const editingId = ref(null)
const formData = reactive({ name: '', parent_id: 0, sort: 0, icon: '', is_active: 1 })
const parentOptions = ref([])

const activeDropdownOpen = ref(false)
const parentDropdownOpen = ref(false)
const formActiveDropdownOpen = ref(false)

const toggleActiveDropdown = () => { activeDropdownOpen.value = !activeDropdownOpen.value }
const selectActive = (v) => { searchParams.is_active = v; activeDropdownOpen.value = false }
const toggleParentDropdown = () => { parentDropdownOpen.value = !parentDropdownOpen.value }
const selectParent = (v) => { formData.parent_id = v; parentDropdownOpen.value = false }
const toggleFormActiveDropdown = () => { formActiveDropdownOpen.value = !formActiveDropdownOpen.value }
const selectFormActive = (v) => { formData.is_active = v; formActiveDropdownOpen.value = false }

const activeLabel = computed(() => {
  if (searchParams.is_active === 1) return '启用'
  if (searchParams.is_active === 0) return '停用'
  return '全部状态'
})
const parentLabel = computed(() => {
  if (formData.parent_id === 0) return '顶级分类'
  const c = parentOptions.value.find(i => i.id === formData.parent_id)
  return c ? c.name : '顶级分类'
})

const confirmState = reactive({
  visible: false, title: '确认删除', message: '', type: 'error',
  confirmText: '删除', showCancel: true, resolve: null
})
const handleConfirm = () => { if (confirmState.resolve) confirmState.resolve(true) }
const handleCancel = () => { if (confirmState.resolve) confirmState.resolve(false) }

const parentName = (parentId) => {
  if (!parentId) return '顶级分类'
  const c = parentOptions.value.find(i => i.id === parentId)
  return c ? c.name : parentId
}

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
    if (searchParams.name) params.name = searchParams.name
    if (searchParams.is_active !== '') params.is_active = searchParams.is_active
    const res = await adminGetShopCategories(params)
    if (res.success) {
      list.value = res.data.data || []
      total.value = res.data.total || 0
      totalPages.value = res.data.totalPages || 0
    } else {
      messageManager.error(res.message || '获取分类列表失败')
    }
  } catch (e) {
    messageManager.error('获取分类列表失败')
  } finally {
    loading.value = false
  }
}

const fetchParentOptions = async () => {
  try {
    const res = await adminGetShopCategories({ page: 1, limit: 200 })
    if (res.success) parentOptions.value = res.data.data || []
  } catch (e) {
    parentOptions.value = []
  }
}

const handleSearch = () => { page.value = 1; fetchList() }
const clearSearch = () => {
  searchParams.name = ''
  searchParams.is_active = ''
  page.value = 1
  fetchList()
}
const changePage = (p) => {
  if (p < 1 || p > totalPages.value) return
  page.value = p
  fetchList()
}

const openCreate = () => {
  editingId.value = null
  formData.name = ''
  formData.parent_id = 0
  formData.sort = 0
  formData.icon = ''
  formData.is_active = 1
  showForm.value = true
}

const openEdit = (item) => {
  editingId.value = item.id
  formData.name = item.name
  formData.parent_id = item.parent_id || 0
  formData.sort = item.sort
  formData.icon = item.icon || ''
  formData.is_active = item.is_active
  showForm.value = true
}

const closeForm = () => { showForm.value = false }

const submitForm = async () => {
  if (!formData.name || !formData.name.trim()) {
    messageManager.warning('请输入分类名称')
    return
  }
  submitting.value = true
  try {
    const payload = {
      name: formData.name.trim(),
      parent_id: Number(formData.parent_id) || 0,
      sort: Number(formData.sort) || 0,
      icon: formData.icon || null,
      is_active: formData.is_active ? 1 : 0
    }
    let res
    if (editingId.value) {
      res = await adminUpdateShopCategory(editingId.value, payload)
    } else {
      res = await adminCreateShopCategory(payload)
    }
    if (res.success) {
      messageManager.success(editingId.value ? '更新成功' : '创建成功')
      showForm.value = false
      fetchList()
      fetchParentOptions()
    } else {
      messageManager.error(res.message || '保存失败')
    }
  } catch (e) {
    messageManager.error('保存失败')
  } finally {
    submitting.value = false
  }
}

const confirmDelete = async (item) => {
  const ok = await new Promise((resolve) => {
    confirmState.message = `确定要删除分类「${item.name}」吗？删除后不可恢复。`
    confirmState.resolve = resolve
    confirmState.visible = true
  })
  if (!ok) return
  try {
    const res = await adminDeleteShopCategory(item.id)
    if (res.success) {
      messageManager.success('删除成功')
      fetchList()
      fetchParentOptions()
    } else {
      messageManager.error(res.message || '删除失败')
    }
  } catch (e) {
    messageManager.error('删除失败')
  }
}

const onDocClick = () => {
  activeDropdownOpen.value = false
  parentDropdownOpen.value = false
  formActiveDropdownOpen.value = false
}

onMounted(() => {
  fetchList()
  fetchParentOptions()
  document.addEventListener('click', onDocClick)
})
onBeforeUnmount(() => {
  document.removeEventListener('click', onDocClick)
})
</script>

<style scoped>
.shop-category-management {
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
  min-width: 140px;
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
  max-height: 220px;
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
  color: var(--text-color-primary);
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
}

.data-table tr {
  transition: background-color 0.3s ease;
}

.data-table tr:hover {
  background-color: var(--bg-color-secondary);
}

.data-table td:last-child {
  white-space: nowrap;
}

.empty-row {
  text-align: center;
  color: var(--text-color-secondary);
  padding: 40px 15px;
}

.muted {
  color: var(--text-color-secondary);
}

.table-image {
  width: 36px;
  height: 36px;
  object-fit: cover;
  border-radius: 4px;
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
  max-width: 480px;
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

.required {
  color: var(--danger-color);
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

.form-select {
  width: 100%;
  height: 38px;
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
  width: 24px;
  height: 24px;
  color: var(--text-color-secondary);
  cursor: pointer;
  margin-right: 8px;
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
