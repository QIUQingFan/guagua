import { defineStore } from 'pinia'
import { ref } from 'vue'

/**
 * 修改密码模态框状态管理
 * 集中管理修改密码模态框的显示状态
 */
export const useChangePasswordStore = defineStore('changePassword', () => {
  const showChangePasswordModal = ref(false)

  const openChangePasswordModal = () => {
    showChangePasswordModal.value = true
  }

  const closeChangePasswordModal = () => {
    showChangePasswordModal.value = false
  }

  return {
    showChangePasswordModal,
    openChangePasswordModal,
    closeChangePasswordModal
  }
})