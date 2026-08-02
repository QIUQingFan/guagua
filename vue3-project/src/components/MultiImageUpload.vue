<template>
  <div class="multi-image-upload">
    <div class="upload-grid" @dragover.prevent @drop.prevent="handleDrop">

      <div v-for="(imageItem, index) in imageList" :key="imageItem.id" class="image-item" :class="{
        'dragging': dragIndex === index,
        'touch-dragging': isTouchDragging && touchStartIndex === index,
        'long-pressing': isLongPressed && touchStartIndex === index && !isTouchDragging
      }" draggable="true" @dragstart="handleDragStart(index, $event)" @dragenter.prevent="handleDragEnter(index)"
        @dragover.prevent @dragend="handleDragEnd" @touchstart="handleTouchStart(index, $event)"
        @touchmove="handleTouchMove($event)" @touchend="handleTouchEnd($event)">
        <div class="image-preview" @click="handleImagePreviewClick(index)">
          <img :src="imageItem.preview" alt="预览图片" />
          <div class="image-overlay">
            <div class="image-actions">
              <button @click.stop="removeImage(index)" class="action-btn remove-btn"
                :disabled="isUploading || (!props.allowDeleteLast && imageList.length <= 1)">
                <SvgIcon name="delete" />
              </button>
            </div>
            <div class="image-index">{{ index + 1 }}</div>
          </div>
        </div>
      </div>

      <div v-if="imageList.length < maxImages" class="upload-item" @click="!isUploading && triggerFileInput()"
        :class="{ 'drag-over': isDragOver, 'uploading': isUploading }"
        @dragover.prevent="!isUploading && (isDragOver = true)" @dragleave.prevent="isDragOver = false"
        @drop.prevent="!isUploading && handleFileDrop($event)">
        <input ref="fileInput" type="file" accept="image/*" multiple @change="handleFileSelect" style="display: none"
          :disabled="isUploading" />

        <div class="upload-placeholder">
          <SvgIcon name="publish" class="upload-icon" :class="{ 'uploading': isUploading }" />
          <p>{{ isUploading ? '上传中...' : '添加图片' }}</p>
          <p class="upload-hint">{{ imageList.length }}/{{ maxImages }}</p>
          <p v-if="!isUploading" class="drag-hint">或拖拽图片到此处</p>
        </div>
      </div>
    </div>

    <div v-if="error" class="error-message">
      {{ error }}
    </div>

    <div class="upload-tips">
      <p>• 最多上传{{ maxImages }}张图片</p>
      <p>• 支持 JPG、PNG 格式</p>
      <p>• 单张图片不超过5MB</p>
      <p class="drag-tip">• <span class="desktop-tip">拖拽图片可调整顺序</span><span class="mobile-tip">长按图片可拖拽排序</span></p>
    </div>

    <MessageToast v-if="showToast" :message="toastMessage" :type="toastType" @close="handleToastClose" />

    <ImageViewer :visible="showImageViewer" :images="viewerImages" :initial-index="currentImageIndex" image-type="post"
      @close="handleImageViewerClose" @change="handleImageViewerChange" />
  </div>
</template>

<script setup>
import { ref, watch, nextTick } from 'vue'
import SvgIcon from '@/components/SvgIcon.vue'
import MessageToast from '@/components/MessageToast.vue'
import ImageViewer from '@/components/ImageViewer.vue'
import { imageUploadApi, uploadApi } from '@/api/index.js'

