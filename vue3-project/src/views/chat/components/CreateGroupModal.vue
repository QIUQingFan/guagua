<script setup>
import { ref, computed } from 'vue'
import { useUserStore } from '@/stores/user'
import { useChatStore } from '@/stores/chat'
import SvgIcon from '@/components/SvgIcon.vue'

const props = defineProps({
  visible: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['update:visible', 'created'])

const userStore = useUserStore()
const chatStore = useChatStore()

const groupName = ref('')
const groupDescription = ref('')
const selectedMemberIds = ref([])
const searchKeyword = ref('')
const isCreating = ref(false)

const defaultAvatar = new URL('@/assets/imgs/瓜呱.png', import.meta.url).href

const followings = computed(() => userStore.followings || [])

const filteredFollowings = computed(() => {
  if (!searchKeyword.value.trim()) return followings.value
  const keyword = searchKeyword.value.trim().toLowerCase()
  return followings.value.filter(user =>
    (user.nickname || '').toLowerCase().includes(keyword)
  )
})

const canCreate = computed(() => {
  return groupName.value.trim().length > 0 &&
    selectedMemberIds.value.length >= 1 &&
    !isCreating.value
})

const toggleMember = (userId) => {
  const index = selectedMemberIds.value.indexOf(userId)
  if (index > -1) {
    selectedMemberIds.value.splice(index, 1)
  } else {
    selectedMemberIds.value.push(userId)
  }
}

const isSelected = (userId) => selectedMemberIds.value.includes(userId)

const closeModal = () => {
  emit('update:visible', false)
}

const handleCreate = async () => {
  if (!canCreate.value) return

  isCreating.value = true
  try {
    const response = await chatStore.createGroup(
      groupName.value.trim(),
      groupDescription.value.trim(),
      selectedMemberIds.value
    )

    if (response.success) {
      groupName.value = ''
      groupDescription.value = ''
      selectedMemberIds.value = []
      emit('created', response.data)
      closeModal()
    }
  } finally {
    isCreating.value = false
  }
}

const handleOverlayClick = () => {
  closeModal()
}
</script>

<template>
  <Teleport to="body">
    <div v-if="visible" class="modal-overlay" @click.self="handleOverlayClick">
      <div class="modal-container">
        <div class="modal-header">
          <h3 class="modal-title">创建群聊</h3>
          <button class="close-btn" @click="closeModal" aria-label="关闭">
            <SvgIcon name="close" width="20" height="20" />
          </button>
        </div>

        <div class="modal-body">
          <div class="form-group">
            <label class="form-label">群名称</label>
            <input
              v-model="groupName"
              type="text"
              class="form-input"
              placeholder="请输入群名称"
              maxlength="100"
            />
          </div>

          <div class="form-group">
            <label class="form-label">群简介（可选）</label>
            <textarea
              v-model="groupDescription"
              class="form-textarea"
              placeholder="请输入群简介"
              rows="3"
            />
          </div>

          <div class="form-group">
            <label class="form-label">
              选择成员（已选 {{ selectedMemberIds.length }} 人）
            </label>
            <input
              v-model="searchKeyword"
              type="text"
              class="form-input"
              placeholder="搜索关注的人"
            />
            <div class="member-list">
              <div
                v-for="user in filteredFollowings"
                :key="user.id"
                class="member-item"
                :class="{ selected: isSelected(user.id) }"
                @click="toggleMember(user.id)"
              >
                <img :src="user.avatar || defaultAvatar" class="member-avatar" alt="头像" v-img-fallback="avatar" />
                <span class="member-name">{{ user.nickname || `用户${user.id}` }}</span>
                <span v-if="isSelected(user.id)" class="selected-mark">✓</span>
              </div>
              <div v-if="filteredFollowings.length === 0" class="empty-members">
                没有可选成员
              </div>
            </div>
          </div>
        </div>

        <div class="modal-footer">
          <button class="cancel-btn" @click="closeModal">取消</button>
          <button
            class="create-btn"
            :disabled="!canCreate"
            @click="handleCreate"
          >
            {{ isCreating ? '创建中...' : '创建' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.modal-container {
  width: 90%;
  max-width: 480px;
  max-height: 80vh;
  background: var(--bg-color-primary);
  border-radius: 16px;
  display: flex;
  flex-direction: column;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.15);
}

.modal-header {
  padding: 16px 20px;
  border-bottom: 1px solid var(--border-color-primary);
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.modal-title {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
  color: var(--text-color-primary);
}

.close-btn {
  width: 32px;
  height: 32px;
  border: none;
  background: transparent;
  color: var(--text-color-secondary);
  cursor: pointer;
  padding: 0;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  transition: background-color 0.2s, color 0.2s;
}

.close-btn:hover {
  background: var(--bg-color-secondary);
  color: var(--text-color-primary);
}

.close-btn :deep(svg) {
  width: 20px;
  height: 20px;
}

.modal-body {
  padding: 20px;
  overflow-y: auto;
  flex: 1;
}

.form-group {
  margin-bottom: 16px;
}

.form-label {
  display: block;
  font-size: 14px;
  font-weight: 500;
  color: var(--text-color-primary);
  margin-bottom: 8px;
}

.form-input,
.form-textarea {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid var(--border-color-secondary);
  border-radius: 8px;
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
  font-size: 14px;
  outline: none;
  box-sizing: border-box;
}

.form-input:focus,
.form-textarea:focus {
  border-color: var(--primary-color);
}

.member-list {
  margin-top: 12px;
  max-height: 200px;
  overflow-y: auto;
  border: 1px solid var(--border-color-secondary);
  border-radius: 8px;
}

.member-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 12px;
  cursor: pointer;
  transition: background 0.2s;
}

.member-item:hover {
  background: var(--bg-color-secondary);
}

.member-item.selected {
  background: var(--primary-color-light, rgba(64, 158, 255, 0.1));
}

.member-avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  object-fit: cover;
}

.member-name {
  flex: 1;
  font-size: 14px;
  color: var(--text-color-primary);
}

.selected-mark {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  background: var(--primary-color);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
}

.empty-members {
  padding: 20px;
  text-align: center;
  color: var(--text-color-tertiary);
  font-size: 13px;
}

.modal-footer {
  padding: 16px 20px;
  border-top: 1px solid var(--border-color-primary);
  display: flex;
  justify-content: flex-end;
  gap: 12px;
}

.cancel-btn,
.create-btn {
  padding: 8px 20px;
  border-radius: 8px;
  font-size: 14px;
  cursor: pointer;
  transition: all 0.2s;
}

.cancel-btn {
  border: 1px solid var(--border-color-secondary);
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
}

.create-btn {
  border: none;
  background: var(--primary-color);
  color: #fff;
}

.create-btn:disabled {
  background: var(--disabled-bg);
  cursor: not-allowed;
}
</style>