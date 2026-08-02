<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useScroll, useWindowSize } from '@vueuse/core'
import { useNavigationStore } from '@/stores/navigation'
import { useUserStore } from '@/stores/user'
import { useFollowStore } from '@/stores/follow'
import { userApi } from '@/api'
import { useChatStore } from '@/stores/chat'
import WaterfallFlow from '@/components/WaterfallFlow.vue'
import FollowButton from '@/components/FollowButton.vue'
import SvgIcon from '@/components/SvgIcon.vue'
import UserPersonalityTags from './components/UserPersonalityTags.vue'
import ContentRenderer from '@/components/ContentRenderer.vue'
import BackToTopButton from '@/components/BackToTopButton.vue'
import ImageViewer from '@/components/ImageViewer.vue'
import VerifiedBadge from '@/components/VerifiedBadge.vue'

const route = useRoute()
const router = useRouter()
const navigationStore = useNavigationStore()
const userStore = useUserStore()
const followStore = useFollowStore()
const chatStore = useChatStore()

const defaultAvatar = new URL('@/assets/imgs/瓜呱.png', import.meta.url).href
const userId = ref(route.params.userId)
const loading = ref(true)

const { y: scrollY } = useScroll(window)
const { width: windowWidth } = useWindowSize()

const tabs = ref([
  { name: 'posts', label: '笔记' },
  { name: 'collections', label: '收藏' }
])

const activeTab = ref('posts')
const tabBarRef = ref(null)
const fixedTabBarRef = ref(null)

const userInfo = ref({
  id: null,
  user_id: '',
  nickname: '',
  avatar: '',
  bio: '',
  location: '',
  follow_count: 0,
  fans_count: 0,
  like_count: 0
})

const userStats = ref({
  follow_count: 0,
  fans_count: 0,
  post_count: 0,
  like_count: 0,
  collect_count: 0,
  likes_and_collects: 0
})

const followStatus = ref(false)

const showImageViewer = ref(false)
const currentImageUrl = ref('')

const isCurrentUser = computed(() => {
  return userStore.isLoggedIn && userStore.userInfo?.user_id === userId.value
})

const sliderStyle = computed(() => {
  const index = tabs.value.findIndex(tab => tab.name === activeTab.value)
  const isLargeScreen = windowWidth.value > 900

  if (isLargeScreen) {
    return {
      left: `calc(50% - 64px + ${index * 64}px)`
    }
  } else {
    return {
      left: `calc(50% - 56px + ${index * 64}px)`
    }
  }
})

const fixedSliderStyle = computed(() => {
  const index = tabs.value.findIndex(tab => tab.name === activeTab.value)
  const isLargeScreen = windowWidth.value > 900

  if (isLargeScreen) {
    return {
      left: `calc(220px + (100vw - 220px - 128px) / 2 + ${index * 64}px)`
    }
  } else {
    return {
      left: `calc(50% - 56px + ${index * 64}px)`
    }
  }
})

function onTabClick(tabName) {
  const currentScrollTop = window.pageYOffset || document.documentElement.scrollTop

  if (currentScrollTop > 500) { 
    navigationStore.scrollToTop('instant')
  }

  activeTab.value = tabName

  if (currentScrollTop <= 500) {
    setTimeout(() => {
      navigationStore.scrollToTop('smooth')
    }, 300) 
  }
}

function goTop() {
  navigationStore.scrollToTop('smooth')
}

const getUserInfo = async () => {
  loading.value = true
  try {
    const response = await userApi.getUserInfo(userId.value)

    if (response.success) {
      userInfo.value = response.data
      await getFollowStatus()
    } else {
      userInfo.value = {}
    }
  } catch (error) {
    console.error('获取用户信息失败:', error)
    userInfo.value = {}
  } finally {
    loading.value = false
  }
}

const getUserStats = async () => {
  try {
    const response = await userApi.getUserStats(userId.value)
    if (response.success) {
      userStats.value = response.data
    }
  } catch (error) {
    console.error('获取用户统计信息失败:', error)
  }
}

const startChat = () => {
  if (!userStore.isLoggedIn) {
    const authStore = useAuthStore()
    authStore.openLoginModal()
    return
  }

  if (!chatStore.isInitialized) {
    chatStore.init()
  }

  router.push({
    name: 'chat',
    query: {
      userId: userInfo.value.id,
      nickname: userInfo.value.nickname || '',
      avatar: userInfo.value.avatar || ''
    }
  })
}