const props = defineProps({
  modelValue: {
    type: Array,
    default: () => []
  },
  maxImages: {
    type: Number,
    default: 9
  },
  allowDeleteLast: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['update:modelValue', 'error'])

const fileInput = ref(null)
const imageList = ref([])
const error = ref('')
const isDragOver = ref(false)
const isUploading = ref(false)

const showToast = ref(false)
const toastMessage = ref('')
const toastType = ref('success')

const dragIndex = ref(-1)
const dragOverIndex = ref(-1)

const touchStartIndex = ref(-1)
const touchStartX = ref(0)
const touchStartY = ref(0)
const touchCurrentY = ref(0)
const isTouchDragging = ref(false)
const touchThreshold = 10 
const longPressTimer = ref(null)
const longPressDelay = 300 
const isLongPressed = ref(false)

const showImageViewer = ref(false)
const currentImageIndex = ref(0)
const viewerImages = ref([])

const generateId = () => Date.now() + Math.random().toString(36).substr(2, 9)

const initializeImageList = (images) => {
  return images.map((image, index) => {
    if (typeof image === 'string') {
      return {
        id: generateId(),
        file: null,
        preview: image,
        uploaded: true,
        url: image
      }
    } else if (image.file) {
      return {
        id: image.id || generateId(),
        file: image.file,
        preview: image.preview,
        uploaded: false,
        url: null
      }
    }
    return image
  })
}

let isInternalUpdate = false

watch(() => props.modelValue, (newValue) => {
  if (isInternalUpdate) return 

  if (newValue && newValue.length > 0) {
    imageList.value = initializeImageList(newValue)
  } else {
    imageList.value = []
  }
}, { immediate: true })

watch(imageList, (newValue) => {
  if (isInternalUpdate) return 

  isInternalUpdate = true

  const externalValue = newValue.map(item => ({
    id: item.id,
    file: item.file,
    preview: item.preview,
    uploaded: item.uploaded,
    url: item.url
  }))
  emit('update:modelValue', externalValue)

  nextTick(() => {
    isInternalUpdate = false
  })
}, { deep: true, flush: 'post' })

const triggerFileInput = () => {
  fileInput.value?.click()
}

const createImagePreview = (file) => {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = (e) => resolve(e.target.result)
    reader.onerror = () => reject(new Error('读取文件失败'))
    reader.readAsDataURL(file)
  })
}

const addFiles = async (files) => {
  const fileArray = Array.from(files)

  const remainingSlots = props.maxImages - imageList.value.length
  if (fileArray.length > remainingSlots) {
    const errorMsg = `最多只能再添加${remainingSlots}张图片`
    error.value = errorMsg
    emit('error', errorMsg)
    return
  }

  for (const file of fileArray) {
    if (file.size > 5 * 1024 * 1024) {
      const fileSizeMB = (file.size / (1024 * 1024)).toFixed(1)
      const errorMsg = `图片大小为 ${fileSizeMB}MB，超过 5MB 限制，请选择更小的图片`

      showMessage(errorMsg, 'error')

      error.value = errorMsg
      emit('error', errorMsg)
      return
    }

    const validation = imageUploadApi.validateImageFile(file)
    if (!validation.valid) {
      const errorMsg = `${file.name}: ${validation.error}`
      error.value = errorMsg
      emit('error', errorMsg)
      return
    }
  }

  error.value = ''

  try {
    for (const file of fileArray) {
      const compressedFile = await compressImage(file)
      const preview = await createImagePreview(compressedFile)
      const imageItem = {
        id: generateId(),
        file: compressedFile, 
        preview: preview,
        uploaded: false,
        url: null
      }
      imageList.value.push(imageItem)
    }
  } catch (err) {
    console.error('处理图片失败:', err)
    const errorMsg = '处理图片失败，请重试'
    error.value = errorMsg
    emit('error', errorMsg)
  }
}

const handleFileSelect = async (event) => {
  const files = event.target.files
  if (files.length === 0) return

  await addFiles(files)

  if (fileInput.value) {
    fileInput.value.value = ''
  }
}

const handleFileDrop = async (event) => {
  isDragOver.value = false
  const files = event.dataTransfer.files
  if (files.length === 0) return

  await addFiles(files)
}

const removeImage = (index) => {
  if (!props.allowDeleteLast && imageList.value.length <= 1) {
    return
  }
  imageList.value.splice(index, 1)
  error.value = ''
}

const handleDragStart = (index, event) => {
  dragIndex.value = index
  event.dataTransfer.effectAllowed = 'move'
  event.dataTransfer.setData('text/html', event.target.outerHTML)
}

const handleDragEnter = (index) => {
  if (dragIndex.value !== -1 && dragIndex.value !== index) {
    dragOverIndex.value = index
  }
}

const handleDragEnd = () => {
  if (dragIndex.value !== -1 && dragOverIndex.value !== -1) {
    const draggedItem = imageList.value[dragIndex.value]
    imageList.value.splice(dragIndex.value, 1)
    imageList.value.splice(dragOverIndex.value, 0, draggedItem)
  }

  dragIndex.value = -1
  dragOverIndex.value = -1
}

