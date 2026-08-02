<template>
  <div class="draft-box-container">

    <div class="page-header">
      <div class="header-left">
        <button class="back-btn" @click="handleBack">
          <SvgIcon name="left" width="20" height="20" />
        </button>
        <h1 class="page-title">草稿箱</h1>
      </div>
      <div class="header-right">
        <span class="post-count">共 {{ totalDrafts }} 篇草稿</span>
      </div>
    </div>

    <div class="filter-section">
      <div class="search-box">
        <SvgIcon name="search" width="16" height="16" class="search-icon" />
        <input v-model="searchKeyword" type="text" placeholder="搜索草稿标题或内容" @input="handleSearch" />
      </div>
      <div class="filter-options">
        <DropdownSelect v-model="selectedCategory" :options="categoryOptions" placeholder="全部分类" label-key="label"
          value-key="value" min-width="120px" max-width="150px" @change="handleCategoryChange" />
      </div>
    </div>

    <div class="drafts-section">
      <div v-if="loading" class="loading-state">
        <div class="loading-spinner"></div>
        <p>加载中...</p>
      </div>

      <div v-else-if="drafts.length === 0" class="empty-state">
        <SvgIcon name="empty" width="80" height="80" class="empty-icon" />
        <p>暂无草稿</p>
        <button class="create-btn" @click="goToPublish">
          <SvgIcon name="publish" width="16" height="16" />
          创建第一篇草稿
        </button>
      </div>

      <div v-else class="posts-list">
        <PostItem 
          v-for="draft in drafts" 
          :key="draft.id" 
          :post="draft" 
          @edit="editDraft" 
          @delete="confirmDelete"
          @view="handleViewDraft"
        />
      </div>

      <div v-if="totalPages > 1" class="pagination">
        <button class="page-btn" :disabled="currentPage === 1" @click="changePage(currentPage - 1)">
          <SvgIcon name="left" width="16" height="16" />
        </button>
        <span class="page-info">{{ currentPage }} / {{ totalPages }}</span>
        <button class="page-btn" :disabled="currentPage === totalPages" @click="changePage(currentPage + 1)">
          <SvgIcon name="right" width="16" height="16" />
        </button>
      </div>
    </div>

    <ConfirmModal :visible="showDeleteModal" title="确认删除" message="确定要删除这篇草稿吗？删除后无法恢复。" type="warning" confirm-text="删除"
      cancel-text="取消" @confirm="handleDelete" @cancel="showDeleteModal = false"
      @update:visible="showDeleteModal = $event" />

    <DetailCard
      v-if="showDetailCard"
      :item="selectedDetailDraft"
      :click-position="clickPosition"
      @close="closeDetailCard"
    />

    <MessageToast v-if="showToast" :message="toastMessage" :type="toastType" @close="handleToastClose" />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { getDraftPosts, deletePost, updatePost } from '@/api/posts'
import { getCategories } from '@/api/categories'

import SvgIcon from '@/components/SvgIcon.vue'
import DropdownSelect from '@/components/DropdownSelect.vue'
import MessageToast from '@/components/MessageToast.vue'
import ConfirmModal from '@/components/ConfirmDialog.vue'
import PostItem from '@/components/PostItem.vue'
import DetailCard from '@/components/DetailCard.vue'

const router = useRouter()
const userStore = useUserStore()

const drafts = ref([])
const loading = ref(false)
const currentPage = ref(1)
const totalPages = ref(1)
const totalDrafts = ref(0)
const searchKeyword = ref('')
const selectedCategory = ref('')
const categories = ref([])

const showDeleteModal = ref(false)
const selectedDraft = ref(null)

const showDetailCard = ref(false)
const selectedDetailDraft = ref(null)
const clickPosition = ref({ x: 0, y: 0 })

const showToast = ref(false)
const toastMessage = ref('')
const toastType = ref('success')

const categoryOptions = computed(() => {
  return [
    { value: '', label: '全部分类' },
    ...categories.value.map(category => ({
      value: category.id,
      label: category.name
    }))
  ]
})

const showMessage = (message, type = 'success') => {
  toastMessage.value = message
  toastType.value = type
  showToast.value = true
}

const handleToastClose = () => {
  showToast.value = false
}

const handleBack = () => {
  router.push('/publish')
}

const goToPublish = () => {
  router.push('/publish')
}

const getCategoryName = (categoryId) => {
  if (!categoryId) return ''
  const categoryObj = categories.value.find(cat => cat.id === categoryId)
  return categoryObj ? categoryObj.name : ''
}

const loadDrafts = async () => {
  try {
    loading.value = true

    if (!userStore.userInfo || !userStore.userInfo.user_id) {
      showMessage('请先登录', 'error')
      router.push('/user')
      return
    }

    const params = {
      page: currentPage.value,
      limit: 10,
      keyword: searchKeyword.value,
      category_id: selectedCategory.value,
      sort: 'created_at',
      user_id: userStore.userInfo.user_id
    }

    const response = await getDraftPosts(params)
    if (response.success) {
      drafts.value = response.data.posts
      totalPages.value = response.data.pagination.pages
      totalDrafts.value = response.data.pagination.total
    } else {
      showMessage(response.message || '加载失败', 'error')
    }
  } catch (error) {
    console.error('加载草稿失败:', error)
    showMessage('加载草稿失败', 'error')
  } finally {
    loading.value = false
  }
}

const handleSearch = () => {
  currentPage.value = 1
  loadDrafts()
}

const handleCategoryChange = (event) => {
  selectedCategory.value = event.value
  currentPage.value = 1
  loadDrafts()
}

const changePage = (page) => {
  currentPage.value = page
  loadDrafts()
}

