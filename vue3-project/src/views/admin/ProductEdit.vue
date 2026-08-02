<template>
  <div class="product-edit">
    <div class="edit-toolbar">
      <button class="btn btn-outline btn-sm" @click="goBack">
        <SvgIcon name="left" />
        返回列表
      </button>
      <h2 class="edit-title">{{ isEdit ? '编辑商品' : '新增商品' }}</h2>
    </div>

    <div class="edit-body">
      <section class="form-section">
        <h3 class="section-title">基础信息</h3>
        <div class="form-grid">
          <div class="form-row">
            <label class="form-label">商品标题 <span class="required">*</span></label>
            <input v-model="formData.title" type="text" class="form-input" maxlength="128" placeholder="请输入商品标题" />
          </div>
          <div class="form-row">
            <label class="form-label">副标题</label>
            <input v-model="formData.subtitle" type="text" class="form-input" maxlength="255" placeholder="可选，一句话卖点" />
          </div>
          <div class="form-row">
            <label class="form-label">分类 <span class="required">*</span></label>
            <div class="custom-select form-select" @click="toggleCategoryDropdown">
              <span class="select-value">{{ categoryLabel }}</span>
              <SvgIcon name="down" class="select-arrow" :class="{ rotated: categoryDropdownOpen }" />
              <div v-if="categoryDropdownOpen" class="select-options">
                <div v-for="c in categoryOptions" :key="c.id" class="select-option"
                  :class="{ selected: Number(formData.category_id) === c.id }"
                  @click.stop="selectCategory(c.id)">{{ c.name }}</div>
              </div>
            </div>
          </div>
          <div class="form-row">
            <label class="form-label">商品状态 <span class="required">*</span></label>
            <div class="custom-select form-select" @click="toggleStatusDropdown">
              <span class="select-value">{{ statusLabel }}</span>
              <SvgIcon name="down" class="select-arrow" :class="{ rotated: statusDropdownOpen }" />
              <div v-if="statusDropdownOpen" class="select-options">
                <div v-for="opt in STATUS_OPTIONS" :key="opt.value" class="select-option"
                  :class="{ selected: formData.status === opt.value }"
                  @click.stop="selectStatus(opt.value)">{{ opt.label }}</div>
              </div>
            </div>
          </div>
          <div class="form-row">
            <label class="form-label">现价 <span class="required">*</span></label>
            <input v-model="formData.price" type="number" step="0.01" min="0" class="form-input" placeholder="0.00" />
          </div>
          <div class="form-row">
            <label class="form-label">原价（划线价）</label>
            <input v-model="formData.original_price" type="number" step="0.01" min="0" class="form-input" placeholder="可选" />
          </div>
          <div class="form-row">
            <label class="form-label">库存 <span class="required">*</span></label>
            <input v-model="formData.stock" type="number" min="0" step="1" class="form-input" placeholder="0" />
          </div>
          <div class="form-row">
            <label class="form-label">封面图 URL</label>
            <input v-model="formData.cover_image" type="text" class="form-input" placeholder="主图地址" />
          </div>
        </div>
        <div class="form-row full">
          <label class="form-label">商品描述</label>
          <textarea v-model="formData.description" class="form-textarea" rows="5" placeholder="富文本描述（选填）"></textarea>
        </div>
      </section>

      <section class="form-section">
        <div class="section-header">
          <h3 class="section-title">商品图片</h3>
          <button class="btn btn-outline btn-sm" @click="addImage">
            <SvgIcon name="publish" />
            添加图片
          </button>
        </div>
        <div v-if="formData.images.length === 0" class="empty-tip">暂无图片，点击右上角添加（按顺序展示）</div>
        <div class="image-list">
          <div v-for="(img, idx) in formData.images" :key="idx" class="image-item">
            <img v-if="img" :src="img" alt="商品图" class="image-preview" @error="onImgError($event)" />
            <div v-else class="image-placeholder">无图</div>
            <input v-model="formData.images[idx]" type="text" class="image-url-input" placeholder="图片 URL" />
            <button class="btn btn-danger btn-sm" @click="removeImage(idx)">
              <SvgIcon name="delete" />
            </button>
          </div>
        </div>
      </section>

      <section class="form-section">
        <div class="section-header">
          <h3 class="section-title">SKU 规格</h3>
          <button class="btn btn-outline btn-sm" @click="addSku">
            <SvgIcon name="publish" />
            添加规格
          </button>
        </div>
        <div v-if="formData.skus.length === 0" class="empty-tip">暂无规格，如无多规格可不填（统一按 SPU 价/库存）</div>
        <div v-for="(sku, idx) in formData.skus" :key="idx" class="sku-row">
          <div class="sku-field sku-spec">
            <label class="sku-label">规格描述</label>
            <input v-model="sku.spec" type="text" class="form-input" placeholder="如 颜色:黑色;尺码:L" />
          </div>
          <div class="sku-field">
            <label class="sku-label">规格价</label>
            <input v-model="sku.price" type="number" step="0.01" min="0" class="form-input" placeholder="0.00" />
          </div>
          <div class="sku-field">
            <label class="sku-label">规格库存</label>
            <input v-model="sku.stock" type="number" min="0" step="1" class="form-input" placeholder="0" />
          </div>
          <div class="sku-field">
            <label class="sku-label">SKU 编码</label>
            <input v-model="sku.sku_code" type="text" class="form-input" placeholder="可选" />
          </div>
          <button class="btn btn-danger btn-sm sku-remove" @click="removeSku(idx)">
            <SvgIcon name="delete" />
          </button>
        </div>
      </section>

      <div class="submit-bar">
        <button class="btn btn-outline" @click="goBack">取消</button>
        <button class="btn btn-primary" :disabled="submitting" @click="submit">
          {{ submitting ? '保存中...' : (isEdit ? '保存修改' : '创建商品') }}
        </button>
      </div>
    </div>

    <div v-if="loading" class="loading-overlay">
      <div class="loading-spinner">
        <SvgIcon name="loading" />
        <span>加载中...</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import SvgIcon from '@/components/SvgIcon.vue'
