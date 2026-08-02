<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { useChatStore } from '@/stores/chat'
import MessageBubble from './MessageBubble.vue'
import EmptyChat from './EmptyChat.vue'
import { resolveSessionName, resolveSessionAvatar } from '@/utils/chatUserResolver.js'
import { socketService } from '@/services/socketService.js'

const router = useRouter()

const props = defineProps({
  targetId: {
    type: [Number, String],
    default: null
  },
  sessionType: {
    type: Number,
    default: 1
  }
})

const userStore = useUserStore()
const chatStore = useChatStore()

const messageInput = ref('')
const messageListRef = ref(null)
const loadingMore = ref(false)
const currentPage = ref(1)
const hasMoreHistory = ref(true)
const showMembers = ref(false)
const connStatus = ref(socketService.status)
let unsubStatus = null

const currentUserId = computed(() => userStore.userInfo?.id || 0)
const currentTargetId = computed(() => Number(props.targetId) || chatStore.currentTargetId)
const currentType = computed(() => props.sessionType || chatStore.currentSessionType)
const session = computed(() => chatStore.currentSession)
const messages = computed(() => chatStore.currentMessages)
const isGroup = computed(() => currentType.value === 2)

const chatTitle = computed(() => {
  if (isGroup.value) {
    return session.value?.target_nickname || chatStore.currentGroup?.name || '群聊'
  }
  return resolveSessionName(session.value)
})

const targetUser = computed(() => {
  return {
    nickname: isGroup.value
      ? (session.value?.target_nickname || chatStore.currentGroup?.name || '群聊')
      : resolveSessionName(session.value),
    avatar: resolveSessionAvatar(session.value, '')
  }
})

const isSelf = (message) => {
  return Number(message.from_user_id) === currentUserId.value
}

const loadHistory = async (page = 1) => {
  if (!currentTargetId.value || loadingMore.value) return
  loadingMore.value = true
  try {
    const fetcher = isGroup.value
      ? chatStore.fetchGroupHistory
      : chatStore.fetchPrivateHistory
    const result = await fetcher(currentTargetId.value, page)
    if (result.success) {
      hasMoreHistory.value = result.pagination?.hasMore !== false
      currentPage.value = page
    }
  } finally {
    loadingMore.value = false
  }
}

const isSending = ref(false)

const sendMessage = async () => {
  const content = messageInput.value.trim()
  if (!content || !currentTargetId.value || isSending.value) return
  isSending.value = true
  messageInput.value = ''
  chatStore.currentSessionType = currentType.value
  try {
    const result = await chatStore.sendMessage(currentTargetId.value, content)
    if (result.success) {
      scrollToBottom()
    }
  } finally {
    setTimeout(() => {
      isSending.value = false
    }, 300)
  }
}

const toggleMembers = () => {
  showMembers.value = !showMembers.value
}


const goToUserProfile = () => {
  if (isGroup.value || !currentTargetId.value) return
  router.push({ name: 'user_profile', params: { userId: currentTargetId.value } })
}

const headerAvatar = computed(() => resolveSessionAvatar(session.value, ''))
const defaultAvatar = new URL('@/assets/imgs/瓜呱.png', import.meta.url).href

const handleRetryMessage = async (message) => {
  if (!message || !message.content || !currentTargetId.value) return

  const messages = chatStore.messagesMap.get(currentTargetId.value) || []
  const index = messages.findIndex(m => m.id === message.id)
  if (index !== -1) {
    messages.splice(index, 1)
  }

  chatStore.currentSessionType = currentType.value
  await chatStore.sendMessage(currentTargetId.value, message.content)
  scrollToBottom()
}

const handleRecall = async (message) => {
  if (!message || !message.id || !currentTargetId.value) return
  if (!window.confirm('确定撤回这条消息吗？')) return
  chatStore.currentSessionType = currentType.value
  const result = await chatStore.recallMessage(
    currentTargetId.value,
    message.id,
    currentType.value
  )
  if (!result.success) {
    window.alert(result.message || '撤回失败')
  }
}

const handleKeydown = (event) => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault()
    sendMessage()
  }
}

const scrollToBottom = () => {
  nextTick(() => {
    if (messageListRef.value) {
      messageListRef.value.scrollTop = messageListRef.value.scrollHeight
    }
  })
}

watch(() => messages.value.length, () => {
  scrollToBottom()
})

watch([() => currentTargetId.value, () => currentType.value], ([newTargetId]) => {
  if (newTargetId) {
    currentPage.value = 1
    hasMoreHistory.value = true
    chatStore.setCurrentSession(newTargetId, currentType.value)
    loadHistory(1)
  }
}, { immediate: true })

onMounted(() => {
  scrollToBottom()
  unsubStatus = socketService.onStatusChange(status => {
    connStatus.value = status
  })
})

onUnmounted(() => {
  if (unsubStatus) {
    unsubStatus()
    unsubStatus = null
  }
})
</script>