const getFollowStatus = async () => {
  if (isCurrentUser.value || !userInfo.value.user_id) return

  try {
    const result = await followStore.fetchFollowStatus(userInfo.value.user_id)
    if (result.success) {
      followStatus.value = result.data.followed
      followStore.initUserFollowState(
        userInfo.value.user_id,
        result.data.followed,
        result.data.isMutual || false,
        result.data.buttonType || 'follow'
      )
    } else {
      followStatus.value = false
    }
  } catch (error) {
    console.error('获取关注状态失败:', error)
    followStatus.value = false
  }
}

function handleAvatarError(event) {
  event.target.src = defaultAvatar
}

const previewAvatar = () => {
  console.log('点击头像预览 - 开始')
  console.log('userInfo.value:', userInfo.value)
  const avatarUrl = userInfo.value.avatar || defaultAvatar
  console.log('avatarUrl:', avatarUrl)
  currentImageUrl.value = avatarUrl
  showImageViewer.value = true
  console.log('showImageViewer设置为true:', showImageViewer.value)
  console.log('currentImageUrl设置为:', currentImageUrl.value)
}

watch(() => route.params.userId, (newUserId) => {
  if (newUserId) {
    if (userStore.isLoggedIn && userStore.userInfo?.user_id === newUserId) {
      router.replace('/user')
      return
    }

    userId.value = newUserId
    activeTab.value = 'posts'

    getUserInfo()
    getUserStats()

    navigationStore.scrollToTop('instant')
  }
})

onMounted(async () => {
  if (userStore.isLoggedIn && userStore.userInfo?.user_id === userId.value) {
    router.replace('/user')
    return
  }

  await getUserInfo()
  await getUserStats()
  navigationStore.scrollToTop('instant')
})
</script>
<template>
  <div class="content-container">

    <div class="user-info" v-if="userInfo.nickname">
      <div class="basic-info">
        <img :src="userInfo.avatar || defaultAvatar" :alt="userInfo.nickname || '用户头像'" class="avatar"
          @click="previewAvatar" @error="handleAvatarError">
        <div class="user-basic">
          <div class="user-nickname">
            <span>{{ userInfo?.nickname || '用户' }}</span>
            <VerifiedBadge :verified="userInfo?.verified" size="large" />
          </div>
          <div class="user-content">
            <div class="user-id text-ellipsis">瓜呱号：{{ userInfo?.user_id || '' }}</div>
            <div class="user-IP text-ellipsis">IP属地：{{ userInfo?.location || '未知' }}</div>
          </div>
        </div>

        <div class="action-buttons" v-if="!isCurrentUser">
          <FollowButton :user-id="userInfo.user_id" :is-following="followStatus" />
          <button class="chat-btn" @click="startChat">
            <SvgIcon name="chat" width="16px" height="16px" />
            <span>发消息</span>
          </button>
        </div>
      </div>
      <div class="user-desc">
        <ContentRenderer v-if="userInfo.bio" :text="userInfo.bio" />
        <span v-else>用户没有任何简介</span>
      </div>

      <UserPersonalityTags :user-info="userInfo" />
      <div class="user-interactions">
        <div class="interaction-item">
          <span class="count">{{ userStats.follow_count || 0 }}</span>
          <span class="shows">关注</span>
        </div>
        <div class="interaction-item">
          <span class="count">{{ userStats.fans_count || 0 }}</span>
          <span class="shows">粉丝</span>
        </div>
        <div class="interaction-item">
          <span class="count">{{ userStats.likes_and_collects || 0 }}</span>
          <span class="shows">获赞与收藏</span>
        </div>
      </div>
    </div>

    <div class="loading-state" v-else-if="loading">
      <div class="loading-content">
        <SvgIcon name="loading" width="32" height="32" class="loading-icon" />
        <p>加载用户信息中...</p>
      </div>
    </div>

    <div class="error-state" v-else>
      <div class="error-content">
        <SvgIcon name="user" width="48" height="48" class="error-icon" />
        <h3>用户不存在</h3>
        <p>该用户可能已被删除或不存在</p>
      </div>
    </div>

    <div class="tab" ref="tabBarRef" v-if="userInfo.nickname">
      <div v-for="item in tabs" class="tab-item" :class="{ active: activeTab === item.name }"
        @click="onTabClick(item.name)">
        {{ item.label }}
      </div>
      <div class="tab-slider" :style="sliderStyle"></div>
    </div>

    <div class="fixedTab" :class="{ hidden: scrollY < 300 }" ref="fixedTabBarRef" v-if="userInfo.nickname">
      <div v-for="item in tabs" class="tab-item" :class="{ active: activeTab === item.name }"
        @click="onTabClick(item.name)">
        {{ item.label }}
      </div>
      <div class="tab-slider" :style="fixedSliderStyle"></div>
    </div>

    <div class="content-switch-container" v-if="userInfo.nickname">

      <div class="content-item" :class="{ active: activeTab === 'posts' }"
        :style="{ transform: activeTab === 'posts' ? 'translateX(0%)' : 'translateX(-100%)' }">
        <div class="waterfall-container">
          <WaterfallFlow :userId="userId" :type="'posts'" :key="`posts-${userId}`" />
        </div>
      </div>

      <div class="content-item" :class="{ active: activeTab === 'collections' }"
        :style="{ transform: activeTab === 'collections' ? 'translateX(0%)' : 'translateX(100%)' }">
        <div class="waterfall-container">
          <WaterfallFlow :userId="userId" :type="'collections'" :key="`collections-${userId}`" />
        </div>
      </div>
    </div>

    <BackToTopButton />

    <ImageViewer :visible="showImageViewer" :images="[currentImageUrl]" :initial-index="0"
      @close="showImageViewer = false" />
  </div>