import messageManager from '@/utils/messageManager'
import {
  adminGetProductDetail,
  adminCreateProduct,
  adminUpdateProduct,
  getShopCategories
} from '@/api/shop.js'

const route = useRoute()
const router = useRouter()

const STATUS_OPTIONS = [
  { value: 'draft', label: '草稿' },
  { value: 'on_sale', label: '上架' },
  { value: 'off_sale', label: '下架' }
]

const isEdit = computed(() => !!route.params.id)
const loading = ref(false)
const submitting = ref(false)
const categoryOptions = ref([])

const formData = reactive({
  title: '',
  subtitle: '',
  category_id: '',
  status: 'draft',
  price: '',
  original_price: '',
  stock: 0,
  cover_image: '',
  description: '',
  images: [],
  skus: []
})

const categoryDropdownOpen = ref(false)
const statusDropdownOpen = ref(false)
const toggleCategoryDropdown = () => { categoryDropdownOpen.value = !categoryDropdownOpen.value }
const toggleStatusDropdown = () => { statusDropdownOpen.value = !statusDropdownOpen.value }
const selectCategory = (v) => { formData.category_id = v; categoryDropdownOpen.value = false }
const selectStatus = (v) => { formData.status = v; statusDropdownOpen.value = false }

const categoryLabel = computed(() => {
  if (!formData.category_id) return '请选择分类'
  const c = categoryOptions.value.find(i => i.id === Number(formData.category_id))
  return c ? c.name : '请选择分类'
})
const statusLabel = computed(() => {
  const o = STATUS_OPTIONS.find(i => i.value === formData.status)
  return o ? o.label : '请选择'
})

const addImage = () => formData.images.push('')
const removeImage = (idx) => formData.images.splice(idx, 1)
const addSku = () => formData.skus.push({ spec: '', price: '', stock: 0, sku_code: '' })
const removeSku = (idx) => formData.skus.splice(idx, 1)

const onImgError = (e) => { e.target.style.display = 'none' }