<template>
  <div class="chat-window" v-if="currentTargetId">
    <div class="chat-header">
      <img
        v-if="!isGroup"
        :src="headerAvatar || defaultAvatar"
        class="chat-header-avatar"
        alt="头像"
        @click="goToUserProfile"
      />
      <span class="chat-title" :class="{ clickable: !isGroup }" @click="goToUserProfile">{{ chatTitle }}</span>
      <button v-if="isGroup" class="members-btn" @click="toggleMembers">
        成员
      </button>
    </div>

    <div
      v-if="connStatus === 'reconnecting' || connStatus === 'failed'"
      class="conn-banner"
      :class="{ failed: connStatus === 'failed' }"
    >
      <span v-if="connStatus === 'reconnecting'">连接已断开，正在重连...</span>
      <template v-else>
        <span>连接已断开</span>
        <button class="reconnect-btn" @click="socketService.manualReconnect()">点击重连</button>
      </template>
    </div>

    <div class="chat-body">
      <div class="message-list" ref="messageListRef">
        <div v-if="loadingMore" class="loading-more">加载中...</div>
        <MessageBubble
          v-for="message in messages"
          :key="message.id"
          :message="message"
          :is-self="isSelf(message)"
          :user-avatar="isSelf(message) ? userStore.userInfo?.avatar : (message.from_avatar || targetUser.avatar)"
          :show-nickname="isGroup"
          @retry="handleRetryMessage"
          @recall="handleRecall"
        />
        <div v-if="messages.length === 0 && !loadingMore" class="no-message">
          还没有消息，打个招呼吧～
        </div>
      </div>

      <div v-if="showMembers && isGroup" class="member-panel">
        <slot name="members" :group-id="currentTargetId" />
      </div>
    </div>

    <div class="chat-input-area">
      <textarea
        v-model="messageInput"
        class="message-input"
        placeholder="输入消息..."
        rows="3"
        @keydown="handleKeydown"
      />
      <button
        class="send-btn"
        :disabled="!messageInput.trim() || isSending"
        :class="{ sending: isSending }"
        @click="sendMessage"
      >
        {{ isSending ? '发送中...' : '发送' }}
      </button>
    </div>
  </div>

  <EmptyChat v-else />
</template>

<style scoped>
.chat-window {
  flex: 1;
  display: flex;
  flex-direction: column;
  height: 100%;
  background: var(--bg-color-primary);
  
  min-width: 0;
}

.chat-header {
  height: 60px;
  padding: 0 20px;
  display: flex;
  align-items: center;
  gap: 10px;
  border-bottom: 1px solid var(--border-color-primary);
  flex-shrink: 0;
}

.chat-header-avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  object-fit: cover;
  cursor: pointer;
  flex-shrink: 0;
  background: var(--bg-color-secondary);
  transition: opacity 0.2s ease;
}

.chat-header-avatar:hover {
  opacity: 0.8;
}

.conn-banner {
  padding: 6px 16px;
  text-align: center;
  font-size: 12px;
  color: #fff;
  background: #e6a23c;
  flex-shrink: 0;
}

.conn-banner.failed {
  background: #f56c6c;
}

.reconnect-btn {
  margin-left: 8px;
  padding: 1px 10px;
  border: none;
  border-radius: 10px;
  background: #fff;
  color: #f56c6c;
  font-size: 12px;
  cursor: pointer;
}

.reconnect-btn:hover {
  opacity: 0.85;
}

.chat-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--text-color-primary);
}

.chat-title.clickable {
  cursor: pointer;
}

.chat-title.clickable:hover {
  opacity: 0.8;
}

.members-btn {
  padding: 4px 12px;
  border: 1px solid var(--border-color-secondary);
  border-radius: 14px;
  background: var(--bg-color-secondary);
  color: var(--text-color-primary);
  font-size: 12px;
  cursor: pointer;
}

.members-btn:hover {
  border-color: var(--primary-color);
  color: var(--primary-color);
}

.chat-body {
  flex: 1;
  display: flex;
  overflow: hidden;
  
  min-width: 0;
}

.member-panel {
  width: 220px;
  border-left: 1px solid var(--border-color-primary);
  background: var(--bg-color-secondary);
  flex-shrink: 0;
  overflow-y: auto;
}

.message-list {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  
  min-width: 0;
}

.loading-more {
  text-align: center;
  padding: 12px;
  color: var(--text-color-tertiary);
  font-size: 12px;
}

.no-message {
  text-align: center;
  padding: 40px;
  color: var(--text-color-tertiary);
  font-size: 14px;
}

.chat-input-area {
  padding: 12px 20px 20px;
  border-top: 1px solid var(--border-color-primary);
  display: flex;
  gap: 12px;
  flex-shrink: 0;
}

.message-input {
  flex: 1;
  resize: none;
  border: 1px solid var(--border-color-secondary);
  border-radius: 8px;
  padding: 10px 12px;
  font-size: 14px;
  line-height: 1.5;
  color: var(--text-color-primary);
  background: var(--bg-color-primary);
  outline: none;
}

.message-input:focus {
  border-color: var(--primary-color);
}

.send-btn {
  width: 80px;
  border: none;
  border-radius: 8px;
  background: var(--primary-color);
  color: #fff;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: background 0.2s;
}

.send-btn:hover:not(:disabled) {
  background: var(--primary-color-dark);
}

.send-btn:disabled {
  background: var(--disabled-bg);
  cursor: not-allowed;
}
</style>