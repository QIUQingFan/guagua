<script setup>
import { ref, onMounted, computed } from 'vue'
import { useUserStore } from '@/stores/user'
import { useChatStore } from '@/stores/chat'
import { getGroupMembers, removeGroupMember, dissolveChatGroup, inviteGroupMember } from '@/api/chat.js'
import { userApi } from '@/api/index.js'
import SvgIcon from '@/components/SvgIcon.vue'
import ConfirmDialog from '@/components/ConfirmDialog.vue'

const props = defineProps({
  groupId: {
    type: Number,
    required: true
  }
})

const emit = defineEmits(['dissolved'])

const userStore = useUserStore()
const chatStore = useChatStore()

const members = ref([])
const isLoading = ref(false)
const showDissolveConfirm = ref(false)
const memberToRemove = ref(null)
const showRemoveConfirm = ref(false)

const showInviteModal = ref(false)
const inviteKeyword = ref('')
const inviteSearchResults = ref([])
const inviteLoading = ref(false)
const inviteSearchTimer = ref(null)

const currentUserId = computed(() => userStore.userInfo?.id || 0)
const currentGroup = computed(() => chatStore.groups.find(g => g.id === props.groupId))
const isOwner = computed(() => currentGroup.value?.owner_id === currentUserId.value)

const owner = computed(() => members.value.find(m => m.role === 1))
const normalMembers = computed(() => members.value.filter(m => m.role === 2))

const defaultAvatar = new URL('@/assets/imgs/瓜呱.png', import.meta.url).href

const fetchMembers = async () => {
  isLoading.value = true
  try {
    const response = await getGroupMembers(props.groupId)
    if (response.success) {
      members.value = response.data || []
    }
  } catch (error) {
    console.error('获取群成员失败:', error)
  } finally {
    isLoading.value = false
  }
}

const confirmRemove = (member) => {
  memberToRemove.value = member
  showRemoveConfirm.value = true
}

const handleRemove = async () => {
  if (!memberToRemove.value) return
  try {
    const response = await removeGroupMember(props.groupId, memberToRemove.value.id)
    if (response.success) {
      members.value = members.value.filter(m => m.id !== memberToRemove.value.id)
      memberToRemove.value = null
    }
  } catch (error) {
    console.error('移除成员失败:', error)
  } finally {
    showRemoveConfirm.value = false
  }
}

const confirmDissolve = () => {
  showDissolveConfirm.value = true
}

const handleDissolve = async () => {
  try {
    const response = await dissolveChatGroup(props.groupId)
    if (response.success) {
      chatStore.groups = chatStore.groups.filter(g => g.id !== props.groupId)
      chatStore.sessions = chatStore.sessions.filter(s => !(s.session_type === 2 && s.target_id === props.groupId))
      emit('dissolved', props.groupId)
    }
  } catch (error) {
    console.error('解散群聊失败:', error)
  } finally {
    showDissolveConfirm.value = false
  }
}

const openInviteModal = () => {
  showInviteModal.value = true
  inviteKeyword.value = ''
  inviteSearchResults.value = []
}

const closeInviteModal = () => {
  showInviteModal.value = false
  inviteKeyword.value = ''
  inviteSearchResults.value = []
  if (inviteSearchTimer.value) {
    clearTimeout(inviteSearchTimer.value)
  }
}

const handleInviteSearchInput = () => {
  if (inviteSearchTimer.value) {
    clearTimeout(inviteSearchTimer.value)
  }
  inviteSearchTimer.value = setTimeout(() => {
    searchInviteUsers()
  }, 300)
}

const searchInviteUsers = async () => {
  const keyword = inviteKeyword.value.trim()
  if (!keyword) {
    inviteSearchResults.value = []
    return
  }
  inviteLoading.value = true
  try {
    const response = await userApi.searchUsers(keyword, { limit: 10 })
    if (response.success && response.data && response.data.users) {
      const memberIds = new Set(members.value.map(m => m.id))
      const currentUserId = userStore.userInfo?.id
      inviteSearchResults.value = response.data.users.filter(user => {
        return user.id !== currentUserId && !memberIds.has(user.id)
      })
    } else {
      inviteSearchResults.value = []
    }
  } catch (error) {
    console.error('搜索用户失败:', error)
    inviteSearchResults.value = []
  } finally {
    inviteLoading.value = false
  }
}

const handleInvite = async (user) => {
  if (!user || !user.id) return
  try {
    const response = await inviteGroupMember(props.groupId, user.id)
    if (response.success) {
      await fetchMembers()
      closeInviteModal()
    }
  } catch (error) {
    console.error('邀请成员失败:', error)
  }
}

onMounted(() => {
  fetchMembers()
})
</script>

