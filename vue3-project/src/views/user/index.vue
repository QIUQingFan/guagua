<script setup>
import { ref, computed, onMounted, nextTick, watch, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useScroll, useWindowSize } from '@vueuse/core'
import { useNavigationStore } from '@/stores/navigation'
import { useUserStore } from '@/stores/user'
import WaterfallFlow from '@/components/WaterfallFlow.vue'
import SvgIcon from '@/components/SvgIcon.vue'
import { eventBus, EVENT_TYPES } from '@/utils/eventBus.js'
import EditProfileModal from './components/EditProfileModal.vue'
import UserPersonalityTags from './components/UserPersonalityTags.vue'
import ContentRenderer from '@/components/ContentRenderer.vue'
import { userApi } from '@/api/index.js'
import BackToTopButton from '@/components/BackToTopButton.vue'
import ImageViewer from '@/components/ImageViewer.vue'
import VerifiedBadge from '@/components/VerifiedBadge.vue'

const router = useRouter()
const navigationStore = useNavigationStore()
const userStore = useUserStore()

const defaultAvatar = new URL('@/assets/imgs/瓜呱.png', import.meta.url).href

const userStats = ref({
  follow_count: 0,
  fans_count: 0,
  post_count: 0,
  like_count: 0,
  collect_count: 0,
  likes_and_collects: 0
})

const showEditProfileModal = ref(false)
const editProfileModalRef = ref(null)

const showImageViewer = ref(false)
const currentImageUrl = ref('')

const openEditProfileModal = () => {
  showEditProfileModal.value = true
}

const closeEditProfileModal = () => {
  showEditProfileModal.value = false
}

const previewAvatar = () => {
  console.log('点击头像预览 - 开始')
  console.log('userStore.userInfo:', userStore.userInfo)
  const avatarUrl = userStore.userInfo?.avatar || defaultAvatar
  console.log('avatarUrl:', avatarUrl)
  currentImageUrl.value = avatarUrl
  showImageViewer.value = true
  console.log('showImageViewer设置为true:', showImageViewer.value)
  console.log('currentImageUrl设置为:', currentImageUrl.value)
}

function handleAvatarError(event) {
  event.target.src = defaultAvatar
}

const handleProfileSaved = async (formData) => {
  try {
    const response = await userApi.updateUserInfo(userStore.userInfo.user_id, formData)

    if (response.success) {
      
      userStore.updateUserInfo(formData)
      await userStore.getCurrentUser()
      
      editProfileModalRef.value?.onSaveSuccess()
      loadUserStats()
    } else {
      
      editProfileModalRef.value?.onSaveError(response.message || '资料更新失败')
    }
  } catch (error) {
    console.error('用户资料更新API调用失败:', error)
    editProfileModalRef.value?.onSaveError('资料更新失败，请重试')
  }
}

const formatNumber = (num) => {
  if (num == null || isNaN(num)) {
    return '0'
  }

  const numValue = Number(num)
  if (numValue >= 10000) {
    return (numValue / 10000).toFixed(1) + '万'
  }
  return numValue.toString()
}

const loadUserStats = async () => {
  if (userStore.userInfo?.user_id) {
    const stats = await userStore.getUserStats(userStore.userInfo.user_id)
    if (stats) {
      userStats.value = stats
    }
  }
}

onMounted(() => {
  navigationStore.scrollToTop('instant')

  eventBus.on(EVENT_TYPES.USER_LIKED_POST, handleGlobalLikeEvent)
  eventBus.on(EVENT_TYPES.USER_UNLIKED_POST, handleGlobalLikeEvent)
  eventBus.on(EVENT_TYPES.USER_COLLECTED_POST, handleGlobalCollectEvent)
  eventBus.on(EVENT_TYPES.USER_UNCOLLECTED_POST, handleGlobalCollectEvent)
})

onUnmounted(() => {
  eventBus.off(EVENT_TYPES.USER_LIKED_POST, handleGlobalLikeEvent)
  eventBus.off(EVENT_TYPES.USER_UNLIKED_POST, handleGlobalLikeEvent)
  eventBus.off(EVENT_TYPES.USER_COLLECTED_POST, handleGlobalCollectEvent)
  eventBus.off(EVENT_TYPES.USER_UNCOLLECTED_POST, handleGlobalCollectEvent)
})

function handleGlobalLikeEvent(data) {
  console.log('用户页面: 收到全局点赞事件', data)
  refreshKeys.value.likes++
  setTimeout(() => {
    loadUserStats()
  }, 500)
}

function handleGlobalCollectEvent(data) {
  console.log('用户页面: 收到全局收藏事件', data)
  refreshKeys.value.collections++
  setTimeout(() => {
    loadUserStats()
  }, 500)
}

let hasLoadedStatsOnce = false
watch(() => userStore.userInfo?.user_id, (newUserId) => {
  if (!newUserId) return
  if (hasLoadedStatsOnce) return
  hasLoadedStatsOnce = true
  loadUserStats()
}, { immediate: true })

