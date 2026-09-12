<script setup>
import { computed } from 'vue'

const props = defineProps({
  avatars: {
    type: Array,
    default: () => []
  },
  size: {
    type: Number,
    default: 48
  },
  fallback: {
    type: String,
    default: ''
  },
  radius: {
    type: Number,
    default: null
  }
})

const defaultAvatar = new URL('@/assets/imgs/瓜呱.png', import.meta.url).href

const validAvatars = computed(() => {
  return (props.avatars || []).filter(a => a && a !== '').slice(0, 9)
})

const displayAvatars = computed(() => {
  if (validAvatars.value.length > 0) return validAvatars.value
  return [props.fallback || defaultAvatar]
})

const gridClass = computed(() => {
  const n = validAvatars.value.length
  if (n <= 1) return 'g-1'
  if (n === 2) return 'g-2'
  if (n === 3) return 'g-3'
  if (n >= 5 && n <= 9) return 'g-9'
  return 'g-4'
})

const borderRadius = computed(() => {
  if (props.radius !== null) return `${props.radius}px`
  return '50%'
})
</script>

<template>
  <div
    class="group-avatar"
    :class="gridClass"
    :style="{
      width: size + 'px',
      height: size + 'px',
      borderRadius: borderRadius
    }"
  >
    <img
      v-for="(avatar, index) in displayAvatars"
      :key="index"
      :src="avatar"
      class="avatar-cell"
      alt="头像"
      v-img-fallback="avatar"
    />
  </div>
</template>

<style scoped>
.group-avatar {
  display: grid;
  gap: 2px;
  overflow: hidden;
  background: var(--bg-color-secondary);
  flex-shrink: 0;
  padding: 2px;
  box-sizing: border-box;
}

.g-1 {
  grid-template-columns: 1fr;
}

.g-1 .avatar-cell {
  width: 100%;
  height: 100%;
  border-radius: 0;
}

.g-2 {
  grid-template-columns: 1fr 1fr;
}

.g-3 {
  grid-template-columns: 1fr 1fr;
  grid-template-rows: 1fr 1fr;
}

.g-3 .avatar-cell:nth-child(1) {
  grid-column: 1 / 2;
  grid-row: 1 / 2;
}

.g-3 .avatar-cell:nth-child(2) {
  grid-column: 2 / 3;
  grid-row: 1 / 2;
}

.g-3 .avatar-cell:nth-child(3) {
  grid-column: 1 / 3;
  grid-row: 2 / 3;
  width: 50%;
  justify-self: center;
  height: 100%;
}

.g-4 {
  grid-template-columns: 1fr 1fr;
  grid-template-rows: 1fr 1fr;
}

.g-9 {
  grid-template-columns: repeat(3, 1fr);
  grid-template-rows: repeat(3, 1fr);
}

.avatar-cell {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}
</style>
