<template>
  <div class="skeleton-wrapper" :class="wrapperClass">

    <div v-if="type === 'user-card'" class="skeleton-user-card">
      <div class="skeleton-avatar" :style="avatarStyle"></div>
      <div class="skeleton-info">
        <div class="skeleton-line" :style="{ width: '80px', height: '16px', marginBottom: '6px' }"></div>
        <div class="skeleton-line" :style="{ width: '120px', height: '12px', marginBottom: '8px' }"></div>
        <div v-if="showStats" class="skeleton-stats">
          <div class="skeleton-line" :style="{ width: '60px', height: '12px' }"></div>
          <div class="skeleton-line" :style="{ width: '60px', height: '12px' }"></div>
        </div>
      </div>
      <div v-if="showButton" class="skeleton-button"></div>
    </div>

    <div v-else-if="type === 'image-card'" class="skeleton-image-card">
      <div class="skeleton-image" :style="{ height: imageHeight }"></div>
      <div class="skeleton-line" :style="{ width: '90%', height: '14px', margin: '8px 0' }"></div>
      <div class="skeleton-footer">
        <div class="skeleton-avatar" :style="{ width: '24px', height: '24px' }"></div>
        <div class="skeleton-line" :style="{ width: '60px', height: '12px' }"></div>
        <div class="skeleton-line" :style="{ width: '40px', height: '12px', marginLeft: 'auto' }"></div>
      </div>
    </div>

    <div v-else-if="type === 'user-item'" class="skeleton-user-item">
      <div class="skeleton-avatar" :style="avatarStyle"></div>
      <div class="skeleton-info">
        <div class="skeleton-line" :style="{ width: '60%', height: '16px', marginBottom: '6px' }"></div>
        <div class="skeleton-line" :style="{ width: '40%', height: '12px' }"></div>
      </div>
    </div>

    <div v-else-if="type === 'custom'" class="skeleton-custom">
      <slot></slot>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
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
    type: String,
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
  wrapperClass: {
    type: String,
    default: ''
  },
  animation: {
    type: String,
    default: 'shimmer',
    validator: (value) => ['shimmer', 'pulse', 'none'].includes(value)
  }
})

const avatarStyle = computed(() => ({
  width: props.avatarSize,
  height: props.avatarSize
}))
</script>

<style scoped>
.skeleton-wrapper {
  --skeleton-bg: var(--bg-color-secondary);
  --skeleton-highlight: var(--bg-color-tertiary);
}

.skeleton-avatar,
.skeleton-line,
.skeleton-image,
.skeleton-button {
  background: linear-gradient(90deg, var(--skeleton-bg) 25%, var(--skeleton-highlight) 37%, var(--skeleton-bg) 63%);
  background-size: 200% 100%;
  border-radius: 4px;
  position: relative;
  overflow: hidden;
}

.skeleton-avatar {
  border-radius: 50%;
  flex-shrink: 0;
}

.skeleton-button {
  width: 72px;
  height: 32px;
  border-radius: 20px;
  margin-left: 12px;
  flex-shrink: 0;
}

.skeleton-image {
  width: 100%;
  border-radius: 10px;
  background-size: 200px 100%;
  min-height: 300px;
}

.skeleton-wrapper:not(.no-animation) .skeleton-avatar,
.skeleton-wrapper:not(.no-animation) .skeleton-line,
.skeleton-wrapper:not(.no-animation) .skeleton-image,
.skeleton-wrapper:not(.no-animation) .skeleton-button {
  animation: skeleton-shimmer 1.5s infinite;
}

.skeleton-wrapper.pulse-animation .skeleton-avatar,
.skeleton-wrapper.pulse-animation .skeleton-line,
.skeleton-wrapper.pulse-animation .skeleton-image,
.skeleton-wrapper.pulse-animation .skeleton-button {
  animation: skeleton-pulse 1.5s ease-in-out infinite;
}

.skeleton-user-card {
  display: flex;
  align-items: center;
  padding: 16px;
  border-radius: 12px;
  border: 1px solid var(--border-color-primary);
  background: var(--bg-color-primary);
}

.skeleton-user-card .skeleton-avatar {
  margin-right: 12px;
}

.skeleton-user-card .skeleton-info {
  flex: 1;
  min-width: 0;
}

.skeleton-user-card .skeleton-stats {
  display: flex;
  gap: 16px;
}

.skeleton-image-card {
  width: 100%;
  box-sizing: border-box;
  background-color: var(--bg-color-primary);
  border-radius: 10px;
  overflow: hidden;
  padding: 0;
}

.skeleton-image-card .skeleton-footer {
  display: flex;
  align-items: center;
  padding: 8px 12px;
  gap: 8px;
}

.skeleton-user-item {
  display: flex;
  align-items: center;
  padding: 12px 20px;
  height: 64px;
  box-sizing: border-box;
}

.skeleton-user-item .skeleton-avatar {
  margin-right: 12px;
}

.skeleton-user-item .skeleton-info {
  flex: 1;
  min-width: 0;
}

@keyframes skeleton-shimmer {
  0% {
    background-position: -200px 0;
  }

  100% {
    background-position: calc(200px + 100%) 0;
  }
}

@keyframes skeleton-pulse {
  0% {
    opacity: 1;
  }

  50% {
    opacity: 0.4;
  }

  100% {
    opacity: 1;
  }
}

@media (max-width: 480px) {
  .skeleton-user-card {
    padding: 12px;
  }

  .skeleton-user-card .skeleton-avatar {
    width: 40px;
    height: 40px;
  }

  .skeleton-user-card .skeleton-stats {
    gap: 12px;
  }

  .skeleton-button {
    width: 64px;
    height: 28px;
  }
}
</style>