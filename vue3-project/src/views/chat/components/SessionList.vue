<script setup>
import { computed } from 'vue'
import { useChatStore } from '@/stores/chat'
import { formatTime } from '@/utils/timeFormat.js'
import { resolveSessionName } from '@/utils/chatUserResolver.js'

const props = defineProps({
  activeId: {
    type: [Number, String],
    default: null
  },
  activeType: {
    type: Number,
    default: 1
  }
})

const emit = defineEmits(['select', 'create-group'])

const chatStore = useChatStore()
const sessions = computed(() => chatStore.sortedSessions)
const defaultAvatar = new URL('@/assets/imgs/瓜呱.png', import.meta.url).href

const isActive = (session) => {
  return Number(session.target_id) === Number(props.activeId || chatStore.currentTargetId) &&
    session.session_type === (props.activeType || chatStore.currentSessionType)
}

const sessionName = (session) => {
  return resolveSessionName(session)
}

const sessionAvatar = (session) => {
  return session.target_avatar || defaultAvatar
}

const handleSelect = (session) => {
  emit('select', {
    targetId: Number(session.target_id),
    sessionType: session.session_type || 1
  })
}

const handleCreateGroup = () => {
  emit('create-group')
}

const formatLastMessage = (content) => {
  if (!content) return '暂无消息'
  return content.length > 30 ? content.slice(0, 30) + '...' : content
}
</script>

<template>
  <div class="session-list">
    <div class="session-header">
      <h3 class="session-title">消息</h3>
      <button class="create-group-btn" @click="handleCreateGroup" title="创建群聊">
        + 群聊
      </button>
    </div>

    <div class="session-items">
      <div
        v-for="session in sessions"
        :key="`${session.session_type || 1}_${session.target_id}`"
        class="session-item"
        :class="{ active: isActive(session) }"
        @click="handleSelect(session)"
      >
        <img
          :src="sessionAvatar(session)"
          class="session-avatar"
          alt="头像"
        />
        <div class="session-info">
          <div class="session-row">
            <span class="session-name">{{ sessionName(session) }}</span>
            <span class="session-time">{{ session.updated_at ? formatTime(session.updated_at) : '' }}</span>
          </div>
          <div class="session-row">
            <span class="session-preview">{{ formatLastMessage(session.last_message) }}</span>
            <span v-if="session.unread_count > 0" class="unread-badge">
              {{ session.unread_count > 99 ? '99+' : session.unread_count }}
            </span>
          </div>
        </div>
      </div>

      <div v-if="sessions.length === 0" class="empty-sessions">
        暂无会话
      </div>
    </div>
  </div>
</template>

<style scoped>
.session-list {
  width: 300px;
  height: 100%;
  border-right: 1px solid var(--border-color-primary);
  background: var(--bg-color-primary);
  display: flex;
  flex-direction: column;
  flex-shrink: 0;
  position: relative;
  z-index: 101;
}

.session-header {
  height: 60px;
  padding: 0 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--border-color-primary);
  flex-shrink: 0;
}

.session-title {
  font-size: 18px;
  font-weight: 600;
  color: var(--text-color-primary);
  margin: 0;
}

.create-group-btn {
  padding: 4px 10px;
  border: 1px solid var(--primary-color);
  border-radius: 14px;
  background: transparent;
  color: var(--primary-color);
  font-size: 12px;
  cursor: pointer;
  transition: all 0.2s;
}

.create-group-btn:hover {
  background: var(--primary-color);
  color: #fff;
}

.session-items {
  flex: 1;
  overflow-y: auto;
}

.session-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  cursor: pointer;
  transition: background 0.2s;
  border-bottom: 1px solid var(--border-color-secondary);
}

.session-item:hover {
  background: var(--bg-color-secondary);
}

.session-item.active {
  background: var(--bg-color-secondary);
}

.session-avatar {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  object-fit: cover;
  flex-shrink: 0;
  background: var(--bg-color-secondary);
}

.session-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.session-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
}

.session-name {
  font-size: 14px;
  font-weight: 500;
  color: var(--text-color-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.session-time {
  font-size: 12px;
  color: var(--text-color-quaternary);
  flex-shrink: 0;
}

.session-preview {
  font-size: 13px;
  color: var(--text-color-tertiary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  flex: 1;
}

.unread-badge {
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  border-radius: 9px;
  background: var(--primary-color);
  color: #fff;
  font-size: 11px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.empty-sessions {
  padding: 40px 20px;
  text-align: center;
  color: var(--text-color-tertiary);
  font-size: 14px;
}
</style>