const handleDrop = (event) => {
  event.preventDefault()
  handleDragEnd()
}

const handleTouchStart = (index, event) => {
  const touch = event.touches[0]
  touchStartIndex.value = index
  touchStartX.value = touch.clientX
  touchStartY.value = touch.clientY
  touchCurrentY.value = touch.clientY
  isTouchDragging.value = false
  isLongPressed.value = false

  longPressTimer.value = setTimeout(() => {
    isLongPressed.value = true
    if (navigator.vibrate) {
      navigator.vibrate(50)
    }
  }, longPressDelay)
}

const handleTouchMove = (event) => {
  if (touchStartIndex.value === -1) return

  const touch = event.touches[0]
  touchCurrentY.value = touch.clientY
  const deltaX = Math.abs(touch.clientX - touchStartX.value)
  const deltaY = Math.abs(touchCurrentY.value - touchStartY.value)
  const totalDelta = Math.sqrt(deltaX * deltaX + deltaY * deltaY) 
  if (totalDelta > touchThreshold && longPressTimer.value) {
    clearTimeout(longPressTimer.value)
    longPressTimer.value = null
  }

  if (isLongPressed.value && totalDelta > touchThreshold && !isTouchDragging.value) {
    isTouchDragging.value = true
    dragIndex.value = touchStartIndex.value
  }

  if (isTouchDragging.value) {
    event.preventDefault() 
    const targetIndex = getTouchTargetIndex(touch.clientX, touch.clientY)
    if (targetIndex !== -1 && targetIndex !== dragIndex.value) {
      dragOverIndex.value = targetIndex
    }
  }
}

const handleTouchEnd = (event) => {
  if (longPressTimer.value) {
    clearTimeout(longPressTimer.value)
    longPressTimer.value = null
  }

  if (isTouchDragging.value && dragIndex.value !== -1) {
    const touch = event.changedTouches[0]
    let finalTargetIndex = -1

    if (touch) {
      finalTargetIndex = getTouchTargetIndex(touch.clientX, touch.clientY)
    }

    if (finalTargetIndex !== -1 && finalTargetIndex !== dragIndex.value) {
      const draggedItem = imageList.value[dragIndex.value]
      imageList.value.splice(dragIndex.value, 1)
      imageList.value.splice(finalTargetIndex, 0, draggedItem)

      if (navigator.vibrate) {
        navigator.vibrate(30)
      }
    }
  }

  touchStartIndex.value = -1
  touchStartX.value = 0
  touchStartY.value = 0
  touchCurrentY.value = 0
  isTouchDragging.value = false
  isLongPressed.value = false
  dragIndex.value = -1
  dragOverIndex.value = -1
}

const getTouchTargetIndex = (clientX, clientY) => {
  const elementAtPoint = document.elementFromPoint(clientX, clientY)
  if (!elementAtPoint) {
    return -1
  }

  let imageItem = elementAtPoint.closest('.image-item')

  if (!imageItem) {
    return -1
  }

  const uploadGrid = document.querySelector('.upload-grid')
  if (!uploadGrid) {
    return -1
  }

  const imageItems = uploadGrid.querySelectorAll('.image-item')
  const targetIndex = Array.from(imageItems).indexOf(imageItem)
  return targetIndex >= 0 ? targetIndex : -1
}

const getAllImageData = async () => {
  const allImageData = []

  for (const item of imageList.value) {
    if (item.uploaded && item.url && !item.url.startsWith('data:')) {
      allImageData.push(item.url)
    }
  }

  return allImageData
}

const compressImage = (file, maxSizeMB = 0.8, quality = 0.4) => {
  return new Promise((resolve) => {
    if (file.size <= maxSizeMB * 1024 * 1024) {
      resolve(file)
      return
    }

    const canvas = document.createElement('canvas')
    const ctx = canvas.getContext('2d')
    const img = new Image()

    img.onload = () => {
      const compressQuality = 0.4
      const maxDimension = 1200

      let { width, height } = img

      if (width > maxDimension || height > maxDimension) {
        const ratio = Math.min(maxDimension / width, maxDimension / height)
        width = Math.floor(width * ratio)
        height = Math.floor(height * ratio)
      }

      canvas.width = width
      canvas.height = height

      ctx.drawImage(img, 0, 0, width, height)

      canvas.toBlob(
        (blob) => {
          if (blob) {
            const compressedFile = new File([blob], file.name, {
              type: file.type,
              lastModified: Date.now()
            })

            resolve(compressedFile)
          } else {
            resolve(file) 
          }
        },
        file.type,
        compressQuality
      )
    }

    img.onerror = () => resolve(file) 
    img.src = URL.createObjectURL(file)
  })
}