<template>
  <div class="group-members-panel">
    <div class="panel-header">
      <h4 class="panel-title">群成员（{{ members.length }}）</h4>
      <button v-if="isOwner" class="invite-btn" @click="openInviteModal">
        邀请
      </button>
    </div>

    <div v-if="isLoading" class="panel-loading">加载中...</div>

    <div v-else class="member-list">
      <div v-if="owner" class="member-item owner">
        <img :src="owner.avatar || defaultAvatar" class="member-avatar" alt="头像" v-img-fallback="avatar" />
        <span class="member-name">{{ owner.nickname || `用户${owner.id}` }}</span>
        <span class="role-tag">群主</span>
      </div>

      <div
        v-for="member in normalMembers"
        :key="member.id"
        class="member-item"
      >
        <img :src="member.avatar || defaultAvatar" class="member-avatar" alt="头像" v-img-fallback="avatar" />
        <span class="member-name">{{ member.nickname || `用户${member.id}` }}</span>
        <button
          v-if="isOwner"
          class="remove-btn"
          @click="confirmRemove(member)"
        >
          移除
        </button>
      </div>
    </div>

    <div v-if="isOwner" class="panel-footer">
      <button class="dissolve-btn" @click="confirmDissolve">
        解散群聊
      </button>
    </div>

    <ConfirmDialog
      v-model:visible="showRemoveConfirm"
      title="移除成员"
      :message="`确定要将 ${memberToRemove?.nickname || '该成员'} 移出群聊吗？`"
      @confirm="handleRemove"
    />

    <ConfirmDialog
      v-model:visible="showDissolveConfirm"
      title="解散群聊"
      message="解散后群聊记录将被删除，确定要解散该群聊吗？"
      @confirm="handleDissolve"
    />

    <div v-if="showInviteModal" class="invite-modal-overlay" @click.self="closeInviteModal">
      <div class="invite-modal">
        <div class="invite-modal-header">
          <h4>邀请成员</h4>
          <button class="close-btn" @click="closeInviteModal">
            <SvgIcon name="close" width="16" height="16" />
          </button>
        </div>
        <div class="invite-modal-body">
          <input
            v-model="inviteKeyword"
            type="text"
            class="invite-search-input"
            placeholder="搜索用户昵称或ID"
            @input="handleInviteSearchInput"
          />
          <div v-if="inviteLoading" class="invite-loading">搜索中...</div>
          <div v-else-if="inviteSearchResults.length === 0 && inviteKeyword.trim()" class="invite-empty">
            未找到用户
          </div>
          <div v-else class="invite-user-list">
            <div
              v-for="user in inviteSearchResults"
              :key="user.id"
              class="invite-user-item"
              @click="handleInvite(user)"
            >
              <img :src="user.avatar || defaultAvatar" class="invite-user-avatar" alt="头像" v-img-fallback="avatar" />
              <span class="invite-user-name">{{ user.nickname || `用户${user.id}` }}</span>
              <button class="invite-confirm-btn" @click.stop="handleInvite(user)">邀请</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.group-members-panel {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.panel-header {
  padding: 16px;
  border-bottom: 1px solid var(--border-color-primary);
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.invite-btn {
  padding: 4px 12px;
  border: none;
  border-radius: 12px;
  background: var(--primary-color);
  color: #fff;
  font-size: 12px;
  cursor: pointer;
}

.panel-title {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
  color: var(--text-color-primary);
}

.panel-loading {
  padding: 20px;
  text-align: center;
  color: var(--text-color-tertiary);
}

.member-list {
  flex: 1;
  overflow-y: auto;
  padding: 8px;
}

.member-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px;
  border-radius: 8px;
  transition: background 0.2s;
}

.member-item:hover {
  background: var(--bg-color-secondary);
}

.member-item.owner {
  background: var(--primary-color-light, rgba(64, 158, 255, 0.08));
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
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.role-tag {
  padding: 2px 8px;
  border-radius: 10px;
  background: var(--primary-color);
  color: #fff;
  font-size: 11px;
}

.remove-btn {
  padding: 2px 10px;
  border: 1px solid var(--danger-color);
  border-radius: 10px;
  background: transparent;
  color: var(--danger-color);
  font-size: 12px;
  cursor: pointer;
}

.panel-footer {
  padding: 16px;
  border-top: 1px solid var(--border-color-primary);
}

.dissolve-btn {
  width: 100%;
  padding: 10px;
  border: none;
  border-radius: 8px;
  background: var(--danger-color);
  color: #fff;
  font-size: 14px;
  cursor: pointer;
}

.invite-modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}

.invite-modal {
  width: 360px;
  max-width: 90vw;
  background: var(--bg-color-primary);
  border-radius: 12px;
  overflow: hidden;
}

.invite-modal-header {
  padding: 16px;
  border-bottom: 1px solid var(--border-color-primary);
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.invite-modal-header h4 {
  margin: 0;
  font-size: 16px;
}

.invite-modal-header .close-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  color: var(--text-color-secondary);
}

.invite-modal-body {
  padding: 16px;
  max-height: 400px;
  overflow-y: auto;
}

.invite-search-input {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid var(--border-color-secondary);
  border-radius: 8px;
  font-size: 14px;
  outline: none;
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
}

.invite-loading,
.invite-empty {
  padding: 20px;
  text-align: center;
  color: var(--text-color-tertiary);
  font-size: 14px;
}

.invite-user-list {
  margin-top: 12px;
}

.invite-user-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px;
  border-radius: 8px;
  cursor: pointer;
  transition: background 0.2s;
}

.invite-user-item:hover {
  background: var(--bg-color-secondary);
}

.invite-user-avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  object-fit: cover;
}

.invite-user-name {
  flex: 1;
  font-size: 14px;
  color: var(--text-color-primary);
}

.invite-confirm-btn {
  padding: 4px 12px;
  border: none;
  border-radius: 10px;
  background: var(--primary-color);
  color: #fff;
  font-size: 12px;
  cursor: pointer;
}
</style>