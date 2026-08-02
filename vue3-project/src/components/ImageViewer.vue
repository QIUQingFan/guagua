<template>
  <Transition name="fade" appear>
    <div v-if="visible" class="image-viewer-overlay" @click="handleOverlayClick" @keydown="handleKeydown" tabindex="0">
      <div class="image-viewer-container" @click.stop>
        <button class="close-btn" @click.stop="closeViewer" aria-label="关闭图片查看器">
          <SvgIcon name="close" :width="24" :height="24" />
        </button>

        <div v-if="images.length > 1" class="image-counter">
          {{ currentIndex + 1 }} / {{ images.length }}
        </div>

        <div class="image-content" @click="handleImageClick" @touchstart="handleTouchStart" @touchmove="handleTouchMove"
          @touchend="handleTouchEnd">
          <div class="image-slider" :style="{ transform: `translateX(-${currentIndex * 100}%)` }">
            <div v-for="(image, index) in images" :key="index" class="image-slide">
              <img :src="getImageSrc(image)" :alt="getImageAlt(image, index)" class="viewer-image"
                @load="preloadAdjacentImages(index)" @error="handleImageError(index)" v-img-fallback />
            </div>
          </div>
        </div>

        <template v-if="images.length > 1">
          <button class="nav-btn prev-btn" :class="{ disabled: currentIndex === 0 }" @click.stop="prevImage"
            :disabled="currentIndex === 0" aria-label="上一张图片">
            <SvgIcon name="left" :width="24" :height="24" />
          </button>
          <button class="nav-btn next-btn" :class="{ disabled: currentIndex === images.length - 1 }" @click.stop="nextImage"
            :disabled="currentIndex === images.length - 1" aria-label="下一张图片">
            <SvgIcon name="right" :width="24" :height="24" />
          </button>
        </template>
      </div>
    </div>
  </Transition>
</template>

<script setup>
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from 'vue'
import SvgIcon from '@/components/SvgIcon.vue'
import { useScrollLock } from '@/composables/useScrollLock'
import { getImageUrl as utilGetImageSrc } from '@/utils/imageUtils'

const props = defineProps({
  visible: {
    type: Boolean,
    default: false
  },
  images: {
    type: Array,
    default: () => []
  },
  initialIndex: {
    type: Number,
    default: 0
  },
  imageType: {
    type: String,
    default: 'post', 
    validator: (value) => ['post', 'comment', 'avatar'].includes(value)
  },
  userId: {
    type: [String, Number],
    default: null
  },
  closeOnOverlay: {
    type: Boolean,
    default: true
  }
})

const emit = defineEmits(['close', 'change'])

const { lock, unlock } = useScrollLock()
const currentIndex = ref(0)
const preloadedImages = ref(new Set())

const touchStartX = ref(0)
const touchStartY = ref(0)
const touchEndX = ref(0)
const touchEndY = ref(0)
const minSwipeDistance = 50
const SWIPE_THRESHOLD = 10

watch(() => props.visible, (newVisible) => {
  if (newVisible) {
    lock()
    currentIndex.value = Math.max(0, Math.min(props.initialIndex, props.images.length - 1))
    nextTick(() => {
      preloadAdjacentImages(currentIndex.value)
    })
  } else {
    unlock()
    preloadedImages.value.clear()
  }
})

watch(currentIndex, (newIndex) => {
  emit('change', newIndex)
  preloadAdjacentImages(newIndex)
})

const getImageSrc = (image) => {
  if (typeof image === 'string') {
    return image
  }
  if (typeof image === 'object') {
    const url = image.url || image.src || image.image_url || image.thumbnailUrl || image.hoverUrl
    if (url) {
      return url
    }
    if (image.thumbnailUrl || image.hoverUrl) {
      return utilGetImageSrc(image, '')
    }
  }
  return ''
}

const getImageAlt = (image, index) => {
  if (typeof image === 'object' && image.alt) {
    return image.alt
  }
  switch (props.imageType) {
    case 'avatar':
      return '用户头像'
    case 'comment':
      return `评论图片 ${index + 1}`
    case 'post':
    default:
      return `帖子图片 ${index + 1}`
  }
}

const preloadAdjacentImages = (index) => {
  const indicesToPreload = []

  if (index > 0) {
    indicesToPreload.push(index - 1)
  }

  if (index < props.images.length - 1) {
    indicesToPreload.push(index + 1)
  }

  indicesToPreload.forEach(i => {
    if (!preloadedImages.value.has(i)) {
      const img = new Image()
      img.src = getImageSrc(props.images[i])
      img.onload = () => preloadedImages.value.add(i)
    }
  })
}

const handleImageError = (index) => {
  console.warn(`图片加载失败: ${getImageSrc(props.images[index])}`)
}

const prevImage = (event) => {
  if (event) {
    event.preventDefault()
    event.stopPropagation()
  }
  if (currentIndex.value > 0) {
    currentIndex.value--
  }
}

const nextImage = (event) => {
  if (event) {
    event.preventDefault()
    event.stopPropagation()
  }
  if (currentIndex.value < props.images.length - 1) {
    currentIndex.value++
  }
}

