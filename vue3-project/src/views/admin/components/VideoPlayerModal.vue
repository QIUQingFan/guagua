<template>
  <div v-if="visible" class="video-modal-overlay" @click="closeModal">
    <div class="video-modal" @click.stop>
      <div class="video-modal-header">
        <h3>查看视频</h3>
        <button class="close-btn" @click="closeModal">
          <SvgIcon name="close" />
        </button>
      </div>
      <div class="video-modal-body">
        <video
          v-if="videoUrl"
          ref="videoPlayer"
          :src="videoUrl"
          :poster="posterUrl"
          controls
          preload="metadata"
          class="modal-video-player"
        >
          您的浏览器不支持视频播放
        </video>
        <div v-else class="video-placeholder">
          <SvgIcon name="video" width="48" height="48" />
          <p>视频加载中...</p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, watch, nextTick } from 'vue'
import SvgIcon from '@/components/SvgIcon.vue'

const props = defineProps({
  visible: {
    type: Boolean,
    default: false
  },
  videoUrl: {
    type: String,
    default: ''
  },
  posterUrl: {
    type: String,
    default: ''
  }
})

const emit = defineEmits(['update:visible', 'close'])

const videoPlayer = ref(null)

const closeModal = () => {
  emit('update:visible', false)
  emit('close')
}

watch(() => props.visible, async (newVisible) => {
  if (newVisible) {
    await nextTick()
  } else {
    if (videoPlayer.value) {
      videoPlayer.value.pause()
    }
  }
})

const handleKeydown = (event) => {
  if (event.key === 'Escape' && props.visible) {
    closeModal()
  }
}

watch(() => props.visible, (newVisible) => {
  if (newVisible) {
    document.addEventListener('keydown', handleKeydown)
  } else {
    document.removeEventListener('keydown', handleKeydown)
  }
})
</script>

<style scoped>
.video-modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.8);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
  padding: 20px;
}

.video-modal {
  background: var(--bg-color-primary);
  border-radius: 12px;
  max-width: 90vw;
  max-height: 90vh;
  width: 800px;
  display: flex;
  flex-direction: column;
  box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
}

.video-modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 20px 24px 16px;
  border-bottom: 1px solid var(--border-color-primary);
}

.video-modal-header h3 {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
  color: var(--text-color-primary);
}

.close-btn {
  background: var(--bg-color-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  width: 30px;
  height: 30px;
  border: none;
  cursor: pointer;
  padding: 5px;
  color: var(--text-color-primary);
}

.close-btn:hover {
  color: var(--text-color-secondary);
  transform: scale(1.1);
  transition: all 0.2s ease;
}

.close-btn svg {
  width: 16px;
  height: 16px;
}

.video-modal-body {
  padding: 24px;
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 300px;
}

.modal-video-player {
  width: 100%;
  max-width: 100%;
  max-height: 60vh;
  border-radius: 8px;
  background: #000;
}

.video-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--text-color-secondary);
  gap: 12px;
}

.video-placeholder p {
  margin: 0;
  font-size: 16px;
}

@media (max-width: 768px) {
  .video-modal {
    width: 95vw;
    max-height: 85vh;
  }
  
  .video-modal-header {
    padding: 16px 20px 12px;
  }
  
  .video-modal-header h3 {
    font-size: 16px;
  }
  
  .video-modal-body {
    padding: 20px;
    min-height: 250px;
  }
  
  .modal-video-player {
    max-height: 50vh;
  }
}
</style>