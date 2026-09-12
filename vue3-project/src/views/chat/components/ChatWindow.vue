<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'
import { useChatStore } from '@/stores/chat'
import MessageBubble from './MessageBubble.vue'
import EmptyChat from './EmptyChat.vue'
import GroupAvatar from './GroupAvatar.vue'
import { resolveSessionName, resolveSessionAvatar, resolveSenderName } from '@/utils/chatUserResolver.js'
import { getGroupMembers } from '@/api/chat.js'
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
const messageInputRef = ref(null)
const messageListRef = ref(null)
const loadingMore = ref(false)
const currentPage = ref(1)
const hasMoreHistory = ref(true)
const showMembers = ref(false)
const connStatus = ref(socketService.status)
let unsubStatus = null

// 群聊相关
const members = ref([])
const showAnnouncement = ref(true)

// 引用
const quoteTarget = ref(null)

// @提及选择器
const showMentionPicker = ref(false)
const mentionQuery = ref('')
const mentionTokenStart = ref(-1)

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

// 群头像：优先自定义头像，否则使用成员头像拼贴
const groupAvatar = computed(() => {
  const custom = chatStore.currentGroup?.avatar || session.value?.target_avatar
  if (custom) return { type: 'image', src: custom }
  const avatars = chatStore.currentGroup?.member_avatars || session.value?.member_avatars || []
  return { type: 'collage', avatars }
})

