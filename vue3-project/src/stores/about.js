import { defineStore } from 'pinia'
import { ref } from 'vue'

/**
 * 关于模态框状态管理
 * 集中管理关于瓜呱模态框的显示状态
 */
export const useAboutStore = defineStore('about', () => {
  const showAboutModal = ref(false)

  const openAboutModal = () => {
    showAboutModal.value = true
  }

  const closeAboutModal = () => {
    showAboutModal.value = false
  }

  return {
    showAboutModal,
    openAboutModal,
    closeAboutModal
  }
})