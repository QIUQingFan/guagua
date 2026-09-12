<script setup>
import { ref, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { useAuthStore } from '@/stores/auth'
import { useChatStore } from '@/stores/chat'
import SessionList from './components/SessionList.vue'
import ChatWindow from './components/ChatWindow.vue'
import GroupMembersPanel from './components/GroupMembersPanel.vue'
import CreateGroupModal from './components/CreateGroupModal.vue'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()
const authStore = useAuthStore()
const chatStore = useChatStore()

const activeTargetId = ref(null)
const activeSessionType = ref(1)
const showCreateGroupModal = ref(false)

const ensureSessionForTarget = (targetId, sessionType, nickname, avatar) => {
  if (!targetId || sessionType !== 1) return
  chatStore.ensurePrivateSession(targetId, { nickname, avatar })
}

const checkLogin = () => {
  if (!userStore.isLoggedIn) {
    authStore.openLoginModal()
    return false
  }
  return true
}

const handleSessionSelect = ({ targetId, sessionType }) => {
  activeTargetId.value = targetId
  activeSessionType.value = sessionType
  chatStore.setCurrentSession(targetId, sessionType)
  const query = { targetId }
  if (sessionType === 2) {
    query.type = 'group'
  }
  router.replace({ name: 'chat', query })
}

const handleCreateGroup = () => {
  showCreateGroupModal.value = true
}

const handleGroupCreated = () => {
  chatStore.fetchGroups()
  chatStore.fetchSessions()
}

onMounted(async () => {
  if (!checkLogin()) return

  if (!chatStore.isInitialized) {
    await chatStore.init()
  }

  const targetId = route.query.targetId || route.query.userId
  const type = route.query.type === 'group' ? 2 : 1
  const nickname = route.query.nickname
  const avatar = route.query.avatar
  if (targetId) {
    activeTargetId.value = Number(targetId)
    activeSessionType.value = type
    ensureSessionForTarget(Number(targetId), type, nickname, avatar)
    chatStore.setCurrentSession(Number(targetId), type)
  }
})

watch(() => [route.query.targetId, route.query.userId, route.query.type, route.query.nickname, route.query.avatar], ([newTargetId, newUserId, newType, newNickname, newAvatar]) => {
  const id = newTargetId || newUserId
  if (id) {
    const type = newType === 'group' ? 2 : 1
    activeTargetId.value = Number(id)
    activeSessionType.value = type
    ensureSessionForTarget(Number(id), type, newNickname, newAvatar)
    chatStore.setCurrentSession(Number(id), type)
  } else {
    activeTargetId.value = null
    chatStore.currentTargetId.value = null
  }
})
</script>

<template>
  <div class="chat-page">
    <SessionList
      :active-id="activeTargetId"
      :active-type="activeSessionType"
      @select="handleSessionSelect"
      @create-group="handleCreateGroup"
    />
    <ChatWindow :target-id="activeTargetId" :session-type="activeSessionType">
      <template #members="{ groupId }">
        <GroupMembersPanel :group-id="groupId" />
      </template>
    </ChatWindow>
    <CreateGroupModal
      v-model:visible="showCreateGroupModal"
      @created="handleGroupCreated"
    />
  </div>
</template>

<style scoped>
.chat-page {
  padding-top: 72px;
  width: 100%;
  height: calc(100vh - 72px);
  display: flex;
  background: var(--bg-color-primary);
  
  overflow: hidden;
}

@media (max-width: 900px) {
  .chat-page {
    padding-top: 60px;
    height: calc(100vh - 60px);
  }
}
</style>