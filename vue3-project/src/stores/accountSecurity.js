import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useAccountSecurityStore = defineStore('accountSecurity', () => {
  const showAccountSecurityModal = ref(false)
  const openAccountSecurityModal = () => {
    showAccountSecurityModal.value = true
  }
  const closeAccountSecurityModal = () => {
    showAccountSecurityModal.value = false
  }
  return {
    showAccountSecurityModal,
    openAccountSecurityModal,
    closeAccountSecurityModal
  }
})