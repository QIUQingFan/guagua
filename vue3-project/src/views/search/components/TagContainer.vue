<script setup>
import { ref, watch, onMounted, onUnmounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useScroll } from '@vueuse/core'
import { useNavigationStore } from '@/stores/navigation'
import TabContainer from '@/components/TabContainer.vue'

const route = useRoute()
const router = useRouter()
const navigationStore = useNavigationStore()

const { y: scrollY } = useScroll(window)

const props = defineProps({
  tagStats: {
    type: Array,
    default: () => []
  },
  activeTag: {
    type: String,
    default: ''
  },
  activeTab: {
    type: String,
    default: 'all'
  }
})

const emit = defineEmits(['tag-reload'])

const isAnimating = ref(false)
const pendingTagId = ref(null)
const currentRequestTagId = ref(null)
const animationTimer = ref(null)

const tagTabs = computed(() => {
  const tabs = [
    { id: '', label: '全部', count: 0 }
  ]

  if (props.tagStats && props.tagStats.length > 0) {
    tabs.push(...props.tagStats.map(tag => ({
      id: tag.id,
      label: tag.label,
      count: tag.count
    })))
  }

  return tabs
})

const shouldShowTags = computed(() => {
  return tagTabs.value.length > 1 && (props.activeTab === 'all' || props.activeTab === 'posts' || props.activeTab === 'videos')
})

function handleTagChange(item) {
  if (props.activeTag === item.id) return
  navigationStore.scrollToTop('instant')

  if (isAnimating.value) {
    pendingTagId.value = item.id
    return
  }

  startTagSwitch(item)
}

function startTagSwitch(item) {
  isAnimating.value = true
  currentRequestTagId.value = item.id
  pendingTagId.value = null

  emit('tag-reload')

  const query = { ...route.query }
  if (item.id) {
    query.tag = item.id
  } else {
    delete query.tag
  }

  router.push({ query }).then(() => {
    animationTimer.value = setTimeout(() => {
      isAnimating.value = false

      if (pendingTagId.value && pendingTagId.value !== currentRequestTagId.value) {
        const targetTag = tagTabs.value.find(tag => tag.id === pendingTagId.value)
        if (targetTag) {
          startTagSwitch(targetTag)
          return
        }
      }

      currentRequestTagId.value = null
      pendingTagId.value = null
    }, 700)
  })
}

onUnmounted(() => {
  if (animationTimer.value) {
    clearTimeout(animationTimer.value)
  }
})
</script>

<template>

  <template v-if="shouldShowTags">

    <div class="tag-container">
      <TabContainer :tabs="tagTabs" :activeTab="activeTag" :enableDrag="true" @tab-change="handleTagChange" />
    </div>

    <div class="fixed-tag-container" :class="{ hidden: scrollY < 100 }">
      <TabContainer :tabs="tagTabs" :activeTab="activeTag" :enableDrag="true" @tab-change="handleTagChange" />
    </div>
  </template>
</template>

<style scoped>
.tag-container {
  background: var(--bg-color-primary);
  width: 100%;
  border-bottom: none;
  transition: background 0.2s ease;
}

.fixed-tag-container {
  position: fixed;
  top: 72px;
  left: 50%;
  transform: translateX(-50%);
  width: 100%;
  max-width: 1200px;
  padding: 0 10px;
  background: var(--bg-color-primary);
  z-index: 50;
  transition: background-color 0.2s ease;
}

.hidden {
  display: none;
}

@media (min-width: 961px) {
  .fixed-tag-container {
    left: calc(50% + 114px);
    width: calc(100% - 228px);
  }
}
</style>