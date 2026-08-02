<template>
  <div v-if="visible" class="modal-overlay" v-click-outside.mousedown="handleClose" v-escape-key="handleClose">
    <div class="modal crop-modal" @mousedown.stop>
      <div class="modal-header">
        <h4>裁剪头像</h4>
        <button @click="handleClose" class="close-btn">
          <SvgIcon name="close" width="16" height="16" />
        </button>
      </div>
      <div class="modal-body">
        <div class="crop-container">
          <img ref="cropImage" :src="imageSrc" alt="待裁剪图片" v-img-fallback />
        </div>
      </div>
      <div class="modal-footer">
        <div class="form-actions">
          <button type="button" @click="handleClose" class="btn btn-outline">取消</button>
          <button type="button" @click="handleConfirm" class="btn btn-primary" :disabled="uploading">
            {{ uploading ? '上传中...' : '确认裁剪' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { ref, watch, nextTick, onUnmounted } from 'vue'
import Cropper from 'cropperjs'
import 'cropperjs/dist/cropper.css'
import SvgIcon from '@/components/SvgIcon.vue'

export default {
  name: 'CropModal',
  components: {
    SvgIcon
  },
  props: {
    visible: {
      type: Boolean,
      default: false
    },
    imageSrc: {
      type: String,
      default: ''
    },
    uploading: {
      type: Boolean,
      default: false
    }
  },
  emits: ['close', 'confirm'],
  setup(props, { emit }) {
    const cropImage = ref(null)
    let cropper = null

    const initCropper = () => {
      if (cropImage.value && props.imageSrc) {
        cropper = new Cropper(cropImage.value, {
          aspectRatio: 1,
          viewMode: 1,
          dragMode: 'move',
          autoCropArea: 0.65,
          restore: false,
          guides: true,
          center: true,
          highlight: false,
          cropBoxMovable: true,
          cropBoxResizable: true,
          toggleDragModeOnDblclick: false,
          background: false,
          modal: true,
          responsive: true,
          checkCrossOrigin: false
        })
      }
    }

    const destroyCropper = () => {
      if (cropper) {
        cropper.destroy()
        cropper = null
      }
    }

    watch(() => props.visible, (newVal) => {
      if (newVal && props.imageSrc) {
        nextTick(() => {
          initCropper()
        })
      } else {
        destroyCropper()
      }
    })

    const handleClose = () => {
      emit('close')
    }

    const handleConfirm = () => {
      if (cropper) {
        const canvas = cropper.getCroppedCanvas({
          width: 200,
          height: 200,
          imageSmoothingEnabled: true,
          imageSmoothingQuality: 'high'
        })
        
        canvas.toBlob((blob) => {
          emit('confirm', blob)
        }, 'image/jpeg', 0.9)
      }
    }

    onUnmounted(() => {
      destroyCropper()
    })

    return {
      cropImage,
      handleClose,
      handleConfirm
    }
  }
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
  max-width: 500px;
  max-height: 80vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.crop-modal {
  max-width: 600px;
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 20px 30px;
  border-bottom: 1px solid var(--border-color-primary);
  flex-shrink: 0;
  background: var(--bg-color-primary);
}

.modal-header h4 {
  margin: 0;
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

.modal-body {
  padding: 20px;
  flex: 1;
  overflow-y: auto;
  min-height: 0;
}

.modal-footer {
  flex-shrink: 0;
  background: var(--bg-color-primary);
  border-top: 1px solid var(--border-color-primary);
  padding: 20px 30px;
}

.form-actions {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  margin: 0;
}

.btn {
  padding: 8px 16px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  transition: all 0.2s;
  text-decoration: none;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-primary {
  background-color: var(--primary-color);
  color: white;
}

.btn-primary:hover:not(:disabled) {
  background-color: var(--primary-color-dark);
}

.btn-outline {
  background-color: transparent;
  color: var(--text-color-secondary);
  border: 1px solid var(--border-color-primary);
}

.btn-outline:hover:not(:disabled) {
  background-color: var(--bg-color-secondary);
}

.crop-container {
  max-height: 400px;
  overflow: hidden;
  text-align: center;
}

.crop-container img {
  max-width: 100%;
  max-height: 400px;
}
</style>