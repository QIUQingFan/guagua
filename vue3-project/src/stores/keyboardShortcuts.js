import { defineStore } from 'pinia'
import { ref } from 'vue'

/**
 * 键盘快捷键模态框状态管理
 * 集中管理键盘快捷键模态框的显示状态
 */
export const useKeyboardShortcutsStore = defineStore('keyboardShortcuts', () => {
  const showKeyboardShortcutsModal = ref(false)

  const openKeyboardShortcutsModal = () => {
    showKeyboardShortcutsModal.value = true
  }

  const closeKeyboardShortcutsModal = () => {
    showKeyboardShortcutsModal.value = false
  }

  return {
    showKeyboardShortcutsModal,
    openKeyboardShortcutsModal,
    closeKeyboardShortcutsModal
  }
})