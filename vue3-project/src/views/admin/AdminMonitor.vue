<template>
  <div class="admin-monitor">
    <div class="monitor-content">
      <div class="activities-section">
        <div v-if="error" class="error-state">
          <p>{{ error }}</p>
        </div>

        <div v-else-if="activities.length === 0" class="empty-state">
          <p>暂无动态</p>
        </div>

        <div v-else class="activities-list">
          <div v-for="activity in activities" :key="activity.id" class="activity-item"
            @click="handleActivityClick(activity)">
            <div class="activity-icon">
              <img :src="activity.avatar || defaultAvatar" alt="avatar" class="activity-avatar"
                @error="onAvatarError($event)" />
            </div>
            <div class="activity-content">
              <div class="activity-title">
                <template v-if="activity.type === 'comment_publish'">
                  <div class="comment-description">{{ activity.description }}</div>
                  <ContentRenderer :content="activity.content" />
                </template>
                <ContentRenderer v-else :text="activity.description || activity.content" />
              </div>
              <div class="activity-meta">
                <span class="activity-type">{{ getActivityTypeText(activity.type) }}</span>
                <span class="activity-user">{{ activity.nickname }}</span>
              </div>
            </div>
            <div class="activity-time">
              {{ formatTime(activity.created_at) }}
            </div>
          </div>
        </div>
      </div>
    </div>

  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { adminApi } from '@/api'
import defaultAvatar from '@/assets/imgs/瓜呱.png'
import ContentRenderer from '@/components/ContentRenderer.vue'
const router = useRouter()
const activities = ref([])
const error = ref('')
const onAvatarError = (e) => {
  e.target.src = defaultAvatar
}

const fetchActivities = async () => {
  try {
    error.value = ''
    const response = await adminApi.getMonitorActivities()
    if (response && response.success) {
      activities.value = Array.isArray(response.data) ? response.data : []
    } else {
      error.value = (response && response.message) || '获取动态失败'
      activities.value = []
    }
  } catch (err) {
    console.error('获取动态失败:', err)
    error.value = '网络错误，请稍后重试'
    activities.value = []
  } finally {
  }
}

const getActivityIcon = (type) => {
  const iconMap = {
    'user_register': 'user',
    'post_publish': 'post',
    'comment_publish': 'chat'
  }
  return iconMap[type] || 'data'
}

const getActivityTypeText = (type) => {
  const typeMap = {
    'user_register': '用户注册',
    'post_publish': '发布笔记',
    'comment_publish': '发表评论'
  }
  return typeMap[type] || '未知活动'
}

const formatTime = (timeStr) => {
  const time = new Date(timeStr)
  const now = new Date()
  const diff = now - time

  if (diff < 60000) {
    return '刚刚'
  }

  if (diff < 3600000) {
    return `${Math.floor(diff / 60000)}分钟前`
  }

  if (diff < 86400000) {
    return `${Math.floor(diff / 3600000)}小时前`
  }

  if (diff < 604800000) {
    return `${Math.floor(diff / 86400000)}天前`
  }

  return time.toLocaleDateString('zh-CN', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}

const handleActivityClick = (activity) => {
  if (activity.type === 'user_register') {
    const url = `${window.location.origin}/user/${activity.user_id}`
    window.open(url, '_blank')
  } else if (activity.type === 'post_publish') {
    const url = `${window.location.origin}/post?id=${activity.target_id}`
    window.open(url, '_blank')
  } else if (activity.type === 'comment_publish') {
    const url = `${window.location.origin}/post?id=${activity.target_id}&targetCommentId=${activity.id}`
    window.open(url, '_blank')
  }
}

onMounted(() => {
  fetchActivities()
})
</script>

<style scoped>
.admin-monitor {
  padding: 12px;
  background-color: var(--bg-color-primary);
  min-height: 100%;
}

.monitor-content {
  max-width: 1200px;
  margin: 0 auto;
}

.activities-section {
  background-color: var(--bg-color-primary);
  border-radius: 12px;
  border: 1px solid var(--border-color-primary);
  overflow: hidden;
}

.error-state,
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 64px 32px;
  color: var(--text-color-secondary);
}

.retry-btn {
  margin-top: 16px;
  padding: 8px 16px;
  background-color: var(--primary-color);
  color: white;
  border: none;
  border-radius: 6px;
  cursor: pointer;
}

.activities-list {
  padding: 0;
}

.activity-item {
  display: flex;
  align-items: center;
  padding: 20px 32px;
  border-bottom: 1px solid var(--border-color-primary);
  cursor: pointer;
  transition: background-color 0.2s ease;
}

.activity-item:hover {
  background-color: var(--bg-color-secondary);
}

.activity-item:last-child {
  border-bottom: none;
}

.activity-icon {
  width: 40px;
  height: 40px;
  margin-right: 12px;
  flex-shrink: 0;
}

.activity-avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  object-fit: cover;
  border: 1px solid var(--border-color-primary);
}

.activity-content {
  flex: 1;
  min-width: 0;
}

.activity-title {
  font-size: 16px;
  font-weight: 500;
  color: var(--text-color-primary);
  margin-bottom: 4px;
  line-height: 1.4;
}

.activity-meta {
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 14px;
  color: var(--text-color-secondary);
}

.activity-type {
  padding: 2px 8px;
  background-color: var(--bg-color-secondary);
  border-radius: 4px;
  font-size: 12px;
}

.activity-time {
  font-size: 14px;
  color: var(--text-color-tertiary);
  white-space: nowrap;
  margin-left: 16px;
}
</style>