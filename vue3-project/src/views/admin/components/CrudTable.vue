<template>
  <div class="crud-table">

    <div class="table-header">
      <div class="header-left">

        <div class="search-bar desktop-only" v-if="searchFields.length > 0">
          <div class="search-inputs">
            <div v-for="field in selectFields" :key="field.key" class="search-field">
              <div class="custom-select" @click="toggleDropdown(field.key)">
                <span class="select-value">{{ getSelectedLabel(field) || field.placeholder }}</span>
                <SvgIcon name="down" class="select-arrow" :class="{ rotated: openDropdown === field.key }" />
                <div v-if="openDropdown === field.key" class="select-options">
                  <div v-for="option in field.options" :key="option.value" class="select-option"
                    :class="{ selected: searchParams[field.key] === option.value }"
                    @click.stop="selectOption(field.key, option.value)">
                    {{ option.label }}
                  </div>
                </div>
              </div>
            </div>
            <div v-for="field in inputFields" :key="field.key" class="search-field">
              <input v-model="searchParams[field.key]" :type="field.type || 'text'" :placeholder="field.placeholder"
                @keyup.enter="handleSearch" />
            </div>
          </div>
          <button @click="handleSearch" class="btn btn-outline btn-sm">筛选</button>
          <button @click="clearSearch" class="btn btn-outline btn-sm">清空</button>
        </div>

        <teleport to="#mobile-filter-container" v-if="isMobile && props.searchFields.length > 0 && teleportReady">
          <div class="mobile-search-bar">
            <div class="mobile-search-inputs">
              <div v-for="field in selectFields" :key="field.key" class="mobile-search-field">
                <label class="field-label">{{ field.label || field.placeholder }}</label>
                <DropdownSelect :model-value="searchParams[field.key] || ''"
                  @change="handleSelectChange(field.key, $event)" :options="field.options"
                  :placeholder="field.placeholder" label-key="label" value-key="value" min-width="100%" />
              </div>
              <div v-for="field in inputFields" :key="field.key" class="mobile-search-field">
                <label class="field-label">{{ field.label || field.placeholder }}</label>
                <input v-model="searchParams[field.key]" :type="field.type || 'text'" :placeholder="field.placeholder"
                  class="mobile-input" @keyup.enter="handleSearch" />
              </div>
            </div>
            <div class="mobile-search-actions">
              <button @click="handleSearch" class="btn btn-primary btn-block">应用筛选</button>
              <button @click="clearSearch" class="btn btn-outline btn-block">清空条件</button>
            </div>
          </div>
        </teleport>

      </div>
      <div class="table-actions">
        <template v-if="!batchMode">
          <button @click="toggleBatchMode" class="btn btn-danger">
            批量删除
          </button>
        </template>
        <template v-else>
          <button @click="batchDelete" class="btn btn-danger" :disabled="selectedItems.length === 0">
            确认删除 ({{ selectedItems.length }})
          </button>
          <button @click="toggleBatchMode" class="btn btn-outline">
            取消
          </button>
        </template>
        <button @click="createItem" class="btn btn-primary">
          新增{{ entityName }}
        </button>
        <button @click="refreshData" class="btn btn-secondary">
          刷新
        </button>
      </div>
    </div>

    <div class="table-container">
      <table class="data-table">
        <thead>
          <tr>
            <th v-if="batchMode" class="checkbox-column">
              <input type="checkbox" @change="toggleSelectAll" :checked="isAllSelected" />
            </th>
            <th v-for="column in columns" :key="column.key">
              <div class="th-content">
                <span>{{ column.label }}</span>
                <div v-if="column.sortable !== false" class="sort-buttons">
                  <button @click="handleSort(column.key, 'asc')"
                    :class="['sort-btn', { active: sortField === column.key && sortOrder === 'asc' }]" title="升序">
                    ▲
                  </button>
                  <button @click="handleSort(column.key, 'desc')"
                    :class="['sort-btn', { active: sortField === column.key && sortOrder === 'desc' }]" title="降序">
                    ▼
                  </button>
                </div>
              </div>
            </th>
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="item in data" :key="item.id">
            <td v-if="batchMode" class="checkbox-column">
              <input type="checkbox" :value="item.id" v-model="selectedItems" />
            </td>
            <td v-for="column in columns" :key="column.key">
              <span v-if="column.type === 'image' && item[column.key]">
                <img :src="item[column.key]" alt="图片" class="table-image" @click="showImageModal(item[column.key])"
                  @error="handleImageError" />
              </span>
              <span v-else-if="column.type === 'image-gallery'">
                <span v-if="loadingGallery === item.id" class="loading-text">
                  加载中...
                </span>
                <span v-else class="content-link" @click="showMediaGallery(item)"
                  :title="item.type === 2 ? '查看视频' : '查看笔记图片'">
                  {{ item.type === 2 ? '视频' : '图片' }}
                </span>
              </span>
              <span v-else-if="column.type === 'date'">
                {{ formatDate(item[column.key]) }}
              </span>
              <span v-else-if="column.type === 'mapped'">
                {{ column.map && column.map[item[column.key]] ? column.map[item[column.key]] : item[column.key] || '-'
                }}
              </span>
              <span v-else-if="column.type === 'status'"
                :class="column.statusMap && column.statusMap[item[column.key]] ? column.statusMap[item[column.key]].class : ''">
                {{ column.statusMap && column.statusMap[item[column.key]] ? column.statusMap[item[column.key]].text :
                  item[column.key] || '-' }}
              </span>
              <span v-else-if="column.type === 'boolean'">
                {{ item[column.key] ? (column.trueText || '是') : (column.falseText || '否') }}
              </span>
              <span v-else-if="column.type === 'array' && Array.isArray(item[column.key])">
                {{ item[column.key].join(', ') }}
              </span>
              <span v-else-if="column.type === 'user-link' && item[column.key]">
                <span class="user-link" @click="openUserProfile(item, column.key)" :title="'查看用户个人主页'">
                  {{ item[column.key] }}
                </span>
              </span>
              <span v-else-if="column.type === 'post-link' && item[column.key]">
                <span class="post-link" @click="openPostDetail(item, column.key)" :title="'查看笔记详情'">
                  {{ item[column.key] }}
                </span>
              </span>
              <span v-else-if="column.type === 'comment-link' && item[column.key]">
                <span class="comment-link" @click="openPostWithCommentId(item, column.key)" :title="'定位到评论位置'">
                  {{ item[column.key] }}
                </span>
              </span>
              <span v-else-if="column.type === 'content' && item[column.key]">
                <span class="content-link" @click="showDetail(item, column)" :title="'查看' + column.label">
                  {{ column.label }}
                </span>
              </span>
              <span v-else-if="column.type === 'tags'">
                <span class="content-link" @click="showTags(item)" :title="'查看笔记标签'">
                  标签 ({{ item[column.key] ? item[column.key].length : 0 }})
                </span>
              </span>
              <span v-else-if="column.type === 'personality-tags'">
                <span class="content-link" @click="showPersonalityTags(item)" :title="'查看个性标签'">
                  个性标签
                </span>
              </span>
              <span v-else-if="column.maxLength && item[column.key] && item[column.key].length > column.maxLength">
                <span class="truncated-content" @click="showDetail(item, column)" :title="'查看' + column.label">
                  {{ item[column.key].substring(0, column.maxLength) }}...
                </span>
              </span>
              <span v-else>
                {{ item[column.key] || '-' }}
              </span>
            </td>
            <td>
              <div class="row-actions">
                <template v-if="customActions.length > 0">
                  <button v-for="action in customActions" :key="action.key"
                    @click="handleCustomAction(action.key, item)" class="row-action-btn"
                    :title="action.title || action.key">
                    {{ action.title || action.key }}
                  </button>
                </template>
                <template v-else>
                  <button @click="editItem(item)" class="row-action-btn">编辑</button>
                  <button @click="deleteItem(item)" class="row-action-btn danger">删除</button>
                </template>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="pagination" v-if="pagination.total > 0">
      <div class="pagination-info">
        共 {{ pagination.total }} 条记录，第 {{ pagination.page }} / {{ pagination.pages }} 页
      </div>
      <div class="pagination-controls">
        <button @click="changePage(pagination.page - 1)" @mouseenter="preloadPage(pagination.page - 1)"
          :disabled="pagination.page <= 1" class="btn btn-sm btn-outline">
          上一页
        </button>
        <span class="page-numbers">
          <button v-for="page in getPageNumbers()" :key="page" @click="changePage(page)" @mouseenter="preloadPage(page)"
            :class="['btn', 'btn-sm', page === pagination.page ? 'btn-primary' : 'btn-outline']">
            {{ page }}
          </button>
        </span>
        <button @click="changePage(pagination.page + 1)" @mouseenter="preloadPage(pagination.page + 1)"
          :disabled="pagination.page >= pagination.pages" class="btn btn-sm btn-outline">
          下一页
        </button>
      </div>
    </div>

    <DetailModal v-model:visible="showDetailModal" :title="detailTitle" :content="detailContent"
      @close="closeDetailModal" />

    <ImageViewer v-model:visible="showImageModalVisible" :images="[currentImage]" :initial-index="0"
      @close="closeImageModal" />

    <ImageViewer v-model:visible="showImageCarouselVisible" :images="currentImages.map(img => img.image_url)"
      :initial-index="0" @close="closeImageCarousel" />

    <VideoPlayerModal v-model:visible="showVideoModalVisible" :video-url="currentVideoUrl"
      :poster-url="currentPosterUrl" @close="closeVideoModal" />

    <TagsModal v-model:visible="showTagsModalVisible" :title="tagsModalTitle" :tags="currentTags"
      @close="closeTagsModal" />

    <PersonalityTagsModal v-model:visible="showPersonalityTagsModalVisible" :user-data="currentUserData"
      @close="closePersonalityTagsModal" />

    <FormModal v-model:visible="showFormModal" :title="`${showCreateModal ? '新增' : '编辑'}${entityName}`"
      :form-fields="formFields" v-model:form-data="formData" :confirm-text="showCreateModal ? '创建' : '更新'"
      :loading="formLoading" @submit="submitForm" @close="closeModals" />

    <div v-if="loading" class="loading-overlay">
      <div class="loading-spinner">
        <div class="spinner-dot"></div>
        <span>加载中...</span>
      </div>
    </div>

    <ConfirmDialog v-model:visible="confirmState.visible" :title="confirmState.title" :message="confirmState.message"
      :type="confirmState.type" :confirm-text="confirmState.confirmText" :cancel-text="confirmState.cancelText"
      :show-cancel="confirmState.showCancel" @confirm="handleConfirm" @cancel="handleCancel" />
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, computed, nextTick, onUnmounted } from 'vue'
import SvgIcon from '@/components/SvgIcon.vue'
import ConfirmDialog from '../../../components/ConfirmDialog.vue'
import DetailModal from './DetailModal.vue'
import FormModal from './FormModal.vue'
import ImageViewer from '@/components/ImageViewer.vue'
import VideoPlayerModal from './VideoPlayerModal.vue'
import TagsModal from './TagsModal.vue'
import PersonalityTagsModal from './PersonalityTagsModal.vue'
import DropdownSelect from '@/components/DropdownSelect.vue'
import apiConfig from '@/config/api.js'
import { useConfirm } from '../composables/useConfirm'
import messageManager from '@/utils/messageManager'