const { y: scrollY } = useScroll(window)
const { width: windowWidth } = useWindowSize()

const tabs = ref([
  { name: 'posts', label: '笔记' },
  { name: 'collections', label: '收藏' },
  { name: 'likes', label: '点赞' }
])

const activeTab = ref('posts')
const tabBarRef = ref(null)
const fixedTabBarRef = ref(null)

const refreshKeys = ref({
  posts: 0,
  collections: 0,
  likes: 0
})

const sliderStyle = computed(() => {
  const index = tabs.value.findIndex(tab => tab.name === activeTab.value)
  const isLargeScreen = windowWidth.value > 900

  if (isLargeScreen) {
    return {
      left: `calc(50% - 96px + ${index * 64}px)`
    }
  } else {
    return {
      left: `calc(50% - 88px + ${index * 64}px)`
    }
  }
})

const fixedSliderStyle = computed(() => {
  const index = tabs.value.findIndex(tab => tab.name === activeTab.value)
  const isLargeScreen = windowWidth.value > 900

  if (isLargeScreen) {
    
    
    return {
      left: `calc(240px + (100vw - 240px - 192px) / 2 + ${index * 64}px)`
    }
  } else {
    return {
      left: `calc(50% - 88px + ${index * 64}px)`
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

function goToFollowList(type) {
  router.push({
    name: 'follow_list',
    params: { type }
  })
}

function handleFollow(userId) {
  console.log('用户页面: 收到关注事件，用户ID:', userId)
  setTimeout(() => {
    loadUserStats()
  }, 500)
}

function handleUnfollow(userId) {
  console.log('用户页面: 收到取消关注事件，用户ID:', userId)
  setTimeout(() => {
    loadUserStats()
  }, 500)
}

function handleLike(data) {
  console.log('点赞操作:', data)
  setTimeout(() => {
    loadUserStats()
  }, 500)

  if (data && data.liked) {
    refreshKeys.value.likes++
  }
  if (data && !data.liked) {
    refreshKeys.value.likes++
  }
}

function handleCollect(data) {
  console.log('收藏操作:', data)
  setTimeout(() => {
    loadUserStats()
  }, 500)

  if (data && data.collected) {
    refreshKeys.value.collections++
  }
  if (data && !data.collected) {
    refreshKeys.value.collections++
  }
}
</script>
<template>
  <div class="content-container">
    <div class="user-info" v-if="userStore.isLoggedIn">
      <div class="basic-info">
        <img :src="userStore.userInfo?.avatar || defaultAvatar" :alt="userStore.userInfo?.nickname || '用户头像'"
          class="avatar" @click="previewAvatar" @error="handleAvatarError" v-img-fallback="avatar">
        <div class="user-basic">
          <div class="user-nickname">
            <span>{{ userStore.userInfo?.nickname || '用户' }}</span>
            <VerifiedBadge v-if="userStore.userInfo?.verified" :verified="userStore.userInfo.verified" size="large"/>
          </div>
          <div class="user-content">
            <div class="user-id text-ellipsis">瓜呱号：{{ userStore.userInfo?.user_id || '' }}</div>
            <div class="user-IP text-ellipsis">IP属地：{{ userStore.userInfo?.location || '未知' }}</div>
          </div>
        </div>
        <div class="edit-profile-button-wrapper">
          <button class="edit-profile-btn" @click="openEditProfileModal">
            编辑资料
          </button>
        </div>
      </div>
      <div class="user-desc">
        <ContentRenderer v-if="userStore.userInfo?.bio" :text="userStore.userInfo.bio" />
        <span v-else>用户没有任何简介</span>
      </div>

      <UserPersonalityTags :user-info="userStore.userInfo" />
      <div class="user-interactions">
        <div class="interaction-item" @click="goToFollowList('following')">
          <span class="count">{{ formatNumber(userStats.follow_count) }}</span>
          <span class="shows">关注</span>
        </div>
        <div class="interaction-item" @click="goToFollowList('followers')">
          <span class="count">{{ formatNumber(userStats.fans_count) }}</span>
          <span class="shows">粉丝</span>
        </div>
        <div class="interaction-item">
          <span class="count">{{ formatNumber(userStats.likes_and_collects) }}</span>
          <span class="shows">获赞与收藏</span>
        </div>
      </div>
    </div>

    <div class="login-prompt" v-else>
      <div class="prompt-content">
        <SvgIcon name="user" width="48" height="48" class="prompt-icon" />
        <h3>请先登录</h3>
        <p>登录后即可查看个人信息和管理内容</p>
      </div>
    </div>

    <div class="tab" ref="tabBarRef" v-if="userStore.isLoggedIn">

      <div v-for="item in tabs" class="tab-item" :class="{ active: activeTab === item.name }"
        @click="onTabClick(item.name)">
        {{ item.label }}</div>
      <div class="tab-slider" :style="sliderStyle"></div>
    </div>

    <div class="fixedTab" :class="{ hidden: scrollY < 300 }" ref="fixedTabBarRef" v-if="userStore.isLoggedIn">

      <div v-for="item in tabs" class="tab-item" :class="{ active: activeTab === item.name }"
        @click="onTabClick(item.name)">
        {{ item.label }}</div>
      <div class="tab-slider" :style="fixedSliderStyle"></div>
    </div>

    <div class="content-switch-container" v-if="userStore.isLoggedIn">

      <div class="content-item" :class="{ active: activeTab === 'posts' }"
        :style="{ transform: activeTab === 'posts' ? 'translateX(0%)' : 'translateX(-100%)' }">
        <div class="waterfall-container">
          <WaterfallFlow :userId="userStore.userInfo?.user_id" :type="'posts'" :refreshKey="refreshKeys.posts"
            @follow="handleFollow" @unfollow="handleUnfollow" @like="handleLike" @collect="handleCollect" />
        </div>
      </div>

      <div class="content-item" :class="{ active: activeTab === 'collections' }"
        :style="{ transform: activeTab === 'collections' ? 'translateX(0%)' : activeTab === 'posts' ? 'translateX(100%)' : 'translateX(-100%)' }">
        <div class="waterfall-container">
          <WaterfallFlow :userId="userStore.userInfo?.user_id" :type="'collections'"
            :refreshKey="refreshKeys.collections" @follow="handleFollow" @unfollow="handleUnfollow" @like="handleLike"
            @collect="handleCollect" />
        </div>
      </div>

      <div class="content-item" :class="{ active: activeTab === 'likes' }"
        :style="{ transform: activeTab === 'likes' ? 'translateX(0%)' : 'translateX(100%)' }">
        <div class="waterfall-container">
          <WaterfallFlow :userId="userStore.userInfo?.user_id" :type="'likes'" :refreshKey="refreshKeys.likes"
            @follow="handleFollow" @unfollow="handleUnfollow" @like="handleLike" @collect="handleCollect" />
        </div>
      </div>
    </div>

    <BackToTopButton />

    <EditProfileModal ref="editProfileModalRef" :visible="showEditProfileModal" :user-info="userStore.userInfo"
      @update:visible="showEditProfileModal = $event" @save="handleProfileSaved" />

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
  
  overflow-x: hidden;
}

.content-switch-container {
  width: 100%;
  max-width: 1200px;
  background: var(--bg-color-primary);
  margin: 0 auto;
  position: relative;
  overflow: hidden;
  padding-bottom: calc(48px + constant(safe-area-inset-bottom));
  padding-bottom: calc(48px + env(safe-area-inset-bottom));
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

.user-info {
  height: auto;
  min-height: 196px;
  padding: 16px 0;
  width: 100%;
  max-width: 700px;
  margin: 0 auto;
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
  display: flex;
  align-items: center;
  gap: 6px;
  color: var(--text-color-primary);
  font-size: 18px;
  font-weight: bold;
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
    transition: background-color 0.2s ease;
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

.login-prompt {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 300px;
  padding: 40px 16px;
  background: var(--bg-color-primary);
  transition: background-color 0.2s ease;
}

.prompt-content {
  text-align: center;
  max-width: 300px;
}

.prompt-icon {
  color: var(--text-color-quaternary);
  margin-bottom: 16px;
}

.prompt-content h3 {
  color: var(--text-color-primary);
  font-size: 18px;
  font-weight: 600;
  margin: 0 0 8px 0;
}

.prompt-content p {
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
  max-width: 700px;
  margin: 0 auto;
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

.edit-profile-button-wrapper {
  position: absolute;
  right: 16px;
  top: 50%;
  transform: translateY(-50%);
}

.edit-profile-btn {
  padding: 3px 16px;
  border: 1px solid var(--text-color-quaternary);
  border-radius: 20px;
  font-size: 14px;
  font-weight: bold;
  cursor: pointer;
  width: 90px;
  height: 40px;
  text-align: center;
  transition: all 0.2s ease;
  user-select: none;
  background: #aeadad0d;
  color: var(--text-color-tertiary);
}

.edit-profile-btn:hover {
  background: #6e6e6e2c;
  color: var(--text-color-secondary);
  border-color: var(--text-color-tertiary);
}

.text-ellipsis {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
}

@media (min-width: 901px) {

  .user-info {
    max-width: 1000px;
    margin: 0 auto;
    padding: 16px 0px;
  }

  .basic-info,
  .user-desc,
  .user-interactions {
    padding: 0;
  }

  .tab {
    max-width: 1000px;
    margin: 0 auto;
    padding-left: 0;
  }

  .fixedTab {
    padding-left: 240px;
  }

  .content-item {
    padding-left: 0;
  }

  .edit-profile-button-wrapper {
    right: 0;
  }

}
</style>