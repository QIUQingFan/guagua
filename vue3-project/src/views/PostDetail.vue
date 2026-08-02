<template>
  <div class="post-detail-page">

    <div v-if="loading" class="loading-container">
      <div class="loading-spinner"></div>
      <p>加载中...</p>
    </div>

    <div v-else>

      <button v-if="showBackButton" @click="goBack" class="back-home-btn">
        <SvgIcon name="close" />
      </button>

      <DetailCard :item="postData" :page-mode="true" :target-comment-id="targetCommentId" />
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getPostDetail } from '@/api/posts'
import DetailCard from '@/components/DetailCard.vue'
import SvgIcon from '@/components/SvgIcon.vue'

const route = useRoute()
const router = useRouter()

const postData = ref(null)
const loading = ref(true)
const targetCommentId = ref(null)

const showBackButton = ref(false)

const originalTitle = ref('')

const updateShowBackButton = () => {
  showBackButton.value = window.innerWidth <= 768
}

const goBack = () => {
  router.push('/explore')
}

const fetchPostDetail = async (postId) => {
  try {
    loading.value = true
    const response = await getPostDetail(postId)

    if (response) {
      postData.value = response
      document.title = response.title || '笔记详情'
    } else {
      router.replace({ name: 'not_found' })
      return
    }
  } catch (error) {
    console.error('获取笔记详情出错:', error)
    router.replace({ name: 'not_found' })
    return
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  originalTitle.value = document.title

  const postId = route.query.id
  if (postId) {
    targetCommentId.value = route.query.targetCommentId || null
    fetchPostDetail(postId)
  } else {
    router.replace({ name: 'not_found' })
    loading.value = false
  }

  updateShowBackButton()
  window.addEventListener('resize', updateShowBackButton)
})

onUnmounted(() => {
  if (originalTitle.value) {
    document.title = originalTitle.value
  }

  window.removeEventListener('resize', updateShowBackButton)
})
</script>

<style scoped>
.post-detail-page {
  min-height: calc(100vh - 64px);
  margin: 10px;
  width: 100%;
  box-sizing: border-box;
  position: relative;
  padding-top: 64px;
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 64px 20px 20px 20px;
}

@media (max-width: 960px) {
  .post-detail-page {
    margin: 0;
    padding: 0;
    padding-top: 64px;
    width: 100vw;
    max-width: 100vw;
  }
}

@media (max-width: 768px) {
  .post-detail-page {
    margin: 0;
    padding: 0;
    overflow-y: visible;
    overflow-x: hidden;
    width: 100vw;
    height: 100vh;
    min-height: 100vh;
    max-width: 100vw;
    display: block;
    border-radius: 0;
    box-shadow: none;
    align-items: normal;
    justify-content: normal;
  }
}

.back-home-btn {
  position: fixed;
  top: calc(16px + env(safe-area-inset-top));
  left: 16px;
  z-index: 1001;
  background: transparent;
  color: var(--text-color-secondary);
  width: 36px;
  height: 36px;
  border: none;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: background-color 0.2s;
}

.back-home-btn:hover {
  background: rgba(144, 144, 144, 0.292);
}

.loading-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 400px;
  text-align: center;
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
}

@media (max-width: 960px) {
  .loading-container {
    position: relative;
    top: auto;
    left: auto;
    transform: none;
    min-height: calc(100vh - 64px);
    width: 100%;
  }
}

@media (max-width: 768px) {
  .loading-container {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    transform: none;
    min-height: 100vh;
    width: 100vw;
    height: 100vh;
    padding: 20px;
    box-sizing: border-box;
    background: var(--bg-color-primary);
    z-index: 1000;
  }
}

.loading-spinner {
  width: 40px;
  height: 40px;
  border: 4px solid var(--border-color-primary);
  border-top: 4px solid var(--primary-color);
  border-radius: 50%;
  animation: spin 1s linear infinite;
  margin-bottom: 16px;
}

@media (max-width: 768px) {
  .loading-spinner {
    width: 48px;
    height: 48px;
    border-width: 5px;
    margin-bottom: 20px;
  }
}

@keyframes spin {
  0% {
    transform: rotate(0deg);
  }

  100% {
    transform: rotate(360deg);
  }
}
</style>