const uploadAllImages = async () => {
  if (isUploading.value) {
    return []
  }

  const unuploadedImages = imageList.value.filter(item => !item.uploaded && item.file)

  if (unuploadedImages.length === 0) {
    const existingUrls = imageList.value
      .filter(item => item.uploaded && item.url && !item.url.startsWith('data:'))
      .map(item => item.url)
    return existingUrls
  }

  isUploading.value = true
  error.value = ''

  try {
    const files = unuploadedImages.map(item => item.file)

    const result = await uploadApi.uploadImages(files)

    if (result.success && result.data && result.data.uploaded && result.data.uploaded.length > 0) {
      let uploadIndex = 0
      for (let i = 0; i < imageList.value.length; i++) {
        const item = imageList.value[i]
        if (!item.uploaded && item.file) {
          if (uploadIndex < result.data.uploaded.length) {
            const uploadedData = result.data.uploaded[uploadIndex]
            item.uploaded = true
            item.url = uploadedData.url

            uploadIndex++
          }
        }
      }

      const allUrls = imageList.value
        .filter(item => item.uploaded && item.url && !item.url.startsWith('data:'))
        .map(item => item.url)
      return allUrls
    } else {
      const errorMsg = result.message || '上传失败，没有成功上传的图片'
      console.error('上传失败:', errorMsg, result)
      throw new Error(errorMsg)
    }
  } catch (err) {
    console.error('批量上传异常:', err)
    error.value = '上传失败: ' + (err.message || '未知错误')
    throw err
  } finally {
    isUploading.value = false
  }
}

const getImageCount = () => {
  return imageList.value.length
}

const reset = () => {
  imageList.value = []
  error.value = ''
  if (fileInput.value) {
    fileInput.value.value = ''
  }
}

const syncWithUrls = (urls) => {
  isInternalUpdate = true

  if (!Array.isArray(urls)) {
    imageList.value = []
    nextTick(() => {
      isInternalUpdate = false
    })
    return
  }

  if (urls.length === 0) {
    imageList.value = []
    nextTick(() => {
      isInternalUpdate = false
    })
    return
  }

  const uniqueUrls = [...new Set(urls.filter(url => url && url.trim()))]

  const newImageList = []

  for (let i = 0; i < uniqueUrls.length; i++) {
    const url = uniqueUrls[i]

    if (url && !url.startsWith('[待上传:')) {
      const existingImageWithSameUrl = imageList.value.find(item =>
        item.uploaded && item.url === url
      )

      if (existingImageWithSameUrl) {
        newImageList.push(existingImageWithSameUrl)
      } else {
        newImageList.push({
          id: generateId(),
          file: null,
          preview: url,
          uploaded: true,
          url: url
        })
      }
    }
  }

  imageList.value = newImageList

  nextTick(() => {
    isInternalUpdate = false
  })
}

const removeImageById = (imageId) => {
  const index = imageList.value.findIndex(item => item.id === imageId)
  if (index !== -1) {
    imageList.value.splice(index, 1)
  }
}

const showMessage = (message, type = 'success') => {
  toastMessage.value = message
  toastType.value = type
  showToast.value = true
}

const handleToastClose = () => {
  showToast.value = false
}

const handleImagePreviewClick = (index) => {
  viewerImages.value = imageList.value.map(item => ({
    url: item.preview,
    alt: `预览图片 ${imageList.value.indexOf(item) + 1}`
  }))
  currentImageIndex.value = index
  showImageViewer.value = true
}

const handleImageViewerClose = () => {
  showImageViewer.value = false
}

const handleImageViewerChange = (newIndex) => {
  currentImageIndex.value = newIndex
}

defineExpose({
  uploadAllImages,
  getAllImageData,
  getImageCount,
  reset,
  syncWithUrls,
  removeImageById,
  addFiles,
  imageList,
  isUploading
})
</script>