const closeViewer = () => {
  emit('close')
}

const handleOverlayClick = () => {
  if (props.closeOnOverlay) {
    closeViewer()
  }
}

const handleImageClick = (event) => {
  const rect = event.currentTarget.getBoundingClientRect()
  const clickX = event.clientX - rect.left
  const clickY = event.clientY - rect.top

  const safeZoneWidth = 100
  const centerY = rect.height / 2
  const safeZoneHeight = 100

  const isInLeftSafeZone = clickX < safeZoneWidth &&
    Math.abs(clickY - centerY) < safeZoneHeight / 2
  const isInRightSafeZone = clickX > (rect.width - safeZoneWidth) &&
    Math.abs(clickY - centerY) < safeZoneHeight / 2

  if (!isInLeftSafeZone && !isInRightSafeZone && props.closeOnOverlay) {
    closeViewer()
  }
}

const handleKeydown = (event) => {
  const activeElement = document.activeElement
  if (activeElement && (
    activeElement.tagName === 'INPUT' ||
    activeElement.tagName === 'TEXTAREA' ||
    activeElement.contentEditable === 'true'
  )) {
    return 
  }

  switch (event.key) {
    case 'Escape':
      event.preventDefault()
      event.stopPropagation()
      closeViewer()
      break
    case 'ArrowLeft':
      event.preventDefault()
      event.stopPropagation()
      prevImage(event)
      break
    case 'ArrowRight':
      event.preventDefault()
      event.stopPropagation()
      nextImage(event)
      break
  }
}

onMounted(() => {
  document.addEventListener('keydown', handleKeydown, true)
})

const handleTouchStart = (e) => {
  touchStartX.value = e.touches[0].clientX
  touchStartY.value = e.touches[0].clientY
}

const handleTouchMove = (e) => {
  const touchMoveX = e.touches[0].clientX
  const touchMoveY = e.touches[0].clientY

  const deltaX = Math.abs(touchMoveX - touchStartX.value)
  const deltaY = Math.abs(touchMoveY - touchStartY.value)

  if (deltaX > deltaY && deltaX > SWIPE_THRESHOLD) {
    e.preventDefault()
  }
}

const handleTouchEnd = (e) => {
  touchEndX.value = e.changedTouches[0].clientX
  touchEndY.value = e.changedTouches[0].clientY

  const deltaX = touchEndX.value - touchStartX.value
  const deltaY = touchEndY.value - touchStartY.value

  if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > minSwipeDistance) {
    if (deltaX > 0) {
      prevImage()
    } else {
      nextImage()
    }
  }

  touchStartX.value = 0
  touchStartY.value = 0
}

onUnmounted(() => {
  document.removeEventListener('keydown', handleKeydown, true)
})
</script>

<style scoped>
.image-viewer-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.7);
  backdrop-filter: blur(14px);
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  outline: none;
}

.image-viewer-container {
  position: relative;
  width: 100vw;
  height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
}

.close-btn {
  position: absolute;
  top: 20px;
  left: 20px;
  z-index: 3001;
  background: rgba(152, 152, 152, 0.5);
  border: none;
  color: white;
  width: 48px;
  height: 48px;
  border-radius: 50%;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
  backdrop-filter: blur(4px);
}

.close-btn:hover {
  background: rgba(87, 87, 87, 0.7);
}

.image-counter {
  position: absolute;
  top: 20px;
  right: 20px;
  z-index: 3001;
  background: rgba(152, 152, 152, 0.5);
  color: white;
  padding: 8px 16px;
  border-radius: 20px;
  font-size: 16px;
  font-weight: 500;
  backdrop-filter: blur(4px);
}

.image-content {
  width: 100%;
  height: 100%;
  overflow: hidden;
}

.image-slider {
  display: flex;
  width: 100%;
  height: 100%;
  transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1);
}

.image-slide {
  flex: 0 0 100%;
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
}

.viewer-image {
  width: 100%;
  height: 100vh;
  object-fit: contain;
  cursor: zoom-out;
  transition: none;
}

.viewer-image:hover {
  cursor: zoom-out;
}

.nav-btn {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  width: 56px;
  height: 56px;
  border-radius: 50%;
  background: rgba(152, 152, 152, 0.5);
  border: none;
  color: white;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.3s ease;
  z-index: 3001;
  pointer-events: auto;
  opacity: 0.8;
}

.nav-btn:hover:not(.disabled) {
  background: rgba(87, 87, 87, 0.7);
  opacity: 1;
}

.nav-btn.disabled {
  opacity: 0.3;
}

.prev-btn {
  left: 20px;
}

.next-btn {
  right: 20px;
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

@media (max-width: 768px) {
  .image-viewer-container {
    width: 100vw;
    height: 100vh;
  }

  .close-btn {
    top: 8px;
    left: 8px;
    width: 40px;
    height: 40px;
  }

  .image-counter {
    top: 16px;
    right: 16px;
    padding: 6px 12px;
    font-size: 14px;
  }

  .nav-btn {
    width: 40px;
    height: 40px;
  }

  .prev-btn {
    left: 10px;
  }

  .next-btn {
    right: 10px;
  }
}
</style>