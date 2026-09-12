<script setup>
import { ref, reactive, onMounted, computed } from 'vue'
import { useUserStore } from '@/stores/user'
import { useChatStore } from '@/stores/chat'
import { getGroupMembers, removeGroupMember, dissolveChatGroup, inviteGroupMember, getGroupInviteCandidates } from '@/api/chat.js'
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

// 邀请候选（最近聊天 / 关注对象）
const inviteTab = ref('chat')
const inviteCandidates = ref([])
const inviteCandidatesLoading = ref(false)

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

const chatCandidates = computed(() => inviteCandidates.value.filter(c => c.sources.includes('chat')))
const followCandidates = computed(() => inviteCandidates.value.filter(c => c.sources.includes('follow')))

const openInviteModal = async () => {
  showInviteModal.value = true
  inviteKeyword.value = ''
  inviteSearchResults.value = []
  inviteTab.value = 'chat'
  await fetchInviteCandidates()
}

const closeInviteModal = () => {
  showInviteModal.value = false
  inviteKeyword.value = ''
  inviteSearchResults.value = []
  if (inviteSearchTimer.value) {
    clearTimeout(inviteSearchTimer.value)
  }
}

const fetchInviteCandidates = async () => {
  inviteCandidatesLoading.value = true
  try {
    const response = await getGroupInviteCandidates(props.groupId)
    if (response.success) {
      inviteCandidates.value = response.data || []
    } else {
      inviteCandidates.value = []
    }
  } catch (error) {
    console.error('获取邀请候选失败:', error)
    inviteCandidates.value = []
  } finally {
    inviteCandidatesLoading.value = false
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

// ---------- 群设置（仅群主） ----------
const showSettingsModal = ref(false)
const settingsForm = reactive({
  name: '',
  description: '',
  avatar: '',
  announcement: ''
})
const settingsSaving = ref(false)

const openSettingsModal = () => {
  const group = currentGroup.value || {}
  settingsForm.name = group.name || ''
  settingsForm.description = group.description || ''
  settingsForm.avatar = group.avatar || ''
  settingsForm.announcement = group.announcement || ''
  showSettingsModal.value = true
}

const closeSettingsModal = () => {
  showSettingsModal.value = false
}

const saveSettings = async () => {
  if (!settingsForm.name.trim()) {
    window.alert('群名称不能为空')
    return
  }
  settingsSaving.value = true
  try {
    const payload = {
      name: settingsForm.name.trim()
    }
    if (settingsForm.description !== (currentGroup.value?.description || '')) {
      payload.description = settingsForm.description
    }
    if (settingsForm.avatar !== (currentGroup.value?.avatar || '')) {
      payload.avatar = settingsForm.avatar || null
    }
    const infoResult = await chatStore.updateGroupInfo(props.groupId, payload)
    if (!infoResult.success) {
      window.alert(infoResult.message || '更新群信息失败')
      return
    }
    if (settingsForm.announcement !== (currentGroup.value?.announcement || '')) {
      const annResult = await chatStore.saveGroupAnnouncement(props.groupId, settingsForm.announcement)
      if (!annResult.success) {
        window.alert(annResult.message || '更新群公告失败')
        return
      }
    }
    await fetchGroups()
    closeSettingsModal()
  } catch (error) {
    console.error('保存群设置失败:', error)
    window.alert('保存失败，请重试')
  } finally {
    settingsSaving.value = false
  }
}

const fetchGroups = async () => {
  await chatStore.fetchGroups()
}

onMounted(() => {
  fetchMembers()
})
</script>

<template>
  <div class="group-members-panel">
    <div class="panel-header">
      <h4 class="panel-title">群成员（{{ members.length }}）</h4>
      <div class="panel-header-actions">
        <button v-if="isOwner" class="settings-btn" @click="openSettingsModal">
          群设置
        </button>
        <button v-if="isOwner" class="invite-btn" @click="openInviteModal">
          邀请
        </button>
      </div>
    </div>

    <div v-if="isLoading" class="panel-loading">加载中...</div>

    <div v-else class="member-list">
      <div v-if="owner" class="member-item owner">
        <img :src="owner.avatar || defaultAvatar" class="member-avatar" alt="头像" v-img-fallback="'avatar'" />
        <span class="member-name">{{ owner.nickname || `用户${owner.id}` }}</span>
        <span class="role-tag">群主</span>
      </div>

      <div
        v-for="member in normalMembers"
        :key="member.id"
        class="member-item"
      >
        <img :src="member.avatar || defaultAvatar" class="member-avatar" alt="头像" v-img-fallback="'avatar'" />
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
          <div class="invite-tabs">
            <button
              class="invite-tab"
              :class="{ active: inviteTab === 'search' }"
              @click="inviteTab = 'search'"
            >
              搜索
            </button>
            <button
              class="invite-tab"
              :class="{ active: inviteTab === 'chat' }"
              @click="inviteTab = 'chat'"
            >
              最近聊天
            </button>
            <button
              class="invite-tab"
              :class="{ active: inviteTab === 'follow' }"
              @click="inviteTab = 'follow'"
            >
              我的关注
            </button>
          </div>

          <div v-if="inviteTab === 'search'" class="invite-tab-panel">
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
                <img :src="user.avatar || defaultAvatar" class="invite-user-avatar" alt="头像" v-img-fallback="'avatar'" />
                <span class="invite-user-name">{{ user.nickname || `用户${user.id}` }}</span>
                <button class="invite-confirm-btn" @click.stop="handleInvite(user)">邀请</button>
              </div>
            </div>
          </div>

          <div v-else class="invite-tab-panel">
            <div v-if="inviteCandidatesLoading" class="invite-loading">加载中...</div>
            <div v-else-if="(inviteTab === 'chat' ? chatCandidates : followCandidates).length === 0" class="invite-empty">
              {{ inviteTab === 'chat' ? '暂无最近聊天的用户' : '暂未关注任何用户' }}
            </div>
            <div v-else class="invite-user-list">
              <div
                v-for="user in (inviteTab === 'chat' ? chatCandidates : followCandidates)"
                :key="user.id"
                class="invite-user-item"
                @click="handleInvite(user)"
              >
                <img :src="user.avatar || defaultAvatar" class="invite-user-avatar" alt="头像" v-img-fallback="'avatar'" />
                <span class="invite-user-name">{{ user.nickname || `用户${user.id}` }}</span>
                <button class="invite-confirm-btn" @click.stop="handleInvite(user)">邀请</button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div v-if="showSettingsModal" class="settings-modal-overlay" @click.self="closeSettingsModal">
      <div class="settings-modal">
        <div class="settings-modal-header">
          <h4>群设置</h4>
          <button class="close-btn" @click="closeSettingsModal">
            <SvgIcon name="close" width="16" height="16" />
          </button>
        </div>
        <div class="settings-modal-body">
          <div class="settings-field">
            <label class="settings-label">群名称</label>
            <input
              v-model="settingsForm.name"
              type="text"
              class="settings-input"
              maxlength="100"
              placeholder="请输入群名称"
            />
          </div>
          <div class="settings-field">
            <label class="settings-label">群简介</label>
            <textarea
              v-model="settingsForm.description"
              class="settings-input settings-textarea"
              rows="2"
              maxlength="500"
              placeholder="介绍一下这个群吧（可选）"
            ></textarea>
          </div>
          <div class="settings-field">
            <label class="settings-label">群头像URL</label>
            <input
              v-model="settingsForm.avatar"
              type="text"
              class="settings-input"
              placeholder="留空则使用成员头像拼图"
            />
            <div class="settings-hint">留空时群头像将自动使用群成员头像拼图</div>
          </div>
          <div class="settings-field">
            <label class="settings-label">群公告</label>
            <textarea
              v-model="settingsForm.announcement"
              class="settings-input settings-textarea"
              rows="3"
              maxlength="500"
              placeholder="填写后群聊顶部将展示公告（可选）"
            ></textarea>
          </div>
        </div>
        <div class="settings-modal-footer">
          <button class="cancel-btn" @click="closeSettingsModal">取消</button>
          <button class="save-btn" :disabled="settingsSaving" @click="saveSettings">
            {{ settingsSaving ? '保存中...' : '保存' }}
          </button>
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

.invite-tabs {
  display: flex;
  gap: 8px;
  margin-bottom: 12px;
  padding-bottom: 10px;
  border-bottom: 1px solid var(--border-color-primary);
}

.invite-tab {
  padding: 5px 14px;
  border: none;
  border-radius: 14px;
  background: var(--bg-color-secondary);
  color: var(--text-color-secondary);
  font-size: 13px;
  cursor: pointer;
  transition: background 0.2s, color 0.2s;
}

.invite-tab:hover {
  color: var(--primary-color);
}

.invite-tab.active {
  background: var(--primary-color);
  color: #fff;
}

.invite-tab-panel {
  min-height: 120px;
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

.panel-header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.settings-btn {
  padding: 4px 12px;
  border: 1px solid var(--border-color-secondary);
  border-radius: 12px;
  background: var(--bg-color-secondary);
  color: var(--text-color-primary);
  font-size: 12px;
  cursor: pointer;
  transition: border-color 0.2s, color 0.2s;
}

.settings-btn:hover {
  border-color: var(--primary-color);
  color: var(--primary-color);
}

.settings-modal-overlay {
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

.settings-modal {
  width: 400px;
  max-width: 90vw;
  background: var(--bg-color-primary);
  border-radius: 12px;
  overflow: hidden;
}

.settings-modal-header {
  padding: 16px;
  border-bottom: 1px solid var(--border-color-primary);
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.settings-modal-header h4 {
  margin: 0;
  font-size: 16px;
}

.settings-modal-body {
  padding: 16px;
  max-height: 60vh;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.settings-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.settings-label {
  font-size: 13px;
  font-weight: 500;
  color: var(--text-color-secondary);
}

.settings-input {
  width: 100%;
  box-sizing: border-box;
  padding: 10px 12px;
  border: 1px solid var(--border-color-secondary);
  border-radius: 8px;
  font-size: 14px;
  outline: none;
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
  font-family: inherit;
}

.settings-input:focus {
  border-color: var(--primary-color);
}

.settings-textarea {
  resize: vertical;
  line-height: 1.5;
}

.settings-hint {
  font-size: 12px;
  color: var(--text-color-tertiary);
}

.settings-modal-footer {
  padding: 14px 16px;
  border-top: 1px solid var(--border-color-primary);
  display: flex;
  justify-content: flex-end;
  gap: 10px;
}

.cancel-btn {
  padding: 8px 18px;
  border: 1px solid var(--border-color-secondary);
  border-radius: 8px;
  background: var(--bg-color-secondary);
  color: var(--text-color-primary);
  font-size: 14px;
  cursor: pointer;
}

.save-btn {
  padding: 8px 18px;
  border: none;
  border-radius: 8px;
  background: var(--primary-color);
  color: #fff;
  font-size: 14px;
  cursor: pointer;
  transition: background 0.2s;
}

.save-btn:hover:not(:disabled) {
  background: var(--primary-color-dark);
}

.save-btn:disabled {
  background: var(--disabled-bg);
  cursor: not-allowed;
}
</style>