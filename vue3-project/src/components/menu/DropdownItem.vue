<template>
  <div class="dropdown-item" @click="handleClick">
    <div class="dropdown-item-content">
      <slot></slot>
    </div>
  </div>
</template>

<script setup>
import { inject } from 'vue'

const emit = defineEmits(['click'])
const closeDropdown = inject('closeDropdown', null)

const handleClick = () => {
  emit('click')
  if (closeDropdown) {
    closeDropdown()
  }
}
</script>

<style scoped>
.dropdown-item {
  cursor: pointer;
  transition: background-color 0.2s ease;
  border-radius: 8px;
  margin: 2px 4px;
  box-sizing: border-box;
}

.dropdown-item:hover {
  background: var(--bg-color-secondary);
}

.dropdown-item-content {
  display: flex;
  align-items: center;
  padding: 12px 16px;
  color: var(--text-color-primary);
  font-size: 16px;
  line-height: 1;
}
</style>