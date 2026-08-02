import { defineStore } from 'pinia'
import { ref } from 'vue'
import { getUnreadNotificationCount, getUnreadNotificationCountByType } from '@/api/notification.js'

export const useNotificationStore = defineStore('notification', () => {
  const unreadCount = ref(0)

  const unreadCountByType = ref({
    comments: 0,
    likes: 0,
    collections: 0,
    follows: 0
  })

  async function fetchUnreadCount() {
    try {
      const response = await getUnreadNotificationCount()
      unreadCount.value = response.count || 0
      return unreadCount.value
    } catch (error) {
      console.error('获取未读通知数量失败:', error)
      unreadCount.value = 0
      return 0
    }
  }

  async function fetchUnreadCountByType() {
    try {
      const response = await getUnreadNotificationCountByType()
      unreadCountByType.value = {
        comments: response.comments || 0,
        likes: response.likes || 0,
        collections: response.collections || 0,
        follows: response.follows || 0
      }
      unreadCount.value = response.total || 0
      return unreadCountByType.value
    } catch (error) {
      console.error('获取按类型的未读通知数量失败:', error)
      unreadCountByType.value = {
        comments: 0,
        likes: 0,
        collections: 0,
        follows: 0
      }
      return unreadCountByType.value
    }
  }

  function decrementUnreadCount() {
    if (unreadCount.value > 0) {
      unreadCount.value--
    }
  }

  function decrementUnreadCountByType(type) {
    if (unreadCountByType.value[type] > 0) {
      unreadCountByType.value[type]--
    }
    if (unreadCount.value > 0) {
      unreadCount.value--
    }
  }

  function clearUnreadCount() {
    unreadCount.value = 0
    unreadCountByType.value = {
      comments: 0,
      likes: 0,
      collections: 0,
      follows: 0
    }
  }

  function resetUnreadCount() {
    unreadCount.value = 0
    unreadCountByType.value = {
      comments: 0,
      likes: 0,
      collections: 0,
      follows: 0
    }
  }

  return {
    unreadCount,
    unreadCountByType,
    fetchUnreadCount,
    fetchUnreadCountByType,
    decrementUnreadCount,
    decrementUnreadCountByType,
    clearUnreadCount,
    resetUnreadCount
  }
})