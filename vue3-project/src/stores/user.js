import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { authApi, userApi } from '@/api/index.js'

export const useUserStore = defineStore('user', () => {
  const token = ref(localStorage.getItem('token') || '')
  const refreshToken = ref(localStorage.getItem('refreshToken') || '')
  const userInfo = ref(null)
  const isLoading = ref(false)

  const isLoggedIn = computed(() => {
    return !!token.value && (!!userInfo.value || !!localStorage.getItem('userInfo'))
  })

  const login = async (credentials) => {
    try {
      isLoading.value = true
      const response = await authApi.login(credentials)

      if (response.success && response.data) {
        token.value = response.data.tokens.access_token
        refreshToken.value = response.data.tokens.refresh_token
        userInfo.value = response.data.user

        localStorage.setItem('token', response.data.tokens.access_token)
        localStorage.setItem('refreshToken', response.data.tokens.refresh_token)
        localStorage.setItem('userInfo', JSON.stringify(response.data.user))

        try {
          const { socketService } = await import('@/services/socketService.js')
          socketService.connect()
          const { useChatStore } = await import('./chat.js')
          const chatStore = useChatStore()
          chatStore.init()
        } catch (error) {
          console.error('初始化聊天服务失败:', error)
        }

        return { success: true }
      } else {
        return {
          success: false,
          message: response.message || '登录失败'
        }
      }
    } catch (error) {
      console.error('登录失败:', error)
      return {
        success: false,
        message: error.message || '网络错误，请稍后重试'
      }
    } finally {
      isLoading.value = false
    }
  }

  const register = async (userData) => {
    try {
      isLoading.value = true
      const response = await authApi.register(userData)

      if (response.success) {
        token.value = response.data.tokens.access_token
        refreshToken.value = response.data.tokens.refresh_token
        userInfo.value = response.data.user

        localStorage.setItem('token', response.data.tokens.access_token)
        localStorage.setItem('refreshToken', response.data.tokens.refresh_token)
        localStorage.setItem('userInfo', JSON.stringify(response.data.user))

        return { success: true }
      } else {
        return { success: false, message: response.message || '注册失败' }
      }
    } catch (error) {
      console.error('注册失败:', error)
      return {
        success: false,
        message: error.message || '网络错误，请稍后重试'
      }
    } finally {
      isLoading.value = false
    }
  }

  const logout = async () => {
    try {
      if (token.value) {
        await authApi.logout()
      }
    } catch (error) {
      console.error('退出登录失败:', error)
    } finally {
      token.value = ''
      refreshToken.value = ''
      userInfo.value = null

      localStorage.removeItem('token')
      localStorage.removeItem('refreshToken')
      localStorage.removeItem('userInfo')

      try {
        const { useNotificationStore } = await import('./notification')
        const notificationStore = useNotificationStore()
        notificationStore.resetUnreadCount()
      } catch (error) {
        console.error('重置未读通知数量失败:', error)
      }

      try {
        const { socketService } = await import('@/services/socketService.js')
        socketService.disconnect()
        const { useChatStore } = await import('./chat.js')
        const chatStore = useChatStore()
        chatStore.reset()
      } catch (error) {
        console.error('重置聊天状态失败:', error)
      }
    }
  }

  const initUserInfo = () => {
    const savedUserInfo = localStorage.getItem('userInfo')
    if (savedUserInfo && token.value) {
      try {
        userInfo.value = JSON.parse(savedUserInfo)
      } catch (error) {
        console.error('解析用户信息失败:', error)
        localStorage.removeItem('userInfo')
        localStorage.removeItem('token')
        localStorage.removeItem('refreshToken')
        token.value = ''
        refreshToken.value = ''
      }
    }
  }

  const refreshUserToken = async () => {
    try {
      const response = await authApi.refreshToken()
      if (response.success) {
        token.value = response.data.tokens.access_token
        localStorage.setItem('token', response.data.tokens.access_token)
        return true
      }
      return false
    } catch (error) {
      console.error('刷新token失败:', error)
      await logout()
      return false
    }
  }

  const getCurrentUser = async () => {
    try {
      const response = await authApi.getCurrentUser()

      if (response.success && response.data) {
        userInfo.value = response.data
        localStorage.setItem('userInfo', JSON.stringify(response.data))
        return response.data
      } else {
        console.error('获取当前用户信息失败:', response.message)
        return null
      }
    } catch (error) {
      console.error('获取当前用户信息失败:', error)
      return null
    }
  }

  const getUserStats = async (userId) => {
    try {
      const response = await userApi.getUserStats(userId)

      if (response.success) {
        return response.data
      } else {
        console.error('获取用户统计信息失败:', response.message)
        return null
      }
    } catch (error) {
      console.error('获取用户统计信息失败:', error)
      return null
    }
  }

  const updateUserInfo = (newUserInfo) => {
    if (userInfo.value) {
      userInfo.value = {
        ...userInfo.value,
        ...newUserInfo
      }

      localStorage.setItem('userInfo', JSON.stringify(userInfo.value))
    }
  }

  return {
    token,
    refreshToken,
    userInfo,
    isLoading,

    isLoggedIn,

    login,
    register,
    logout,
    initUserInfo,
    getCurrentUser,
    refreshUserToken,
    getUserStats,
    updateUserInfo
  }
})