const props = defineProps({
  title: {
    type: String,
    required: true
  },
  entityName: {
    type: String,
    required: true
  },
  apiEndpoint: {
    type: String,
    required: true
  },
  columns: {
    type: Array,
    required: true
  },
  formFields: {
    type: Array,
    required: true
  },
  searchFields: {
    type: Array,
    default: () => []
  },
  defaultSortField: {
    type: String,
    default: ''
  },
  defaultSortOrder: {
    type: String,
    default: ''
  },
  customActions: {
    type: Array,
    default: () => []
  }
})

const isMobile = ref(false)
const teleportReady = ref(false)

function setupMobileWatcher() {
  if (typeof window === 'undefined' || !window.matchMedia) return
  const mql = window.matchMedia('(max-width: 960px)')
  const update = () => { isMobile.value = mql.matches }
  update()
  if (mql.addEventListener) {
    mql.addEventListener('change', update)
  } else if (mql.addListener) {
    mql.addListener(update)
  }
}

function checkTeleportTarget() {
  const target = document.getElementById('mobile-filter-container')
  teleportReady.value = !!target
  if (!target) {
    setTimeout(checkTeleportTarget, 100)
  }
}

function setupTeleportWatcher() {
  if (typeof window === 'undefined' || !window.MutationObserver) return

  const observer = new MutationObserver(() => {
    const target = document.getElementById('mobile-filter-container')
    teleportReady.value = !!target
  })

  observer.observe(document.body, {
    childList: true,
    subtree: true
  })

  return observer
}

