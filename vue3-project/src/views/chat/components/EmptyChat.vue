<script setup>
defineProps({
  title: {
    type: String,
    default: '选择一位用户开始聊天'
  },
  subtitle: {
    type: String,
    default: '你可以在用户主页点击"发消息"发起私聊'
  }
})
</script>

<template>
  <div class="empty-chat">
    <div class="empty-icon">💬</div>
    <div class="empty-title">{{ title }}</div>
    <div class="empty-subtitle">{{ subtitle }}</div>
  </div>
</template>

<style scoped>
.empty-chat {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--text-color-tertiary);
  padding: 40px;
}

.empty-icon {
  font-size: 64px;
  margin-bottom: 16px;
  opacity: 0.6;
}

.empty-title {
  font-size: 18px;
  font-weight: 500;
  color: var(--text-color-primary);
  margin-bottom: 8px;
}

.empty-subtitle {
  font-size: 14px;
  text-align: center;
  max-width: 300px;
  line-height: 1.5;
}
</style>