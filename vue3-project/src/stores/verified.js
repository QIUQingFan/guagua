import { defineStore } from 'pinia'
import { ref } from 'vue'

/**
 * 认证模态框状态管理
 * 集中管理认证模态框的显示状态
 */
export const useVerifiedStore = defineStore('verified', () => {
  const showVerifiedModal = ref(false)

  const openVerifiedModal = () => {
    showVerifiedModal.value = true
  }

  const closeVerifiedModal = () => {
    showVerifiedModal.value = false
  }

  return {
    showVerifiedModal,
    openVerifiedModal,
    closeVerifiedModal
  }
})