const { confirmState, handleConfirm, handleCancel, confirmDelete, showError } = useConfirm()

const defaultAvatar = new URL('@/assets/imgs/瓜呱.png', import.meta.url).href

const getAuthHeaders = () => {
  const headers = {
    'Content-Type': 'application/json'
  }

  const adminToken = localStorage.getItem('admin_token')
  if (adminToken) {
    headers.Authorization = `Bearer ${adminToken}`
  }

  return headers
}

const data = ref([])
const loading = ref(false)
const showCreateModal = ref(false)
const showEditModal = ref(false)
const showDetailModal = ref(false)
const detailTitle = ref('')
const detailContent = ref('')
const showImageModalVisible = ref(false)
const currentImage = ref('')
const showImageCarouselVisible = ref(false)
const currentImages = ref([])
const loadingGallery = ref(null)
const showTagsModalVisible = ref(false)
const currentTags = ref([])
const tagsModalTitle = ref('')
const showPersonalityTagsModalVisible = ref(false)
const currentUserData = ref({})
const showVideoModalVisible = ref(false)
const currentVideoUrl = ref('')
const currentPosterUrl = ref('')
const formData = ref({})
const editingItem = ref(null)
const formLoading = ref(false)
const searchParams = reactive({})
const sortField = ref(props.defaultSortField)
const sortOrder = ref(props.defaultSortOrder)
const openDropdown = ref(null)

const selectFields = computed(() => {
  return props.searchFields.filter(field => field.type === 'select')
})

const inputFields = computed(() => {
  return props.searchFields.filter(field => field.type !== 'select')
})

const batchMode = ref(false)
const selectedItems = ref([])

const showFormModal = computed({
  get: () => showCreateModal.value || showEditModal.value,
  set: (value) => {
    if (!value) {
      showCreateModal.value = false
      showEditModal.value = false
    }
  }
})

const pagination = reactive({
  page: 1,
  limit: 20,
  total: 0,
  pages: 0
})

const pageCache = ref(new Map())
const preloadingPages = ref(new Set())

props.searchFields.forEach(field => {
  searchParams[field.key] = ''
})

const resetFormData = () => {
  const newFormData = {}

  if (props.apiEndpoint === '/admin/posts') {
    newFormData.image_urls = []
    newFormData.images = []
    newFormData.tags = []
  }

  formData.value = newFormData
}

const handleClickOutside = (event) => {
  if (!event.target.closest('.custom-select')) {
    openDropdown.value = null
  }
}

let teleportObserver = null

onMounted(() => {
  setupMobileWatcher()
  checkTeleportTarget()
  teleportObserver = setupTeleportWatcher()
  loadData()
  document.addEventListener('click', handleClickOutside)
})

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside)
  if (teleportObserver) {
    teleportObserver.disconnect()
  }
})

