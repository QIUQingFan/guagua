import { defineStore } from 'pinia'
import { ref } from 'vue'

/**
 * 认证模态框状态管理
 * 集中管理登录/注册模态框的显示状态
 */
export const useAuthStore = defineStore('auth', () => {
  const showAuthModal = ref(false)
  
  const initialMode = ref('login')

  const openLoginModal = () => {
    initialMode.value = 'login'
    showAuthModal.value = true
  }

  const openRegisterModal = () => {
    initialMode.value = 'register'
    showAuthModal.value = true
  }

  const closeAuthModal = () => {
    showAuthModal.value = false
  }

  return {
    showAuthModal,
    initialMode,
    openLoginModal,
    openRegisterModal,
    closeAuthModal
  }
})