</template>

<style scoped>
* {
  box-sizing: border-box;
}

.content-container {
  padding-top: 72px;
  margin: 0 auto;
  width: 100%;
  max-width: 1200px;
  background: var(--bg-color-primary);
  min-height: 100vh;
  transition: background-color 0.2s ease;
}

.content-area {
  width: 100%;
  background-color: var(--bg-color-primary);
  margin-bottom: 0;
  padding: 0px 10px calc(48px + constant(safe-area-inset-bottom)) 10px;
  padding: 0px 10px calc(48px + env(safe-area-inset-bottom)) 10px;
  box-sizing: border-box;
  overflow-x: hidden;
  transition: background-color 0.2s ease;
}

.user-info {
  height: auto;
  min-height: 196px;
  padding: 16px 0;
  width: 100%;
  max-width: 1200px;
  overflow-x: hidden;
  background: var(--bg-color-primary);
  transition: background-color 0.2s ease;
}

.basic-info {
  display: flex;
  flex-direction: row;
  align-items: center;
  height: 72px;
  width: 100%;
  padding: 0 16px;
  position: relative;
}

.avatar {
  width: 72px;
  height: 72px;
  border-radius: 50%;
  border: 1px solid var(--border-color-primary);
  cursor: pointer;
}

.user-basic {
  display: flex;
  flex-direction: column;
  flex: 1;
  margin-left: 16px;
  gap: 6px;
}

.user-nickname {
  color: var(--text-color-primary);
  font-size: 18px;
  font-weight: bold;
  gap: 6px;
  align-items: center;
  display: flex;
}

.user-content {
  display: flex;
  flex-direction: column;
  color: var(--text-color-quaternary);
  font-size: 12px;
  gap: 4px;
  max-width: 100%;
}