const loadData = async (targetPage = null, useCache = true) => {
  const pageToLoad = targetPage || pagination.page

  const cacheKey = generateCacheKey(pageToLoad)

  if (useCache && pageCache.value.has(cacheKey)) {
    const cachedData = pageCache.value.get(cacheKey)
    if (!targetPage) {
      data.value = cachedData.data
      Object.assign(pagination, cachedData.pagination)
    }
    return cachedData
  }

  if (!targetPage) {
    loading.value = true
  }

  try {
    const params = new URLSearchParams({
      page: pageToLoad,
      limit: pagination.limit,
      ...searchParams
    })

    if (sortField.value && sortOrder.value) {
      params.append('sortField', sortField.value)
      params.append('sortOrder', sortOrder.value)
    }

    const response = await fetch(`${apiConfig.baseURL}${props.apiEndpoint}?${params}`, {
      headers: getAuthHeaders()
    })
    const result = await response.json()

    if (result.code === 200) {
      const responseData = {
        data: result.data.data || result.data,
        pagination: result.data.pagination || {
          page: result.data.page || pageToLoad,
          limit: result.data.limit || pagination.limit,
          total: result.data.total || 0,
          pages: result.data.totalPages || Math.ceil((result.data.total || 0) / (result.data.limit || pagination.limit))
        }
      }

      pageCache.value.set(cacheKey, responseData)

      if (!targetPage) {
        data.value = responseData.data
        Object.assign(pagination, responseData.pagination)
      }

      return responseData
    } else {
      console.error('加载数据失败:', result.message)
    }
  } catch (error) {
    console.error('加载数据失败:', error)
  } finally {
    if (!targetPage) {
      loading.value = false
    }
  }
}

const generateCacheKey = (page) => {
  const searchKey = Object.entries(searchParams)
    .filter(([key, value]) => value !== '')
    .map(([key, value]) => `${key}:${value}`)
    .join('|')
  const sortKey = sortField.value && sortOrder.value ? `${sortField.value}:${sortOrder.value}` : ''
  return `${page}-${searchKey}-${sortKey}`
}

const preloadPage = async (page) => {
  if (typeof page !== 'number' || page < 1 || page > pagination.pages || page === pagination.page) {
    return
  }

  if (preloadingPages.value.has(page)) {
    return
  }

  const cacheKey = generateCacheKey(page)

  if (pageCache.value.has(cacheKey)) {
    return
  }

  preloadingPages.value.add(page)

  try {
    await loadData(page, false)
  } catch (error) {
    console.error(`预加载第 ${page} 页失败:`, error)
  } finally {
    preloadingPages.value.delete(page)
  }
}

const clearCache = () => {
  pageCache.value.clear()
  preloadingPages.value.clear()
}

const refreshData = () => {
  clearCache()
  pagination.page = 1
  loadData()
}

const emit = defineEmits(['close-filter', 'custom-action'])

const handleSearch = () => {
  clearCache()
  pagination.page = 1
  loadData()
  if (isMobile.value) {
    emit('close-filter')
  }
}

const clearSearch = () => {
  props.searchFields.forEach(field => {
    searchParams[field.key] = ''
  })
  openDropdown.value = null
  clearCache()
  pagination.page = 1
  loadData()
  if (isMobile.value) {
    emit('close-filter')
  }
}

const toggleDropdown = (fieldKey) => {
  openDropdown.value = openDropdown.value === fieldKey ? null : fieldKey
}

const selectOption = (fieldKey, value) => {
  searchParams[fieldKey] = value
  openDropdown.value = null
  handleSearch()
}

const getSelectedLabel = (field) => {
  const selectedValue = searchParams[field.key]
  if (!selectedValue) return ''
  const option = field.options.find(opt => opt.value === selectedValue)
  return option ? option.label : ''
}

const changePage = (page) => {
  if (page >= 1 && page <= pagination.pages) {
    pagination.page = page
    loadData()
  }
}

const getPageNumbers = () => {
  const pages = []
  const current = pagination.page
  const total = pagination.pages

  if (total <= 7) {
    for (let i = 1; i <= total; i++) {
      pages.push(i)
    }
  } else {
    if (current <= 4) {
      for (let i = 1; i <= 5; i++) {
        pages.push(i)
      }
      pages.push('...')
      pages.push(total)
    } else if (current >= total - 3) {
      pages.push(1)
      pages.push('...')
      for (let i = total - 4; i <= total; i++) {
        pages.push(i)
      }
    } else {
      pages.push(1)
      pages.push('...')
      for (let i = current - 1; i <= current + 1; i++) {
        pages.push(i)
      }
      pages.push('...')
      pages.push(total)
    }
  }

  return pages.filter(page => page !== '...' || pages.indexOf(page) === pages.lastIndexOf(page))
}

const createItem = () => {
  editingItem.value = null

  resetFormData()

  showCreateModal.value = true
}