const editDraft = (draft) => {
  router.push({
    path: '/publish',
    query: {
      draftId: draft.id,
      mode: 'edit'
    }
  })
}

const confirmDelete = (draft) => {
  selectedDraft.value = draft
  showDeleteModal.value = true
}

const handleDelete = async () => {
  try {
    const response = await deletePost(selectedDraft.value.id)
    if (response.success) {
      showMessage('删除成功', 'success')
      loadDrafts() 
    } else {
      showMessage(response.message || '删除失败', 'error')
    }
  } catch (error) {
    console.error('删除失败:', error)
    showMessage('删除失败，请重试', 'error')
  }
}

const handleViewDraft = (draft, event) => {
  clickPosition.value = {
    x: event.clientX,
    y: event.clientY
  }
  selectedDetailDraft.value = JSON.parse(JSON.stringify(draft))
  showDetailCard.value = true

  const originalTitle = document.title
  document.title = draft.title || '草稿详情'

  const newUrl = `/post?id=${draft.id}`
  window.history.pushState(
    {
      previousUrl: window.location.pathname + window.location.search,
      showDetailCard: true,
      postId: draft.id,
      originalTitle: originalTitle
    },
    draft.title || '草稿详情',
    newUrl
  )
}

const closeDetailCard = () => {
  showDetailCard.value = false
  selectedDetailDraft.value = null

  if (window.history.state && window.history.state.originalTitle) {
    document.title = window.history.state.originalTitle
  }

  if (window.history.state && window.history.state.previousUrl) {
    window.history.replaceState(window.history.state, '', window.history.state.previousUrl)
  } else {
    window.history.back()
  }
}

const loadCategories = async () => {
  try {
    const response = await getCategories()
    if (response.success && response.data) {
      categories.value = response.data
    }
  } catch (error) {
    console.error('加载分类失败:', error)
  }
}

onMounted(() => {
  userStore.initUserInfo()
  loadCategories()
  loadDrafts()
})
</script>

<style scoped>
* {
  transition: background 0.2s ease, border-color 0.2s ease;
}

.draft-box-container {
  min-height: 100vh;
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
  padding-bottom: calc(48px + constant(safe-area-inset-bottom));
  padding-bottom: calc(48px + env(safe-area-inset-bottom));
  margin: 72px auto;
  width: 100%;
  max-width: 700px;
}

@media (min-width: 961px) {
  .draft-box-container {
    max-width: 1000px;
  }
}

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1rem;
  background: var(--bg-color-primary);
  border-bottom: 1px solid var(--border-color-primary);
  position: sticky;
  top: 0;
  z-index: 100;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.header-right {
  display: flex;
  align-items: center;
}

.back-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  border: none;
  background: transparent;
  color: var(--text-color-primary);
  border-radius: 50%;
  cursor: pointer;
}

.back-btn:hover {
  background: var(--bg-color-secondary);
}

.page-title {
  font-size: 1.2rem;
  font-weight: 600;
  margin: 0;
  color: var(--text-color-primary);
}

.post-count {
  font-size: 0.9rem;
  color: var(--text-color-secondary);
}

.filter-section {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1rem;
  background: var(--bg-color-primary);
  border-bottom: 1px solid var(--border-color-primary);
  gap: 1rem;
}

.search-box {
  position: relative;
  flex: 1;
  max-width: 400px;
}

.search-icon {
  position: absolute;
  left: 12px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--text-color-secondary);
  pointer-events: none;
}

.search-box input {
  width: 100%;
  padding: 0.75rem 0.75rem 0.75rem 2.5rem;
  border: 1px solid var(--border-color-primary);
  border-radius: 8px;
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
  font-size: 0.9rem;
  transition: all 0.2s ease;
  box-sizing: border-box;
  caret-color: var(--primary-color);
}

.search-box input:focus {
  outline: none;
  border-color: var(--primary-color);
}

.search-box input::placeholder {
  color: var(--text-color-secondary);
}

.filter-options {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.drafts-section {
  padding: 1rem;
}

.loading-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 3rem;
  color: var(--text-color-secondary);
}

.loading-spinner {
  width: 40px;
  height: 40px;
  border: 3px solid var(--border-color-primary);
  border-top: 3px solid var(--primary-color);
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin-bottom: 1rem;
}

@keyframes spin {
  0% {
    transform: rotate(0deg);
  }

  100% {
    transform: rotate(360deg);
  }
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 3rem;
  color: var(--text-color-secondary);
}

.empty-icon {
  margin-bottom: 1rem;
  opacity: 0.5;
}

.create-btn {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1.5rem;
  background: var(--primary-color);
  color: white;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  font-size: 0.9rem;
  font-weight: 500;
  margin-top: 1rem;
  transition: all 0.2s ease;
}

.create-btn:hover {
  background: var(--primary-color-dark);
}

.posts-list {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.pagination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  padding: 2rem 1rem;
}

.page-btn {
  padding: 0.5rem 1rem;
  border: 1px solid var(--border-color-primary);
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.2s ease;
}

.page-btn:hover:not(:disabled) {
  background: var(--primary-color);
  color: white;
  border-color: var(--primary-color);
}

.page-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.page-info {
  font-size: 0.9rem;
  color: var(--text-color-secondary);
}

@media (max-width: 960px) {
  .draft-box-container {
    margin: 72px 0;
  }
  
  .page-header {
    padding: 0.75rem 1rem;
  }
  
  .filter-section {
    flex-direction: column;
    align-items: stretch;
    gap: 0.75rem;
    padding: 0.75rem 1rem;
  }

  .search-box {
    max-width: none;
  }

  .filter-options {
    justify-content: flex-start;
    gap: 0.75rem;
  }
  
  .posts-section {
    padding: 0.75rem 1rem;
  }
}
</style>