@media (min-width: 901px) {
  .user-content {
    flex-direction: row;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
}

.user-id {
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.user-IP {
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.user-IP::before {
  content: '';
  display: none;
}

@media (min-width: 901px) {
  .user-id {
    max-width: 60%;
  }

  .user-IP::before {
    content: '';
    display: inline-block;
    width: 0.92px;
    height: 12px;
    background-color: var(--bg-color-tertiary);
    margin-right: 8px;
    vertical-align: middle;
  }
}

.user-desc {
  margin: 17px 0px 0px;
  color: var(--text-color-primary);
  font-size: 14px;
  padding: 0 16px;
}

.user-interactions {
  display: flex;
  padding: 0 16px;
  flex-wrap: wrap;
  width: 100%;
}

.user-interactions div {
  display: flex;
  flex-direction: column;
  margin-right: 16px;
  margin-top: 20px;
}

.interaction-item {
  cursor: pointer;
  padding: 4px 8px;
  border-radius: 8px;
  transition: background-color 0.2s ease;
}

.interaction-item:hover {
  background-color: var(--bg-color-secondary);
}

.interaction-item:last-child {
  cursor: default;
}

.interaction-item:last-child:hover {
  background-color: transparent;
}

.count {
  color: var(--text-color-primary);
  margin-right: 4px;
  font-size: 14px;
  text-align: center;
}

.shows {
  color: var(--text-color-quaternary);
  margin: 4px 0 0;
  font-size: 14px;
  text-align: center;
}

.action-buttons {
  position: absolute;
  right: 16px;
  top: 50%;
  transform: translateY(-50%);
  display: flex;
  align-items: center;
  gap: 12px;
}

.chat-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 16px;
  border: 1px solid var(--border-color-secondary);
  border-radius: 20px;
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s;
}

.chat-btn:hover {
  background: var(--bg-color-secondary);
  border-color: var(--primary-color);
  color: var(--primary-color);
}

.loading-state,
.error-state {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 300px;
  padding: 40px 16px;
  background: var(--bg-color-primary);
}

.loading-content,
.error-content {
  text-align: center;
  max-width: 300px;
}

.loading-icon,
.error-icon {
  color: var(--text-color-quaternary);
  margin-bottom: 16px;
}

.loading-content p,
.error-content h3 {
  color: var(--text-color-primary);
  font-size: 18px;
  font-weight: 600;
  margin: 0 0 8px 0;
}

.error-content p {
  color: var(--text-color-secondary);
  font-size: 14px;
  margin: 0;
  line-height: 1.5;
}

.tab {
  position: relative;
  display: flex;
  justify-content: center;
  padding-left: 16px;
  padding-top: 16px;
  padding-bottom: 16px;
  background: var(--bg-color-primary);
  transition: background-color 0.2s ease;
}

.fixedTab {
  position: fixed;
  top: 72px;
  z-index: 99;
  transform: none;
  background: var(--bg-color-primary);
  display: flex;
  justify-content: center;
  left: 0;
  right: 0;
  padding-left: 16px;
  padding-top: 16px;
  padding-bottom: 16px;
  transition: background-color 0.2s ease;
}

.tab-item {
  width: 64px;
  height: 40px;
  font-size: 16px;
  color: var(--text-color-secondary);
  cursor: pointer;
  background: transparent;
  border-radius: 999px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  user-select: none;
  position: relative;
  z-index: 1;
  transition: color 0.2s ease, background-color 0.2s ease;
}

.tab-item:hover {
  color: var(--text-color-primary);
  transition: color 0.2s ease;
}

.tab-item.active {
  color: var(--text-color-primary);
  font-weight: bold;
  background: transparent;
  transition: color 0.2s ease;
}

.tab-slider {
  position: absolute;
  top: 16px;
  width: 64px;
  height: 40px;
  border-radius: 999px;
  background: var(--bg-color-secondary);
  transition: left 0.3s cubic-bezier(.4, 0, .2, 1), background-color 0.2s ease;
  z-index: 0;
}

.fixedTab .tab-slider {
  position: absolute;
  top: 16px;
  width: 64px;
  height: 40px;
  border-radius: 999px;
  background: var(--bg-color-secondary);
  transition: left 0.3s cubic-bezier(.4, 0, .2, 1), background-color 0.2s ease;
  z-index: 0;
}

.hidden {
  display: none;
}

.content-switch-container {
  width: 100%;
  max-width: 1200px;
  background: var(--bg-color-primary);
  margin: 0 auto;
  position: relative;
  overflow: hidden;
  transition: background-color 0.2s ease;
}

.content-item {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  background: var(--bg-color-primary);
  transition: transform 0.3s ease;
  opacity: 0;
  pointer-events: none;
  display: flex;
  justify-content: center;
}

.content-item.active {
  position: relative;
  opacity: 1;
  pointer-events: auto;
}

.waterfall-container {
  width: 100%;
  max-width: 700px;
  padding: 0 8px;
  margin: 0 auto;
  background: var(--bg-color-primary);
  transition: background-color 0.2s ease;
}

@media (min-width: 960px) {
  .waterfall-container {
    max-width: 1000px;
    padding: 0 16px;
  }
}

.btn {
  display: flex;
  justify-content: center;
  align-items: center;
  width: 38px;
  height: 38px;
  border-radius: 50%;
  background-color: var(--bg-color-primary);
  border: var(--border-color-primary) 1px solid;
  cursor: pointer;
  transition: background-color 0.2s ease, border-color 0.2s ease, transform 0.2s ease;
}

.btn-icon {
  color: var(--text-color-secondary);
  transition: color 0.3s ease;
}

.btn:hover {
  background-color: var(--bg-color-secondary);
  transition: all 0.2s ease;
}

.btn:hover .btn-icon {
  color: var(--text-color-primary);
}

.text-ellipsis {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
}

@media (min-width: 901px) {

  .user-info {
    max-width: 650px;
    margin: 0 auto;
    padding: 16px 0px;
  }

  .basic-info,
  .user-desc,
  .user-interactions {
    padding: 0;
  }

  .action-buttons {
    right: 0;
  }

  .tab {
    max-width: 700px;
    margin: 0 auto;
    padding-left: 0;
  }

  .fixedTab {
    padding-left: 220px;
  }

  .content-item {
    padding-left: 0;
  }
}
</style>