const editItem = async (item) => {
  editingItem.value = item

  if (props.apiEndpoint === '/admin/posts') {
    try {
      const response = await fetch(`${apiConfig.baseURL}${props.apiEndpoint}/${item.id}`, {
        headers: getAuthHeaders()
      })
      const result = await response.json()

      if (result.code === 200) {
        const fullItem = result.data
        const newFormData = {}

        Object.keys(fullItem).forEach(key => {
          if (key === 'tags') {
            if (Array.isArray(fullItem[key])) {
              newFormData[key] = fullItem[key].map(tag =>
                typeof tag === 'object' ? tag.name : tag
              )
            } else {
              newFormData[key] = []
            }
          } else if (key === 'images') {
            if (fullItem.type === 2) {
              const videoUrl = Array.isArray(fullItem[key]) && fullItem[key].length > 0 ? fullItem[key][0] : ''
              newFormData['video_url'] = videoUrl
              newFormData['cover_url'] = fullItem.cover_url || ''

              if (videoUrl) {
                newFormData['video_upload'] = {
                  url: videoUrl,
                  coverUrl: fullItem.cover_url,
                  name: '已上传的视频',
                  size: 0,
                  uploaded: true,
                  preview: videoUrl
                }
              } else {
                newFormData['video_upload'] = null
              }
              newFormData[key] = []  
            } else {
              newFormData[key] = Array.isArray(fullItem[key]) ? fullItem[key] : []
            }
          } else {
            newFormData[key] = fullItem[key]
          }
        })

        formData.value = newFormData
      } else {
        console.error('获取笔记详情失败:', result.message)
        const newFormData = {}
        Object.keys(item).forEach(key => {
          if (key === 'tags') {
            if (Array.isArray(item[key])) {
              newFormData[key] = item[key].map(tag =>
                typeof tag === 'object' ? tag.name : tag
              )
            } else {
              newFormData[key] = []
            }
          } else if (key === 'images') {
            if (item.type === 2) {
              const videoUrl = Array.isArray(item[key]) && item[key].length > 0 ? item[key][0] : ''
              newFormData['video_url'] = videoUrl
              newFormData['cover_url'] = item.cover_url || ''
              newFormData['video_upload'] = videoUrl
              newFormData[key] = []  
            } else {
              newFormData[key] = Array.isArray(item[key]) ? item[key] : []
            }
          } else {
            newFormData[key] = item[key]
          }
        })
        formData.value = newFormData
      }
    } catch (error) {
      console.error('获取笔记详情失败:', error)
      const newFormData = {}
      Object.keys(item).forEach(key => {
        if (key === 'tags') {
          if (Array.isArray(item[key])) {
            newFormData[key] = item[key].map(tag =>
              typeof tag === 'object' ? tag.name : tag
            )
          } else {
            newFormData[key] = []
          }
        } else if (key === 'images') {
          if (item.type === 2) {
            const videoUrl = Array.isArray(item[key]) && item[key].length > 0 ? item[key][0] : ''
            newFormData['video_url'] = videoUrl
            newFormData['cover_url'] = item.cover_url || ''

            if (videoUrl) {
              newFormData['video_upload'] = {
                url: videoUrl,
                coverUrl: item.cover_url,
                name: '已上传的视频',
                size: 0,
                uploaded: true,
                preview: videoUrl
              }
            } else {
              newFormData['video_upload'] = null
            }
            newFormData[key] = []  
          } else {
            newFormData[key] = Array.isArray(item[key]) ? item[key] : []
          }
        } else {
          newFormData[key] = item[key]
        }
      })
      formData.value = newFormData
    }
  } else {
    const newFormData = {}
    Object.keys(item).forEach(key => {
      if (key === 'tags') {
        if (Array.isArray(item[key])) {
          newFormData[key] = item[key].map(tag =>
            typeof tag === 'object' ? tag.name : tag
          )
        } else {
          newFormData[key] = []
        }
      } else if (key === 'interests') {
        if (typeof item[key] === 'string') {
          try {
            newFormData[key] = JSON.parse(item[key])
          } catch {
            newFormData[key] = item[key] ? item[key].split(',').map(s => s.trim()).filter(s => s) : []
          }
        } else {
          newFormData[key] = Array.isArray(item[key]) ? item[key] : []
        }
      } else if (key === 'images') {
        const images = Array.isArray(item[key]) ? item[key] : []
        newFormData['image_urls'] = images
      } else {
        newFormData[key] = item[key]
      }
    })
    formData.value = newFormData
  }

  showEditModal.value = true
}

const deleteItem = async (item) => {
  try {
    await confirmDelete(props.entityName)
    try {
      const response = await fetch(`${apiConfig.baseURL}${props.apiEndpoint}/${item.id}`, {
        method: 'DELETE',
        headers: getAuthHeaders()
      })

      const result = await response.json()
      if (result.code === 200) {
        clearCache()
        loadData(null, false)
      } else {
        const errorMessage = result.message || '删除失败，请稍后重试'
        await showError(errorMessage)
      }
    } catch (error) {
      console.error('删除失败:', error)
      if (error !== false) {
        const errorMessage = error?.message || '删除失败，请稍后重试'
        await showError(errorMessage)
      }
    }
  } catch (error) {
  }
}

const submitForm = async (data) => {
  formLoading.value = true
  try {

    const url = showCreateModal.value
      ? `${apiConfig.baseURL}${props.apiEndpoint}`
      : `${apiConfig.baseURL}${props.apiEndpoint}/${editingItem.value.id}`

    const method = showCreateModal.value ? 'POST' : 'PUT'

    const response = await fetch(url, {
      method,
      headers: getAuthHeaders(),
      body: JSON.stringify(data)
    })

    const result = await response.json()

    if (result.code === 200) {
      const action = showCreateModal.value ? '创建' : '更新'
      messageManager.success(`${props.entityName}${action}成功`)
      closeModals()
      clearCache()
      loadData(null, false)
    } else {
      const errorMessage = result.message || '操作失败，请稍后重试'
      await showError(errorMessage)
    }
  } catch (error) {
    console.error('操作失败:', error)
    if (error !== false) {
      const errorMessage = error?.message || '操作失败，请稍后重试'
      await showError(errorMessage)
    }
  } finally {
    formLoading.value = false
  }
}