const goBack = () => router.push('/admin/products')

const fetchCategories = async () => {
  try {
    const res = await getShopCategories({ flat: 1 })
    categoryOptions.value = res.success ? (res.data || []) : []
  } catch (e) {
    categoryOptions.value = []
  }
}

const fetchDetail = async () => {
  if (!isEdit.value) return
  loading.value = true
  try {
    const res = await adminGetProductDetail(route.params.id)
    if (res.success) {
      const p = res.data
      formData.title = p.title || ''
      formData.subtitle = p.subtitle || ''
      formData.category_id = p.category_id || ''
      formData.status = p.status || 'draft'
      formData.price = p.price ?? ''
      formData.original_price = p.original_price ?? ''
      formData.stock = p.stock ?? 0
      formData.cover_image = p.cover_image || ''
      formData.description = p.description || ''
      formData.images = Array.isArray(p.images) ? [...p.images] : []
      formData.skus = Array.isArray(p.skus)
        ? p.skus.map(s => ({ spec: s.spec || '', price: s.price ?? '', stock: s.stock ?? 0, sku_code: s.sku_code || '' }))
        : []
    } else {
      messageManager.error(res.message || '获取商品详情失败')
      goBack()
    }
  } catch (e) {
    messageManager.error('获取商品详情失败')
    goBack()
  } finally {
    loading.value = false
  }
}

const isValidAmount = (v) => {
  const n = Number(v)
  return v !== '' && v !== null && v !== undefined && !isNaN(n) && n >= 0
}

const submit = async () => {
  if (!formData.title || !formData.title.trim()) {
    messageManager.warning('请输入商品标题')
    return
  }
  if (!formData.category_id) {
    messageManager.warning('请选择分类')
    return
  }
  if (!isValidAmount(formData.price)) {
    messageManager.warning('请输入有效的商品价格')
    return
  }
  const stockNum = parseInt(formData.stock)
  if (!Number.isFinite(stockNum) || stockNum < 0) {
    messageManager.warning('请输入有效的库存数量')
    return
  }
  if (formData.original_price !== '' && formData.original_price !== null && !isValidAmount(formData.original_price)) {
    messageManager.warning('原价格式不正确')
    return
  }

  const payload = {
    title: formData.title.trim(),
    subtitle: formData.subtitle || null,
    category_id: Number(formData.category_id),
    status: formData.status,
    price: String(formData.price),
    original_price: (formData.original_price !== '' && formData.original_price !== null)
      ? String(formData.original_price) : null,
    stock: stockNum,
    cover_image: formData.cover_image || null,
    description: formData.description || null,
    images: formData.images.filter(u => u && typeof u === 'string' && u.trim()),
    skus: formData.skus
      .filter(s => s.spec && s.spec.trim() && isValidAmount(s.price))
      .map(s => ({
        spec: String(s.spec).trim(),
        price: String(s.price),
        stock: parseInt(s.stock) || 0,
        sku_code: s.sku_code || null
      }))
  }

  submitting.value = true
  try {
    const res = isEdit.value
      ? await adminUpdateProduct(route.params.id, payload)
      : await adminCreateProduct(payload)
    if (res.success) {
      messageManager.success(isEdit.value ? '保存成功' : '创建成功')
      router.push('/admin/products')
    } else {
      messageManager.error(res.message || '保存失败')
    }
  } catch (e) {
    messageManager.error('保存失败')
  } finally {
    submitting.value = false
  }
}

const onDocClick = () => {
  categoryDropdownOpen.value = false
  statusDropdownOpen.value = false
}

onMounted(() => {
  fetchCategories()
  fetchDetail()
  document.addEventListener('click', onDocClick)
})
onBeforeUnmount(() => {
  document.removeEventListener('click', onDocClick)
})
</script>

<style scoped>
.product-edit {
  background: var(--bg-color-primary);
  height: 100%;
  display: flex;
  flex-direction: column;
  min-height: 0;
  overflow-y: auto;
  position: relative;
  transition: background-color 0.3s ease;
}

