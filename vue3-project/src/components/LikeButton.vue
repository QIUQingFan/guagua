<template>
  <button :class="[
    'like-button',
    {
      'active': isLiked,
      'small': size === 'small',
      'medium': size === 'medium',
      'large': size === 'large'
    }
  ]" @click="handleClick">
    <span class="like-btn-wrapper">

      <span v-if="showRing" class="like-ring" @animationend="onRingEnd"></span>

      <SvgIcon :name="isLiked ? 'liked' : 'like'" :class="{
        liked: isLiked,
        scaling: scaling
      }" :width="iconSize" :height="iconSize" @animationend="onScaleEnd" />
    </span>
  </button>
</template>

<script setup>
import { ref, computed } from 'vue'
import SvgIcon from './SvgIcon.vue'

const props = defineProps({
  isLiked: {
    type: Boolean,
    default: false
  },
  size: {
    type: String,
    default: 'medium',
    validator: (value) => ['small', 'medium', 'large'].includes(value)
  }
})

const emit = defineEmits(['click'])

const scaling = ref(false)
const showRing = ref(false)

const iconSize = computed(() => {
  const sizeMap = {
    small: '16px',
    medium: '20px',
    large: '24px'
  }
  return sizeMap[props.size]
})

const triggerAnimation = (willBeLiked) => {
  scaling.value = false
  showRing.value = false

  setTimeout(() => {
    scaling.value = true
    if (willBeLiked) {
      showRing.value = true
    }
  }, 0)
}

const handleClick = (event) => {
  const willBeLiked = !props.isLiked
  triggerAnimation(willBeLiked)
  emit('click', willBeLiked, event)
}

const onScaleEnd = () => {
  scaling.value = false
}

const onRingEnd = () => {
  showRing.value = false
}
</script>

<style scoped>
.like-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: none;
  border: none;
  cursor: pointer;
  color: var(--text-color-secondary);
  transition: color 0.2s ease;
  padding: 4px;
  border-radius: 4px;
  padding: 2px;
}

.like-button:hover {
  color: var(--text-color-primary);
}

.like-btn-wrapper {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.scaling {
  animation: likeScale 0.5s linear both;
}

.like-ring {
  position: absolute;
  left: 50%;
  top: 50%;
  width: 20px;
  height: 20px;
  border-radius: 50%;
  border: 1px solid #ff4757;
  background: transparent;
  transform: translate(-50%, -50%) scale(0);
  animation: likeRing 0.6s ease-out;
  pointer-events: none;
}

.like-button.small .like-ring {
  width: 16px;
  height: 16px;
}

.like-button.medium .like-ring {
  width: 20px;
  height: 20px;
}

.like-button.large .like-ring {
  width: 24px;
  height: 24px;
}

@keyframes likeScale {
  0% {
    transform: scale(1);
  }

  30% {
    transform: scale(0.5);
  }

  50% {
    transform: scale(1.2);
  }

  80% {
    transform: scale(0.9);
  }

  100% {
    transform: scale(1);
  }
}

@keyframes likeRing {
  0% {
    transform: translate(-50%, -50%) scale(0);
    opacity: 1;
  }

  100% {
    transform: translate(-50%, -50%) scale(2);
    opacity: 0;
  }
}
</style>