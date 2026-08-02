<template>
  <div v-if="visible" class="modal-overlay" v-click-outside.mousedown="closeModal" v-escape-key="closeModal">
    <div class="modal detail-modal" @mousedown.stop>
      <div class="modal-header">
        <h4>{{ title }}</h4>
        <button @click="closeModal" class="close-btn">
          <SvgIcon name="close" />
        </button>
      </div>
      <div class="modal-body">
        <div class="detail-content" v-html="content">
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import SvgIcon from '@/components/SvgIcon.vue'

const props = defineProps({
  visible: {
    type: Boolean,
    default: false
  },
  title: {
    type: String,
    default: '详细内容'
  },
  content: {
    type: String,
    default: ''
  }
})

const emit = defineEmits(['update:visible', 'close'])

const closeModal = () => {
  emit('update:visible', false)
  emit('close')
}

</script>

<style scoped>
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: var(--overlay-bg);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 1000;
}

.modal {
  background: var(--bg-color-primary);
  border-radius: 8px;
  width: 90%;
  max-width: 600px;
  max-height: 80vh;
  overflow-y: auto;
  transition: background-color 0.3s ease;
}

.detail-modal {
  max-width: 500px;
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 20px 10px 0px 30px;
}

.modal-header h4 {
  margin: 0;
  color: var(--text-color-primary);
}

.close-btn {
  background: none;
  border: none;
  cursor: pointer;
  padding: 5px;
  color: var(--text-color-secondary);
  transition: color 0.2s;
}

.close-btn:hover {
  color: var(--text-color-primary);
}

.close-btn svg {
  width: 16px;
  height: 16px;
}

.modal-body {
  padding: 20px;
}

.detail-content {
  padding: 20px;
  line-height: 1.6;
  color: var(--text-color-primary);
  word-wrap: break-word;
  font-size: 14px;
  background: var(--bg-color-secondary);
  border-radius: 4px;
  max-height: 400px;
  overflow-y: auto;
}

.detail-content :deep(table) {
  width: 100%;
  border-collapse: collapse;
  margin: 10px 0;
}

.detail-content :deep(td) {
  padding: 8px 12px;
  border: 1px solid var(--border-color-primary);
  vertical-align: top;
}

.detail-content :deep(td:first-child) {
  font-weight: bold;
  background-color: var(--bg-color-primary);
  width: 30%;
}

.detail-content :deep(td:last-child) {
  background-color: var(--bg-color-secondary);
}

</style>