<style scoped>
.multi-image-upload {
  width: 100%;
}

.upload-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
  gap: 10px;
  margin-bottom: 10px;
}

.image-item,
.upload-item {
  aspect-ratio: 1;
  border-radius: 8px;
  overflow: hidden;
  position: relative;
}

.image-preview {
  width: 100%;
  height: 100%;
  position: relative;
  cursor: zoom-in;
}

.image-preview img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  pointer-events: none;
}

.image-overlay {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: var(--overlay-bg);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: space-between;
  padding: 8px;
  opacity: 0;
  transition: opacity 0.2s ease;
}

.image-preview:hover .image-overlay {
  opacity: 1;
}

.image-actions {
  display: flex;
  gap: 8px;
  align-self: flex-end;
}

.action-btn {
  background: rgba(255, 255, 255, 0.814);
  border: none;
  border-radius: 50%;
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.2s ease;
  opacity: 0.5;
}

.remove-btn:hover:not(:disabled) {
  opacity: 1;
}

.action-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
  background-color: rgba(255, 255, 255, 0.3);
}

.action-btn svg {
  width: 12px;
  height: 12px;
}

.image-index {
  background: rgba(0, 0, 0, 0.534);
  color: white;
  border-radius: 12px;
  padding: 4px 8px;
  font-size: 12px;
  font-weight: bold;
  align-self: flex-start;
}

.upload-item {
  border: 2px dashed var(--border-color-primary);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.2s ease;
  background: var(--bg-color-primary);
}

.upload-item:hover,
.upload-item.drag-over {
  border-color: var(--primary-color);
}

.upload-item.uploading {
  border-color: var(--primary-color);
  background-color: rgba(255, 71, 87, 0.05);
  cursor: not-allowed;
  opacity: 0.7;
}

.upload-icon.uploading {
  animation: spin 1s linear infinite;
  color: var(--primary-color);
}

.image-item {
  transition: all 0.2s ease;
  cursor: move;
  user-select: none;
}

.image-item:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}

.image-item.dragging {
  opacity: 0.5;
  transform: scale(1.05) rotate(5deg);
  z-index: 1000;
  box-shadow: 0 8px 25px rgba(0, 0, 0, 0.3);
}

.image-item.touch-dragging {
  opacity: 0.8;
  transform: scale(1.6) rotate(3deg);
  z-index: 1000;
}

.image-item.long-pressing {
  transform: scale(0.95);
}

@media (max-width: 768px) {
  .image-item {
    touch-action: pan-y;
  }

  .image-item.touch-dragging {
    touch-action: none;
    transform: rotate(2deg);
  }

  .image-item.long-pressing {
    transform: scale(0.9);
  }

  .image-overlay {
    pointer-events: none;
  }

  .image-overlay .action-btn {
    pointer-events: auto;
  }

  .upload-grid {
    user-select: none;
  }
}

.upload-placeholder {
  text-align: center;
  color: var(--text-color-secondary);
}

.upload-icon {
  width: 24px;
  height: 24px;
  margin-bottom: 5px;
  color: var(--text-color-secondary);
}

.upload-placeholder p {
  margin: 2px 0;
  font-size: 12px;
}

.upload-hint {
  color: var(--text-color-secondary);
  font-size: 10px !important;
}

.drag-hint {
  color: var(--text-color-secondary);
  font-size: 10px !important;
  margin-top: 4px;
}

.upload-loading {
  text-align: center;
  color: var(--primary-color);
}

.loading-icon {
  width: 20px;
  height: 20px;
  margin-bottom: 5px;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  from {
    transform: rotate(0deg);
  }

  to {
    transform: rotate(360deg);
  }
}

.upload-loading p {
  margin: 2px 0;
  font-size: 12px;
}

.error-message {
  color: var(--primary-color);
  font-size: 12px;
  margin-bottom: 10px;
}

.upload-tips {
  font-size: 12px;
  color: var(--text-color-secondary);
  line-height: 1.4;
}

.upload-tips p {
  margin: 2px 0;
}

.drag-tip .mobile-tip {
  display: none;
}

.drag-tip .desktop-tip {
  display: inline;
}

@media (max-width: 768px) {
  .drag-tip .mobile-tip {
    display: inline;
  }

  .drag-tip .desktop-tip {
    display: none;
  }
}
</style>