<script setup>
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { formatTime } from '@/utils/timeFormat.js'
import { resolveSenderName } from '@/utils/chatUserResolver.js'

const router = useRouter()

const props = defineProps({
  message: {
    type: Object,
    required: true
  },
  isSelf: {
    type: Boolean,
    default: false
  },
  userAvatar: {
    type: String,
    default: ''
  },
  showNickname: {
    type: Boolean,
    default: false
  }
})

const senderNickname = computed(() => {
  return resolveSenderName(props.message)
})

const defaultAvatar = new URL('@/assets/imgs/瓜呱.png', import.meta.url).href

const displayTime = computed(() => {
  return props.message.created_at ? formatTime(props.message.created_at) : ''
})

const statusText = computed(() => {
  if (props.message.failed) return '发送失败'
  if (props.message.sending) return '发送中...'
  return ''
})

const RECALL_WINDOW_MS = 120 * 1000
const now = ref(Date.now())
let recallTimer = null

onMounted(() => {
  recallTimer = setInterval(() => {
    now.value = Date.now()
  }, 30000)
})

onUnmounted(() => {
  if (recallTimer) clearInterval(recallTimer)
})

const canRecall = computed(() => {
  if (!props.isSelf || !props.message) return false
  if (props.message.is_recalled) return false
  if (props.message.sending || props.message.failed) return false
  if (!props.message.created_at) return false
  return (now.value - new Date(props.message.created_at).getTime()) < RECALL_WINDOW_MS
})

const emit = defineEmits(['retry', 'recall'])

const handleRetry = () => {
  if (props.message.failed) {
    emit('retry', props.message)
  }
}

const handleRecall = () => {
  if (canRecall.value) {
    emit('recall', props.message)
  }
}


const handleAvatarClick = () => {
  if (props.isSelf) return
  const userId = props.message.from_user_id
  if (!userId) return
  router.push({ name: 'user_profile', params: { userId } })
}
</script>

<template>
  <div v-if="message.is_recalled" class="message-recalled">
    <span>{{ isSelf ? '你撤回了一条消息' : `${senderNickname}撤回了一条消息` }}</span>
  </div>
  <div v-else class="message-bubble" :class="{ 'message-self': isSelf }">
    <img
      :src="userAvatar || defaultAvatar"
      class="avatar"
      :class="{ clickable: !isSelf }"
      alt="头像"
      @click="handleAvatarClick"
    />
    <div class="message-content">
      <div v-if="showNickname && !isSelf" class="message-nickname">{{ senderNickname }}</div>
      <div class="message-text">{{ message.content }}</div>
      <div class="message-meta">
        <span class="message-time">{{ displayTime }}</span>
        <span v-if="statusText" class="message-status" :class="{ failed: message.failed }">
          {{ statusText }}
        </span>
        <button v-if="message.failed" class="retry-btn" @click="handleRetry">
          重试
        </button>
        <button v-if="canRecall" class="recall-btn" @click="handleRecall">
          撤回
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.message-bubble {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  margin-bottom: 16px;
}

.message-self {
  flex-direction: row-reverse;
}

.avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  object-fit: cover;
  flex-shrink: 0;
  background: var(--bg-color-secondary);
}

.avatar.clickable {
  cursor: pointer;
  transition: opacity 0.2s ease;
}

.avatar.clickable:hover {
  opacity: 0.8;
}

.message-content {
  max-width: 60%;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
}

.message-self .message-content {
  align-items: flex-end;
}

.message-nickname {
  font-size: 12px;
  color: var(--text-color-tertiary);
  margin-bottom: 4px;
  padding-left: 4px;
}

.message-text {
  padding: 12px 16px;
  border-radius: 18px;
  background: var(--bg-color-secondary);
  color: var(--text-color-primary);
  font-size: 14px;
  line-height: 1.5;
  word-break: break-word;
  white-space: pre-wrap;
}

.message-self .message-text {
  background: var(--primary-color);
  color: #fff;
}

.message-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 4px;
  font-size: 12px;
  color: var(--text-color-tertiary);
}

.message-status {
  color: var(--text-color-tertiary);
}

.message-status.failed {
  color: var(--danger-color);
}

.retry-btn {
  padding: 2px 8px;
  border: none;
  border-radius: 10px;
  background: var(--danger-color);
  color: #fff;
  font-size: 11px;
  cursor: pointer;
  transition: opacity 0.2s;
}

.retry-btn:hover {
  opacity: 0.8;
}

.recall-btn {
  padding: 2px 8px;
  border: none;
  border-radius: 10px;
  background: transparent;
  color: var(--text-color-tertiary);
  font-size: 11px;
  cursor: pointer;
  transition: color 0.2s;
}

.recall-btn:hover {
  color: var(--danger-color);
}

.message-recalled {
  text-align: center;
  font-size: 12px;
  color: var(--text-color-tertiary);
  margin: 8px 0;
}

.message-recalled span {
  display: inline-block;
  padding: 4px 12px;
  background: var(--bg-color-secondary);
  border-radius: 8px;
}
</style>
