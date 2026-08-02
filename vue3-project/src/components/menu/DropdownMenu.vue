<script setup>
import { ref, onMounted, onUnmounted, provide } from 'vue'

const props = defineProps({
  direction: {
    type: String,
    default: 'down'
  },
  menuClass: {
    type: String,
    default: ''
  }
})

const isOpen = ref(false)
const dropdownRef = ref(null)

const toggleDropdown = () => {
  isOpen.value = !isOpen.value
}

const closeDropdown = () => {
  isOpen.value = false
}

const handleClickOutside = (event) => {
  if (dropdownRef.value && !dropdownRef.value.contains(event.target)) {
    closeDropdown()
  }
}

onMounted(() => {
  document.addEventListener('click', handleClickOutside)
})

provide('closeDropdown', closeDropdown)

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside)
})
</script>

<template>
  <div class="dropdown-container" ref="dropdownRef">

    <div class="dropdown-trigger" @click="toggleDropdown">
      <slot name="trigger"></slot>
    </div>

    <Transition name="dropdown">
      <div v-if="isOpen" class="dropdown-menu" :class="[
        direction === 'up' ? 'dropdown-up' : 'dropdown-down',
        menuClass
      ]">
        <slot name="menu"></slot>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.dropdown-container {
  position: relative;
}

.dropdown-trigger {
  cursor: pointer;
}

.dropdown-menu {
  position: absolute;
  z-index: 1000;
  min-width: 200px;
  background: var(--bg-color-primary);
  border: 1px solid var(--border-color-primary);
  border-radius: 8px;
  box-shadow: 0 4px 12px var(--shadow-color);
  padding: 2px 0;
  backdrop-filter: blur(10px);
}

.dropdown-down {
  top: 100%;
  margin-top: 4px;
  right: 0;
}

.dropdown-up {
  bottom: 100%;
  margin-bottom: 4px;
  right: 0;
}

.dropdown-enter-active,
.dropdown-leave-active {
  transition: all 0.2s ease;
  transform-origin: top right;
}

.dropdown-enter-from {
  opacity: 0;
  transform: scale(0.95) translateY(-8px);
}

.dropdown-leave-to {
  opacity: 0;
  transform: scale(0.95) translateY(-8px);
}

.dropdown-up.dropdown-enter-active,
.dropdown-up.dropdown-leave-active {
  transform-origin: bottom right;
}

.dropdown-up.dropdown-enter-from {
  opacity: 0;
  transform: scale(0.95) translateY(8px);
}

.dropdown-up.dropdown-leave-to {
  opacity: 0;
  transform: scale(0.95) translateY(8px);
}
</style>