const updateFormData = (newData) => {
  if (newData && typeof newData === 'object') {
    formData.value = { ...newData }
  } else {
    formData.value = {}
  }
}

const closeModals = () => {
  showCreateModal.value = false
  showEditModal.value = false
  editingItem.value = null

  resetFormData()
}

const showDetail = (item, column) => {
  detailTitle.value = `查看${column.label} - ${props.entityName} ID: ${item.id}`
  detailContent.value = item[column.key] || ''
  showDetailModal.value = true
}

const closeDetailModal = () => {
  showDetailModal.value = false
  detailTitle.value = ''
  detailContent.value = ''
}

const showImageModal = (imageUrl) => {
  currentImage.value = imageUrl
  showImageModalVisible.value = true
}

const closeImageModal = () => {
  showImageModalVisible.value = false
  currentImage.value = ''
}

const showImageGallery = async (postId) => {
  loadingGallery.value = postId
  try {
    const response = await fetch(`${apiConfig.baseURL}/posts/${postId}`, {
      headers: getAuthHeaders()
    })
    const result = await response.json()

    if (result.code === 200) {
      const images = result.data.images.map((imageUrl, index) => ({
        id: index + 1,
        image_url: imageUrl
      }))
      currentImages.value = images
      showImageCarouselVisible.value = true
      } else {
        console.error('获取笔记图片失败:', result.message)
        const errorMessage = result.message || '获取笔记图片失败'
        await showError(errorMessage)
      }
    } catch (error) {
      console.error('获取笔记图片失败:', error)
      if (error !== false) {
        const errorMessage = error?.message || '获取笔记图片失败'
        await showError(errorMessage)
      }
    } finally {
      loadingGallery.value = null
    }
}

const closeImageCarousel = () => {
  showImageCarouselVisible.value = false
  currentImages.value = []
}

const showMediaGallery = async (item) => {
  if (item.type === 2) {
    loadingGallery.value = item.id
    try {
      const response = await fetch(`${apiConfig.baseURL}/posts/${item.id}`, {
        headers: getAuthHeaders()
      })
      const result = await response.json()

      if (result.code === 200) {
        currentVideoUrl.value = result.data.video_url || ''
        currentPosterUrl.value = result.data.images && result.data.images[0] ? result.data.images[0] : ''
        showVideoModalVisible.value = true
      } else {
        console.error('获取视频信息失败:', result.message)
        const errorMessage = result.message || '获取视频信息失败'
        await showError(errorMessage)
      }
    } catch (error) {
      console.error('获取视频信息失败:', error)
      if (error !== false) {
        const errorMessage = error?.message || '获取视频信息失败'
        await showError(errorMessage)
      }
    } finally {
      loadingGallery.value = null
    }
  } else {
    showImageGallery(item.id)
  }
}

const closeVideoModal = () => {
  showVideoModalVisible.value = false
  currentVideoUrl.value = ''
  currentPosterUrl.value = ''
}

const showTags = (item) => {
  currentTags.value = item.tags || []
  tagsModalTitle.value = `笔记标签 - ${item.title || 'ID: ' + item.id}`
  showTagsModalVisible.value = true
}

const closeTagsModal = () => {
  showTagsModalVisible.value = false
  currentTags.value = []
  tagsModalTitle.value = ''
}

const showPersonalityTags = async (item) => {
  try {
    const response = await fetch(`${apiConfig.baseURL}/users/${item.user_id}/personality-tags`, {
      headers: getAuthHeaders()
    })

    if (response.ok) {
      const result = await response.json()
      if (result.code === 200) {
        currentUserData.value = {
          ...item,
          personalityTags: result.data
        }
      } else {
        console.error('获取个性标签失败:', result.message)
        currentUserData.value = {
          ...item,
          personalityTags: null
        }
      }
    } else {
      console.error('API请求失败:', response.status)
      currentUserData.value = {
        ...item,
        personalityTags: null
      }
    }
  } catch (error) {
    console.error('获取个性标签出错:', error)
    currentUserData.value = {
      ...item,
      personalityTags: null
    }
  }

  showPersonalityTagsModalVisible.value = true
}

const closePersonalityTagsModal = () => {
  showPersonalityTagsModalVisible.value = false
  currentUserData.value = {}
}

const formatDate = (dateString) => {
  if (!dateString) return '-'
  return new Date(dateString).toLocaleString('zh-CN')
}

const openUserProfile = async (item, fieldKey) => {
  try {
    let userDisplayId = null

    if (fieldKey) {
      userDisplayId = item[fieldKey]
    } else {
      if (props.apiEndpoint === '/admin/users') {
        userDisplayId = item.user_id
      } else {
        userDisplayId = item.user_display_id || item.sender_display_id
      }
    }

    if (userDisplayId) {
      const userProfileUrl = `${window.location.origin}/user/${userDisplayId}`
      window.open(userProfileUrl, '_blank')
    } else {
      console.error('无法获取用户的瓜呱号，字段:', fieldKey, '数据:', item)
    }
  } catch (error) {
    console.error('获取用户信息失败:', error)
  }
}