// 群公告
const groupAnnouncement = computed(() => {
  if (!isGroup.value) return ''
  return chatStore.currentGroup?.announcement || session.value?.group_announcement || ''
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

const fetchGroupMembers = async (groupId) => {
  try {
    const response = await getGroupMembers(groupId)
    if (response.success) {
      members.value = response.data || []
    }
  } catch (error) {
    console.error('获取群成员失败:', error)
    members.value = []
  }
}

const isSending = ref(false)

const collectMentionUserIds = (content) => {
  if (!isGroup.value || !members.value.length) return []
  const ids = []
  const regex = /@([^\s@]+)/g
  let match
  while ((match = regex.exec(content)) !== null) {
    const name = match[1]
    const member = members.value.find(m => (m.nickname || `用户${m.id}`) === name)
    if (member) ids.push(member.id)
  }
  return [...new Set(ids)]
}

const sendMessage = async () => {
  const content = messageInput.value.trim()
  if (!content || !currentTargetId.value || isSending.value) return
  isSending.value = true
  chatStore.currentSessionType = currentType.value

  const options = {}
  if (quoteTarget.value) {
    options.quote = quoteTarget.value
  }
  if (isGroup.value) {
    options.mentionUserIds = collectMentionUserIds(content)
  }

  messageInput.value = ''
  clearQuote()
  try {
    const result = await chatStore.sendMessage(currentTargetId.value, content, 1, options)
    if (result.success) {
      scrollToBottom()
    }
  } finally {
    setTimeout(() => {
      isSending.value = false
    }, 300)
  }
}

const handleQuoteMessage = (message) => {
  if (!message) return
  quoteTarget.value = {
    id: message.id,
    content: (message.content || '').slice(0, 100),
    from_nickname: message.from_nickname || resolveSenderName(message)
  }
}

const clearQuote = () => {
  quoteTarget.value = null
}

// ---------- @提及 输入处理 ----------
const filteredMentionMembers = computed(() => {
  if (!isGroup.value || members.value.length === 0) return []
  const q = mentionQuery.value.trim().toLowerCase()
  return members.value
    .filter(m => {
      const name = (m.nickname || `用户${m.id}`).toLowerCase()
      return !q || name.includes(q)
    })
    .slice(0, 6)
})

const handleInput = () => {
  const ta = messageInputRef.value
  if (!ta) return
  const cursor = ta.selectionStart
  const before = ta.value.slice(0, cursor)
  const atIdx = before.lastIndexOf('@')

  if (isGroup.value && atIdx !== -1 && !/\s/.test(before.slice(atIdx + 1))) {
    showMentionPicker.value = true
    mentionTokenStart.value = atIdx
    mentionQuery.value = before.slice(atIdx + 1)
  } else {
    showMentionPicker.value = false
  }
}

const selectMentionMember = (member) => {
  const ta = messageInputRef.value
  const text = messageInput.value
  const start = mentionTokenStart.value
  const end = start + 1 + mentionQuery.value.length
  const insert = `@${member.nickname || `用户${member.id}`} `
  const newValue = text.slice(0, start) + insert + text.slice(end)
  messageInput.value = newValue
  showMentionPicker.value = false
  nextTick(() => {
    if (ta) {
      const pos = start + insert.length
      ta.focus()
      ta.selectionStart = pos
      ta.selectionEnd = pos
    }
  })
}

const closeMentionPicker = () => {
  showMentionPicker.value = false
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
  if (showMentionPicker.value && filteredMentionMembers.value.length > 0) {
    if (event.key === 'Enter') {
      event.preventDefault()
      selectMentionMember(filteredMentionMembers.value[0])
      return
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault()
      return
    }
  }
  if (event.key === 'Escape') {
    closeMentionPicker()
  }
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

watch([() => currentTargetId.value, () => currentType.value], ([newTargetId, newType]) => {
  if (newTargetId) {
    currentPage.value = 1
    hasMoreHistory.value = true
    showAnnouncement.value = true
    quoteTarget.value = null
    closeMentionPicker()
    if (Number(newType) === 2) {
      fetchGroupMembers(newTargetId)
    } else {
      members.value = []
    }
    chatStore.setCurrentSession(newTargetId, newType)
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
      <GroupAvatar
        v-if="isGroup && groupAvatar.type === 'collage'"
        :avatars="groupAvatar.avatars"
        :size="36"
        :fallback="defaultAvatar"
        class="chat-header-avatar"
      />
      <img
        v-else-if="isGroup && groupAvatar.type === 'image'"
        :src="groupAvatar.src"
        class="chat-header-avatar"
        alt="群头像"
      />
      <img
        v-else-if="!isGroup"
        :src="headerAvatar || defaultAvatar"
        class="chat-header-avatar"
        alt="头像"
        @click="goToUserProfile"
      />
      <span class="chat-title" :class="{ clickable: !isGroup }" @click="goToUserProfile">{{ chatTitle }}</span>
      <button v-if="isGroup" class="members-btn" @click="toggleMembers">
        {{ showMembers ? '收起' : '成员' }}
      </button>
    </div>

    <div
      v-if="isGroup && groupAnnouncement && showAnnouncement"
      class="announcement-banner"
      @click="showAnnouncement = false"
      title="点击关闭"
    >
      <span class="announcement-label">📢 群公告</span>
      <span class="announcement-content">{{ groupAnnouncement }}</span>
      <span class="announcement-close">✕</span>
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
          @quote="handleQuoteMessage"
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
      <div v-if="quoteTarget" class="quote-bar">
        <div class="quote-bar-info">
          <span class="quote-bar-label">引用 {{ quoteTarget.from_nickname || '消息' }}</span>
          <span class="quote-bar-text">{{ quoteTarget.content }}</span>
        </div>
        <button class="quote-bar-close" @click="clearQuote">✕</button>
      </div>

      <div class="mention-picker" v-if="showMentionPicker && filteredMentionMembers.length > 0">
        <div
          v-for="member in filteredMentionMembers"
          :key="member.id"
          class="mention-item"
          @mousedown.prevent="selectMentionMember(member)"
        >
          <img :src="member.avatar || defaultAvatar" class="mention-avatar" alt="头像" v-img-fallback="'avatar'" />
          <span class="mention-name">{{ member.nickname || `用户${member.id}` }}</span>
          <span v-if="member.role === 1" class="mention-role">群主</span>
        </div>
      </div>

      <div class="input-row">
        <textarea
          ref="messageInputRef"
          v-model="messageInput"
          class="message-input"
          :placeholder="isGroup ? '输入消息... 输入 @ 可提及成员' : '输入消息...'"
          rows="3"
          @keydown="handleKeydown"
          @input="handleInput"
          @blur="closeMentionPicker"
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
  position: relative;
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

.announcement-banner {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 20px;
  background: rgba(230, 162, 60, 0.12);
  border-bottom: 1px solid rgba(230, 162, 60, 0.25);
  font-size: 13px;
  color: var(--text-color-primary);
  cursor: pointer;
  flex-shrink: 0;
}

.announcement-label {
  color: #b88230;
  font-weight: 600;
  flex-shrink: 0;
}

.announcement-content {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.announcement-close {
  flex-shrink: 0;
  color: var(--text-color-tertiary);
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
  margin-left: auto;
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
  flex-direction: column;
  gap: 10px;
  flex-shrink: 0;
  position: relative;
}

.quote-bar {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 12px;
  border: 1px solid var(--border-color-secondary);
  border-radius: 8px;
  background: var(--bg-color-secondary);
  font-size: 12px;
}

.quote-bar-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.quote-bar-label {
  color: var(--primary-color);
  font-weight: 500;
}

.quote-bar-text {
  color: var(--text-color-tertiary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.quote-bar-close {
  background: transparent;
  border: none;
  color: var(--text-color-tertiary);
  cursor: pointer;
  font-size: 14px;
  flex-shrink: 0;
}

.quote-bar-close:hover {
  color: var(--danger-color);
}

.mention-picker {
  position: absolute;
  bottom: calc(100% - 8px);
  left: 20px;
  right: 20px;
  max-height: 220px;
  overflow-y: auto;
  background: var(--bg-color-primary);
  border: 1px solid var(--border-color-primary);
  border-radius: 10px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.12);
  z-index: 20;
  padding: 6px;
}

.mention-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 10px;
  border-radius: 8px;
  cursor: pointer;
  transition: background 0.15s;
}

.mention-item:hover {
  background: var(--bg-color-secondary);
}

.mention-avatar {
  width: 30px;
  height: 30px;
  border-radius: 50%;
  object-fit: cover;
  flex-shrink: 0;
}

.mention-name {
  flex: 1;
  font-size: 14px;
  color: var(--text-color-primary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mention-role {
  padding: 1px 8px;
  border-radius: 8px;
  background: var(--primary-color);
  color: #fff;
  font-size: 10px;
  flex-shrink: 0;
}

.input-row {
  display: flex;
  gap: 12px;
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
