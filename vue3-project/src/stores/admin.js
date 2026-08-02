import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { adminApi } from '@/api'

export const useAdminStore = defineStore('admin', () => {
  const admin = ref(null)
  const token = ref(localStorage.getItem('admin_token') || '')
  const refreshToken = ref(localStorage.getItem('admin_refresh_token') || '')

  const isLoggedIn = computed(() => !!admin.value && !!token.value)

  
  const role = computed(() => admin.value?.role || 'super_admin')

  
  const hasRole = (...roles) => roles.includes(role.value)

  const login = async (credentials) => {
    try {
      const response = await adminApi.login(credentials)

      if (response.success && response.data) {
        admin.value = response.data.admin
        token.value = response.data.tokens.access_token
        refreshToken.value = response.data.tokens.refresh_token

        localStorage.setItem('admin_token', token.value)
        localStorage.setItem('admin_refresh_token', refreshToken.value)
        localStorage.setItem('admin_info', JSON.stringify(admin.value))

        return { success: true, message: response.message }
      } else {
        return { success: false, message: response.message || '登录失败' }
      }
    } catch (error) {
      console.error('管理员登录失败:', error)

      let errorMessage = '登录失败，请稍后重试'
      if (error.response?.data?.message) {
        errorMessage = error.response.data.message
      } else if (error.message) {
        errorMessage = error.message
      }

      return { success: false, message: errorMessage }
    }
  }

  const logout = async () => {
    try {
      admin.value = null
      token.value = ''
      refreshToken.value = ''

      localStorage.removeItem('admin_token')
      localStorage.removeItem('admin_refresh_token')
      localStorage.removeItem('admin_info')

    } catch (error) {
      console.error('管理员退出登录失败:', error)
    }
  }

  const getCurrentAdmin = async () => {
    try {
      if (!token.value) {
        throw new Error('未登录')
      }

      const response = await adminApi.getCurrentAdmin()

      if (response.success && response.data) {
        admin.value = response.data
        localStorage.setItem('admin_info', JSON.stringify(admin.value))
        return { success: true, data: response.data }
      } else {
        throw new Error(response.message || '获取管理员信息失败')
      }
    } catch (error) {
      console.error('获取管理员信息失败:', error)

      if (error.response?.status === 401) {
        await logout()
      }

      return { success: false, message: error.message }
    }
  }

  const initializeAdmin = () => {
    try {
      const storedAdminInfo = localStorage.getItem('admin_info')
      if (storedAdminInfo && token.value) {
        admin.value = JSON.parse(storedAdminInfo)
      }
    } catch (error) {
      console.error('恢复管理员信息失败:', error)
      logout()
    }
  }

  const checkTokenValidity = async () => {
    if (!token.value) return false

    try {
      const result = await getCurrentAdmin()
      return result.success
    } catch (error) {
      return false
    }
  }

  return {
    admin,
    token,
    refreshToken,

    isLoggedIn,
    role,
    hasRole,

    login,
    logout,
    getCurrentAdmin,
    initializeAdmin,
    checkTokenValidity
  }
})