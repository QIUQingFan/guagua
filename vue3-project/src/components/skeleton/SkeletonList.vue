<template>
  <div class="skeleton-list" :class="listClass">
    <BaseSkeleton v-for="index in count" :key="index" :type="type" :avatar-size="avatarSize"
      :image-height="getImageHeight(index)" :show-stats="showStats" :show-button="showButton" :wrapper-class="itemClass"
      :animation="animation">
      <slot v-if="type === 'custom'" :index="index"></slot>
    </BaseSkeleton>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import BaseSkeleton from '@/components/skeleton/BaseSkeleton.vue'

const props = defineProps({
  count: {
    type: Number,
    default: 6
  },
  type: {
    type: String,
    default: 'user-card',
    validator: (value) => ['user-card', 'image-card', 'user-item', 'custom'].includes(value)
  },
  avatarSize: {
    type: String,
    default: '48px'
  },
  imageHeight: {
    type: [String, Array],
    default: '200px'
  },
  showStats: {
    type: Boolean,
    default: true
  },
  showButton: {
    type: Boolean,
    default: true
  },
  layout: {
    type: String,
    default: 'vertical',
    validator: (value) => ['vertical', 'grid', 'waterfall'].includes(value)
  },
  listClass: {
    type: String,
    default: ''
  },
  itemClass: {
    type: String,
    default: ''
  },
  animation: {
    type: String,
    default: 'shimmer',
    validator: (value) => ['shimmer', 'pulse', 'none'].includes(value)
  }
})

const getImageHeight = (index) => {
  if (props.type !== 'image-card') return props.imageHeight

  if (Array.isArray(props.imageHeight)) {
    return props.imageHeight[index % props.imageHeight.length]
  }

  if (props.imageHeight === 'random') {
    if (window.innerWidth <= 480) {
      const heights = ['120px', '140px', '160px', '180px', '150px', '170px']
      return heights[index % heights.length]
    } else if (window.innerWidth <= 768) {
      const heights = ['150px', '180px', '210px', '240px', '190px', '220px']
      return heights[index % heights.length]
    } else {
      const heights = ['180px', '220px', '260px', '300px', '240px', '280px']
      return heights[index % heights.length]
    }
  }

  return props.imageHeight
}
</script>

<style scoped>
.skeleton-list {
  padding: 0;
  margin: 0;
}

.skeleton-list:not(.grid-layout):not(.waterfall-layout) {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.skeleton-list.grid-layout {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 15px;
}

.skeleton-list.waterfall-layout {
  column-count: 2;
  column-gap: 10px;
  list-style: none;
}

.skeleton-list.waterfall-layout>* {
  break-inside: avoid;
  margin-bottom: 10px;
}

@media (min-width: 960px) {
  .skeleton-list.waterfall-layout {
    column-count: 4;
    column-gap: 15px;
  }
}

@media (max-width: 480px) {
  .skeleton-list.grid-layout {
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
    gap: 10px;
  }

  .skeleton-list:not(.grid-layout):not(.waterfall-layout) {
    gap: 8px;
  }
}
</style>