const openPostDetail = async (item) => {
  window.open(`${window.location.origin}/post?id=${item.id}`, '_blank')
}
const openPostWithCommentId = (item) => {
  console.log(item)
  window.open(`${window.location.origin}/post?id=${item.post_id}&targetCommentId=${item.id}`, '_blank')
}
const handleSort = (field, order) => {
  clearCache()
  sortField.value = field
  sortOrder.value = order
  pagination.page = 1
  loadData()
}

const getSelectedOptionLabel = (field, value) => {
  if (!field.options || !value) return ''
  const option = field.options.find(opt => opt.value === value)
  return option ? option.label : value
}

const handleSelectChange = (field, eventData) => {
  searchParams[field] = eventData.value
}

const toggleBatchMode = () => {
  batchMode.value = !batchMode.value
  if (!batchMode.value) {
    selectedItems.value = []
  }
}

const isAllSelected = computed(() => {
  return data.value.length > 0 && selectedItems.value.length === data.value.length
})

const toggleSelectAll = () => {
  if (isAllSelected.value) {
    selectedItems.value = []
  } else {
    selectedItems.value = data.value.map(item => item.id)
  }
}

const batchDelete = async () => {
  if (selectedItems.value.length === 0) {
    showError('请选择要删除的项目')
    return
  }

  try {
    await confirmDelete(props.entityName, selectedItems.value.length)
    try {
      const response = await fetch(`${apiConfig.baseURL}${props.apiEndpoint}`, {
        method: 'DELETE',
        headers: getAuthHeaders(),
        body: JSON.stringify({
          ids: selectedItems.value
        })
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const result = await response.json()
      if (result.code === 200) {
        selectedItems.value = []
        batchMode.value = false
        clearCache()
        loadData(null, false)
      } else {
        throw new Error(result.message || '删除失败')
      }
    } catch (error) {
      console.error('批量删除失败:', error)
      if (error !== false) {
        const errorMessage = error?.message || '批量删除失败，请稍后重试'
        await showError(errorMessage)
      }
    }
  } catch (error) {
  }
}

const handleImageError = (event) => {
  event.target.src = defaultAvatar
}

const handleCustomAction = (action, item) => {
  emit('custom-action', { action, item })
}
</script>

<style scoped>
.crud-table {
  background: var(--bg-color-primary);
  border-radius: 0;
  margin: 0;
  height: 100%;
  display: flex;
  flex-direction: column;
  min-height: 0;
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
  display: flex;
  flex-direction: column;
  gap: 0;
  flex: 1;
}

.table-actions {
  display: flex;
  gap: 10px;
  flex-shrink: 0;
}

.search-bar {
  display: flex;
  align-items: flex-end;
  gap: 15px;
  flex-wrap: wrap;
}

.search-actions {
  display: flex;
  gap: 8px;
  align-items: flex-end;
}

.search-actions .btn {
  height: 32px;
  padding: 0 12px;
  font-size: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  min-width: 60px;
}

.search-inputs {
  display: flex;
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
  min-width: 120px;
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
  min-width: 120px;
  height: 34px;
  cursor: pointer;
  justify-content: center;
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
  max-height: 200px;
  overflow-y: auto;
  margin-top: 2px;
  transition: background-color 0.3s ease, border-color 0.3s ease;
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
  word-wrap: break-word;
  word-break: break-all;
  vertical-align: top;
  white-space: normal;
  transition: border-bottom 0.3s ease;
}

.data-table th {
  background-color: var(--bg-color-secondary);
  font-weight: 600;
  color: var(--text-color-primary);
  width: auto;
  border-bottom: 1px solid transparent;
  transition: background-color 0.3s ease;
}

.data-table tr {
  transition: background-color 0.3s ease;
}

.data-table tr:hover {
  background-color: var(--bg-color-secondary);
}

.checkbox-column {
  width: 50px !important;
  text-align: center;
  padding: 12px 8px !important;
}

.data-table th:last-child,
.data-table td:last-child {
  width: 50px;
  text-align: center;
  white-space: nowrap;
}

.checkbox-column input[type="checkbox"] {
  cursor: pointer;
  transform: scale(1.2);
}

.checkbox-column input[type="checkbox"]:checked {
  accent-color: var(--primary-color);
}

.table-image {
  width: 40px;
  height: 40px;
  object-fit: cover;
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.3s ease;
}

.table-image:hover {
  transform: scale(1.1);
}

.pagination {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 8px 30px;
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

.pagination-controls button,
.page-numbers button {
  user-select: none;
  transition: all 0.3s ease;
}

.pagination-controls button:hover:not(:disabled),
.page-numbers button:hover:not(:disabled) {
  background-color: var(--primary-color);
  color: var(--text-color-inverse);
}

.page-numbers button.btn-primary:hover:not(:disabled) {
  background-color: var(--primary-color);
  opacity: 0.9;
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
  transition: background-color 0.3s ease;
}

.loading-spinner {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  color: var(--text-color-secondary);
  font-size: 13px;
}

.spinner-dot {
  width: 28px;
  height: 28px;
  border: 3px solid var(--border-color-primary);
  border-top-color: var(--primary-color);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
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
  transition: border-color 0.3s ease;
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

.row-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}

.row-action-btn {
  background: none;
  border: none;
  padding: 4px 8px;
  font-size: 13px;
  font-weight: 600;
  color: var(--primary-color);
  cursor: pointer;
  border-radius: 4px;
  transition: background 0.2s ease, color 0.2s ease;
}

.row-action-btn:hover {
  background: var(--nav-active-bg, rgba(220, 18, 87, 0.08));
}

.row-action-btn.danger {
  color: var(--series-negative);
}

.row-action-btn.danger:hover {
  background: rgba(239, 68, 68, 0.1);
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

.action-icon:hover:not(:disabled) {
  background-color: var(--bg-color-secondary);
  color: var(--primary-color);
}

.truncated-content,
.content-link,
.user-link,
.post-link,
.comment-link {
  color: var(--text-color-secondary);
  cursor: pointer;
  text-decoration: underline;
  transition: color 0.2s;
  display: inline-block;
  max-width: 80px;
  word-wrap: break-word;
  word-break: break-all;
  line-height: 1.4;
}

.truncated-content:hover,
.content-link:hover,
.user-link:hover {
  color: var(--primary-color);
}

.th-content {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  white-space: nowrap;
}

.sort-buttons {
  display: flex;
  flex-direction: column;
  gap: 1px;
  flex-shrink: 0;
}

.sort-btn {
  background: none;
  border: none;
  cursor: pointer;
  padding: 2px 4px;
  color: var(--text-color-secondary);
  transition: color 0.2s;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 10px;
  line-height: 1;
  border-radius: 2px;
  width: 16px;
  height: 12px;
}

.sort-btn:hover {
  background-color: var(--bg-color-tertiary);
}

.sort-btn.active {
  color: var(--primary-color);
  background-color: var(--primary-color-shadow);
  opacity: 0.8;
  transition: background-color 0.3s ease;
}

.mobile-search-bar {
  padding: 20px;
  background: var(--bg-color-primary);
  border-radius: 8px;
  margin: 0;
}

.mobile-search-inputs {
  display: flex;
  flex-direction: column;
  gap: 20px;
  margin-bottom: 20px;
}

.mobile-search-field {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.field-label {
  display: block;
  margin-bottom: 5px;
  font-weight: 500;
  color: var(--text-color-primary);
  font-size: 14px;
}

.mobile-input {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid var(--border-color-primary);
  border-radius: 4px;
  font-size: 14px;
  box-sizing: border-box;
  background-color: var(--bg-color-primary);
  color: var(--text-color-primary);
  caret-color: var(--primary-color);
  transition: border-color 0.2s;
}

.mobile-input:focus {
  border-color: var(--primary-color);
  outline: none;
}

.mobile-search-actions {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin: 0;
}

.btn-block {
  width: 100%;
  justify-content: center;
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

.btn-block:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-block.btn-primary {
  background-color: var(--primary-color);
  color: white;
}

.btn-block.btn-primary:hover:not(:disabled) {
  background-color: var(--primary-color-dark);
}

.btn-block.btn-outline {
  background-color: transparent;
  color: var(--text-color-secondary);
  border: 1px solid var(--border-color-primary);
}

.btn-block.btn-outline:hover:not(:disabled) {
  background-color: var(--bg-color-secondary);
  border-color: var(--primary-color);
  color: var(--primary-color);
}

.mobile-search-field .custom-select {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid var(--border-color-primary);
  border-radius: 4px;
  background-color: var(--bg-color-primary);
  cursor: pointer;
  transition: border-color 0.2s;
  box-sizing: border-box;
  position: relative;
}

.mobile-search-field .custom-select:hover {
  border-color: var(--primary-color);
}

.mobile-search-field .custom-select:focus {
  border-color: var(--primary-color);
  outline: none;
}

.mobile-search-field .select-options {
  position: absolute;
  top: calc(100% + 2px);
  left: 0;
  right: 0;
  max-height: 200px;
  overflow-y: auto;
  border: 1px solid var(--border-color-primary);
  border-radius: 4px;
  background: var(--bg-color-primary);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  z-index: 1000;
}

.mobile-search-field .select-option {
  padding: 10px 12px;
  cursor: pointer;
  transition: background-color 0.2s;
  color: var(--text-color-primary);
  font-size: 14px;
}

.mobile-search-field .select-option:hover {
  background-color: var(--bg-color-secondary);
}

.mobile-search-field .select-option.selected {
  background-color: var(--primary-color);
  color: white;
}

.mobile-search-field .select-value {
  color: var(--text-color-primary);
  font-size: 14px;
}

.mobile-search-field .select-arrow {
  position: absolute;
  right: 12px;
  top: 50%;
  transform: translateY(-50%);
  transition: transform 0.2s;
  color: var(--text-color-secondary);
  width: 12px;
  height: 12px;
}

.mobile-search-field .select-arrow.rotated {
  transform: translateY(-50%) rotate(180deg);
}

@media (max-width: 960px) {
  .desktop-only {
    display: none;
  }

  .table-header {
    justify-content: center;
  }

  .header-left {
    display: none;
  }

  .table-actions {
    justify-content: center;
    flex-wrap: wrap;
  }
}
</style>