.edit-toolbar {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 15px 30px;
  border-bottom: 1px solid var(--border-color-primary);
  background-color: var(--bg-color-secondary);
  transition: background-color 0.3s ease, border-color 0.3s ease;
}

.edit-title {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
  color: var(--text-color-primary);
}

.edit-body {
  padding: 24px 30px;
  display: flex;
  flex-direction: column;
  gap: 24px;
  max-width: 900px;
}

.form-section {
  background: var(--bg-color-secondary);
  border: 1px solid var(--border-color-primary);
  border-radius: 8px;
  padding: 20px 24px;
  transition: background-color 0.3s ease, border-color 0.3s ease;
}

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
}

.section-title {
  margin: 0 0 16px 0;
  font-size: 16px;
  font-weight: 600;
  color: var(--text-color-primary);
}

.section-header .section-title {
  margin: 0;
}

.form-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 16px;
}

.form-row {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.form-row.full {
  margin-top: 16px;
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
  background-color: var(--bg-color-primary);
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

.form-textarea {
  padding: 8px 12px;
  border: 1px solid var(--border-color-secondary);
  background-color: var(--bg-color-primary);
  border-radius: 6px;
  font-size: 14px;
  color: var(--text-color-primary);
  box-sizing: border-box;
  resize: vertical;
  font-family: inherit;
  transition: border-color 0.2s;
}

.form-textarea:focus {
  outline: none;
  border-color: var(--primary-color);
}

.custom-select {
  position: relative;
  display: inline-block;
  width: 100%;
  height: 38px;
  cursor: pointer;
}

.select-value {
  display: flex;
  align-items: center;
  padding: 8px 30px 8px 12px;
  border: 1px solid var(--border-color-secondary);
  background-color: var(--bg-color-primary);
  border-radius: 6px;
  font-size: 14px;
  color: var(--text-color-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  height: 38px;
  box-sizing: border-box;
  transition: border-color 0.2s;
}

.custom-select:hover .select-value {
  border-color: var(--primary-color);
}

.select-arrow {
  position: absolute;
  right: 10px;
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
  font-size: 14px;
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

.empty-tip {
  color: var(--text-color-secondary);
  font-size: 13px;
  padding: 8px 0;
}

.image-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.image-item {
  display: flex;
  align-items: center;
  gap: 10px;
}

.image-preview {
  width: 48px;
  height: 48px;
  object-fit: cover;
  border-radius: 4px;
  flex-shrink: 0;
  border: 1px solid var(--border-color-secondary);
}

.image-placeholder {
  width: 48px;
  height: 48px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  background: var(--bg-color-primary);
  color: var(--text-color-secondary);
  font-size: 12px;
  flex-shrink: 0;
  border: 1px solid var(--border-color-secondary);
}

.image-url-input {
  flex: 1;
  padding: 8px 12px;
  border: 1px solid var(--border-color-secondary);
  background-color: var(--bg-color-primary);
  border-radius: 6px;
  font-size: 14px;
  height: 38px;
  color: var(--text-color-primary);
  box-sizing: border-box;
  transition: border-color 0.2s;
}

.image-url-input:focus {
  outline: none;
  border-color: var(--primary-color);
}

.sku-row {
  display: flex;
  align-items: flex-end;
  gap: 12px;
  padding: 12px;
  background: var(--bg-color-primary);
  border: 1px solid var(--border-color-secondary);
  border-radius: 6px;
  margin-bottom: 10px;
}

.sku-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.sku-spec {
  flex: 2;
}

.sku-field:not(.sku-spec) {
  flex: 1;
}

.sku-label {
  font-size: 12px;
  color: var(--text-color-secondary);
}

.sku-remove {
  flex-shrink: 0;
}

.submit-bar {
  display: flex;
  gap: 12px;
  justify-content: flex-end;
  padding-bottom: 40px;
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
  padding: 6px 12px;
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

@media (max-width: 720px) {
  .form-grid {
    grid-template-columns: 1fr;
  }

  .sku-row {
    flex-wrap: wrap;
  }
}
</style>
