<template>
  <div v-if="visible" class="modal-overlay" v-click-outside.mousedown="handleClose" v-escape-key="handleClose">
    <div class="modal-container" @click.stop>
      <div class="modal-header">
        <h3 class="modal-title">账号与安全</h3>
        <button class="close-btn" @click="handleClose">
          <SvgIcon name="close" width="20" height="20" />
        </button>
      </div>

      <div class="modal-content">
        <div class="security-options">
          <div class="security-item" @click="handleVerification">
            <div class="item-icon">
              <SvgIcon name="verified" width="24" height="24" />
            </div>
            <div class="item-content">
              <div class="item-title">我要认证</div>
              <div class="item-desc">申请个人认证或官方认证</div>
            </div>
          </div>

          <div class="security-item" @click="handleChangePassword">
            <div class="item-icon">
              <SvgIcon name="edit" width="24" height="24" />
            </div>
            <div class="item-content">
              <div class="item-title">修改密码</div>
              <div class="item-desc">更改您的登录密码</div>
            </div>
          </div>

          <div class="security-item danger" @click="handleDeleteAccount">
            <div class="item-icon">
              <SvgIcon name="delete" width="24" height="24" />
            </div>
            <div class="item-content">
              <div class="item-title">注销账号</div>
              <div class="item-desc">永久删除您的账号和所有数据</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <ConfirmDialog v-model:visible="showDeleteModal" title="确认注销账号"
    message="注销账号将永久删除您的所有数据，包括发布的内容、评论、收藏等，此操作不可恢复。确定要继续吗？" type="error" confirm-text="确认注销" cancel-text="取消"
    @confirm="confirmDeleteAccount" @cancel="showDeleteModal = false" @update:visible="showDeleteModal = $event" />
</template>

<script setup>
import { useScrollLock } from '@/composables/useScrollLock'
import { useChangePasswordStore } from '@/stores/changePassword'
import { useVerifiedStore } from '@/stores/verified'
import { useUserStore } from '@/stores/user'
import SvgIcon from '@/components/SvgIcon.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'
import { watch, ref } from 'vue'

const props = defineProps({
  visible: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['update:visible', 'close'])

const { lock, unlock } = useScrollLock()
const changePasswordStore = useChangePasswordStore()
const verifiedStore = useVerifiedStore()
const userStore = useUserStore()
const showDeleteModal = ref(false)

const handleClose = () => {
  emit('update:visible', false)
  emit('close')
}

const handleVerification = () => {
  handleClose()
  verifiedStore.openVerifiedModal()
}

const handleChangePassword = () => {
  handleClose()
  changePasswordStore.openChangePasswordModal()
}

const handleDeleteAccount = () => {
  showDeleteModal.value = true
}

const confirmDeleteAccount = async () => {
  try {
    const response = await fetch(`/api/users/${userStore.userInfo.user_id}`, {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${userStore.token}`
      }
    })

    if (response.ok) {
      showDeleteModal.value = false
      handleClose()
      await userStore.logout()
      window.location.reload()
    } else {
      const result = await response.json()
      console.error('注销账号失败:', result.message)
    }
  } catch (error) {
    console.error('注销账号失败:', error)
  }
}

watch(() => props.visible, (newVisible) => {
  if (newVisible) {
    lock()
  } else {
    unlock()
  }
})
</script>

<style scoped>
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.21);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.modal-container {
  background: var(--bg-color-primary);
  border-radius: 12px;
  box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
  min-width: 320px;
  max-height: 90vh;
  overflow: hidden;
  border: 1px solid var(--border-color-primary);
}

.modal-header {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 20px 24px 16px;
  border-bottom: 1px solid var(--border-color-primary);
}

.modal-title {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
  color: var(--text-color-primary);
}

.close-btn {
  position: absolute;
  top: 16px;
  right: 16px;
  width: 32px;
  height: 32px;
  border: none;
  background: var(--bg-color-secondary);
  color: var(--text-color-primary);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  z-index: 1;
  transition: all 0.2s ease;
}

.close-btn:hover {
  opacity: 0.8;
  transform: scale(1.1);
}

.modal-content {
  padding: 24px;
}

.security-options {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.security-item {
  display: flex;
  align-items: center;
  padding: 16px;
  border: 1px solid var(--border-color-primary);
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.2s ease;
  background: var(--bg-color-primary);
}

.security-item:hover {
  background: var(--bg-color-secondary);
  border-color: var(--border-color-secondary);
}

.security-item.danger:hover {
  background: rgba(239, 68, 68, 0.05);
  border-color: var(--danger-color);
}

.item-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  margin-right: 16px;
  color: var(--text-color-secondary);
}

.item-content {
  flex: 1;
}

.item-title {
  font-size: 16px;
  font-weight: 500;
  color: var(--text-color-primary);
  margin-bottom: 4px;
}

.item-desc {
  font-size: 14px;
  color: var(--text-color-secondary);
}
</style>