<template>
  <div class="shortcuts-modal-overlay" v-click-outside.mousedown="closeModal" v-escape-key="closeModal"
    :class="{ 'animating': isAnimating }">
    <div class="shortcuts-modal" @click.stop :class="{ 'scale-in': isAnimating }">
      <div class="shortcuts-header">
        <div class="header-content">
          <h1 class="shortcuts-title">键盘快捷键</h1>
        </div>
        <button class="close-btn" @click="closeModal">
          <SvgIcon name="close" />
        </button>
      </div>

      <div class="shortcuts-content">
        <div class="shortcuts-main">
          <div class="shortcuts-list">
            <div class="shortcut-item">
              <span class="shortcut-desc">上一张图片</span>
              <div class="shortcut-keys">
                <kbd class="shortcut-key">←</kbd>
              </div>
            </div>

            <div class="shortcut-item">
              <span class="shortcut-desc">下一张图片</span>
              <kbd class="shortcut-key">→</kbd>
            </div>

            <div class="shortcut-item">
              <span class="shortcut-desc">关闭笔记</span>
              <kbd class="shortcut-key">Esc</kbd>
            </div>
            <div class="shortcut-item">
              <span class="shortcut-desc">收藏</span>
              <kbd class="shortcut-key">S</kbd>
            </div>
            <div class="shortcut-item">
              <span class="shortcut-desc">点赞</span>
              <kbd class="shortcut-key">D</kbd>
            </div>
            <div class="shortcut-item">
              <span class="shortcut-desc">发送评论</span>
              <kbd class="shortcut-key">Ctrl</kbd>
              <span class="plus">+</span>
              <kbd class="shortcut-key">Enter</kbd>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import SvgIcon from '@/components/SvgIcon.vue'
import { useScrollLock } from '@/composables/useScrollLock'

const emit = defineEmits(['close'])

const { lock, unlock } = useScrollLock()

const isAnimating = ref(false)

const closeModal = () => {
  isAnimating.value = false
  unlock()
  setTimeout(() => {
    emit('close')
  }, 200)
}

onMounted(() => {
  lock()

  setTimeout(() => {
    isAnimating.value = true
  }, 10)
})
</script>

<style scoped>
.shortcuts-modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: var(--overlay-bg);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 2000;
  opacity: 0;
  transition: opacity 0.2s ease;
}

.shortcuts-modal-overlay.animating {
  opacity: 1;
}

.shortcuts-modal {
  background: var(--bg-color-primary);
  border-radius: 16px;
  width: 400px;
  min-height: 70vh;
  position: relative;
  transform: scale(0.9);
  transition: transform 0.2s ease;
  box-shadow: 0 20px 40px var(--shadow-color);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.shortcuts-modal.scale-in {
  transform: scale(1);
}

.shortcuts-header {
  position: relative;
  background: var(--bg-color-primary);
  padding: 16px 32px;
  border-radius: 16px 16px 0 0;
  flex-shrink: 0;
  border-bottom: 1px solid var(--border-color-primary);
}

.header-content {
  text-align: center;
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

.shortcuts-content {
  flex: 1;
  overflow-y: auto;
  padding: 12px 24px;
}

.shortcuts-main {
  display: flex;
  flex-direction: column;
  gap: 0;
}

.shortcuts-title {
  font-size: 16px;
  font-weight: 700;
  color: var(--text-color-primary);
  margin: 0;
}

.shortcuts-list {
  display: flex;
  flex-direction: column;
  gap: 0;
}

.shortcut-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 0;
  border-bottom: 1px solid var(--border-color-primary);
}

.shortcut-item:last-child {
  border-bottom: none;
}

.shortcut-desc {
  font-size: 16px;
  color: var(--text-color-secondary);
  flex: 1;
  font-weight: 400;
}

.shortcut-key {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  height: 24px;
  padding: 0 8px;
  background: var(--text-color-primary);
  border-radius: 5px;
  font-size: 15px;
  font-weight: 600;
  color: var(--bg-color-primary);
  font-family: var(--font-family);
}

.plus {
  margin: 0 4px;
}

@media (max-width: 768px) {
  .shortcuts-modal {
    width: 300px;
  }
}
</style>