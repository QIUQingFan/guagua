<template>
  <div class="content-renderer">
    <div v-if="text" class="content-text">
      <span class="mention-text" v-html="parsedText" @click="handleMentionClick"></span>
    </div>

    <div v-if="images && images.length > 0" class="content-images">
      <div class="images-grid" :class="getGridClass()">
        <div v-for="(image, index) in images" :key="index" class="image-item"
          @click="$emit('image-click', { images: images, index })">
          <img :src="image" :alt="`图片${index + 1}`" class="content-image" @error="handleImageError" v-img-fallback />
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import defaultPlaceholder from '@/assets/imgs/瓜呱.png'

const props = defineProps({
  content: {
    type: String,
    default: ''
  },
  text: {
    type: String,
    default: ''
  }
})

const emit = defineEmits(['image-click'])

const actualContent = computed(() => {
  return props.content || props.text || ''
})

const parsedContent = computed(() => {
  if (!actualContent.value) return { text: '', images: [] }

  const tempDiv = document.createElement('div')
  tempDiv.innerHTML = actualContent.value

  const imgElements = tempDiv.querySelectorAll('img')
  const images = Array.from(imgElements).map(img => img.src)

  imgElements.forEach(img => img.remove())

  let htmlContent = tempDiv.innerHTML
  
  const mentionLinkRegex = /<a[^>]*class="[^"]*mention-link[^"]*"[^>]*>.*?<\/a>/g
  const mentionLinks = []
  let linkIndex = 0
  
  htmlContent = htmlContent.replace(mentionLinkRegex, (match) => {
    const placeholder = `__MENTION_LINK_${linkIndex}__`
    mentionLinks[linkIndex] = match
    linkIndex++
    return placeholder
  })
  
  htmlContent = htmlContent.replace(/<br\s*\/?>/gi, '\n')
  htmlContent = htmlContent.replace(/<\/div><div>/gi, '\n')
  htmlContent = htmlContent.replace(/<div>/gi, '')
  htmlContent = htmlContent.replace(/<\/div>/gi, '')
  htmlContent = htmlContent.replace(/<\/p><p>/gi, '\n')
  htmlContent = htmlContent.replace(/<p>/gi, '')
  htmlContent = htmlContent.replace(/<\/p>/gi, '')
  
  mentionLinks.forEach((link, index) => {
    htmlContent = htmlContent.replace(`__MENTION_LINK_${index}__`, link)
  })

  return { text: htmlContent.trim(), images }
})

const text = computed(() => parsedContent.value.text)
const images = computed(() => parsedContent.value.images)

const parsedText = computed(() => {
  return text.value
})

const handleMentionClick = (event) => {
  const target = event.target

  if (target.classList.contains('mention-link')) {
    event.preventDefault()
    const userId = target.getAttribute('data-user-id')

    if (userId) {
      const userUrl = `${window.location.origin}/user/${userId}`
      window.open(userUrl, '_blank')
    }
  }
}

const getGridClass = () => {
  const count = images.value.length
  if (count === 1) return 'single'
  if (count === 2) return 'double'
  if (count === 3) return 'triple'
  if (count === 4) return 'quad'
  return 'multiple'
}

const handleImageError = (event) => {
  event.target.src = defaultPlaceholder
}
</script>

<style scoped>
.content-renderer {
  width: 100%;
}

.content-text {
  margin-bottom: 8px;
  line-height: 1.5;
  word-wrap: break-word;
}

.mention-text {
  white-space: pre-wrap;
  word-wrap: break-word;
}

:deep(.mention-link) {
  color: var(--text-color-tag);
  text-decoration: none;
  font-weight: 500;
  cursor: pointer;
  transition: color 0.2s ease;
  background: none;
  border: none;
  padding: 0;
}

:deep(.mention-link:hover) {
  color: var(--text-color-tag);
  opacity: 0.8;
}

:deep(.mention-link:active) {
  color: var(--text-color-tag);
  opacity: 0.6;
}

:deep(.mention-link:focus) {
  outline: none;
  box-shadow: none;
  border: none;
}

.content-images {
  margin-top: 8px;
}

.images-grid {
  display: grid;
  gap: 4px;
  border-radius: 8px;
  overflow: hidden;
}

.images-grid.single {
  grid-template-columns: 1fr;
  max-width: 200px;
}

.images-grid.double {
  grid-template-columns: 1fr 1fr;
  max-width: 200px;
}

.images-grid.triple {
  grid-template-columns: 1fr 1fr 1fr;
  max-width: 240px;
}

.images-grid.quad {
  grid-template-columns: 1fr 1fr;
  max-width: 200px;
}

.images-grid.multiple {
  grid-template-columns: repeat(3, 1fr);
  max-width: 240px;
}

.image-item {
  position: relative;
  aspect-ratio: 1;
  cursor: pointer;
  border-radius: 4px;
  overflow: hidden;
  transition: transform 0.2s ease;
}

.image-item:hover {
  transform: scale(1.02);
}

.content-image {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

@media (max-width: 768px) {
  .images-grid.single {
    max-width: 150px;
  }

  .images-grid.double {
    max-width: 150px;
  }

  .images-grid.triple {
    max-width: 180px;
  }

  .images-grid.quad {
    max-width: 150px;
  }

  .images-grid.multiple {
    max-width: 180px;
  }
}
</style>