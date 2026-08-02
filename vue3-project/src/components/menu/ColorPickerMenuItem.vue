<template>
  <div class="color-picker-menu-item">
    <div class="color-item-content">
      <span class="color-label">主题色</span>
      <div class="color-picker-container">
        <div class="color-picker-wrapper">
          <input 
            type="color" 
            :value="currentColor" 
            @input="handleColorChange"
            class="color-input"
            ref="colorInput"
          />
          <div 
            class="color-display" 
            :style="{ backgroundColor: currentColor }"
            @click="openColorPicker"
          ></div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'

const colorInput = ref(null)
const currentColor = ref('#dc1257') 

const getCurrentThemeColor = () => {
  const rootStyles = getComputedStyle(document.documentElement)
  const primaryColor = rootStyles.getPropertyValue('--primary-color').trim()
  return primaryColor || '#ff2e4d'
}

const openColorPicker = () => {
  colorInput.value?.click()
}

const handleColorChange = (event) => {
  const newColor = event.target.value
  currentColor.value = newColor
  updateThemeColors(newColor)
}

const updateThemeColors = (baseColor) => {
  const root = document.documentElement
  
  const hexToRgb = (hex) => {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex)
    return result ? {
      r: parseInt(result[1], 16),
      g: parseInt(result[2], 16),
      b: parseInt(result[3], 16)
    } : null
  }
  
  const adjustBrightness = (hex, percent) => {
    const rgb = hexToRgb(hex)
    if (!rgb) return hex
    
    const adjust = (color) => {
      const adjusted = Math.round(color * (1 + percent / 100))
      return Math.max(0, Math.min(255, adjusted))
    }
    
    const r = adjust(rgb.r)
    const g = adjust(rgb.g)
    const b = adjust(rgb.b)
    
    return `#${((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1)}`
  }
  
  root.style.setProperty('--primary-color', baseColor)
  
  const darkColor = adjustBrightness(baseColor, -10)
  root.style.setProperty('--primary-color-dark', darkColor)
  
  const rgb = hexToRgb(darkColor)
  if (rgb) {
    const shadowColor = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.3)`
    root.style.setProperty('--primary-color-shadow', shadowColor)
  }
  
  localStorage.setItem('theme-color', baseColor)
}

onMounted(() => {
  const savedColor = localStorage.getItem('theme-color')
  if (savedColor) {
    currentColor.value = savedColor
    updateThemeColors(savedColor)
  } else {
    currentColor.value = getCurrentThemeColor()
  }
})
</script>

<style scoped>
.color-picker-menu-item {
  padding:4px;
  margin: 0 5px;
  border-radius: 999px;
}

.color-item-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 4px 10px;
  gap: 20px;
}

.color-label {
  font-size: 16px;
  color: var(--text-color-primary);
  font-weight: 400;
  flex-shrink: 0;
}

.color-picker-container {
  display: inline-block;
  flex-shrink: 0;
}

.color-picker-wrapper {
  position: relative;
  display: inline-block;
}

.color-input {
  position: absolute;
  opacity: 0;
  width: 0;
  height: 0;
  pointer-events: none;
}

.color-display {
  width: 32px;
  margin-right: 20px;
  height: 32px;
  border-radius: 50%;
  border: 1px solid var(--border-color-secondary);
  cursor: pointer;
  transition: box-shadow 0.2s ease,transform 0.2s ease;
}

.color-display:hover {
  transform: scale(1.05);
}

.color-display:active {
  transform: scale(0.90);
  box-shadow: 0 0 0 1px var(--primary-color);
}
</style>