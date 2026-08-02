import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import {
  getSavedTheme,
  setTheme as setThemeUtil,
  getSystemTheme,
  themeOptions
} from '@/utils/themeUtils'

export const useThemeStore = defineStore('theme', () => {
  const currentTheme = ref(getSavedTheme())

  const actualTheme = computed(() => {
    if (currentTheme.value === 'system') {
      return getSystemTheme()
    }
    return currentTheme.value
  })

  const isDark = computed(() => actualTheme.value === 'dark')

  const isLight = computed(() => actualTheme.value === 'light')

  const isSystem = computed(() => currentTheme.value === 'system')

  const setTheme = (theme) => {
    currentTheme.value = theme
    setThemeUtil(theme)
  }

  const toggleTheme = () => {
    const currentIndex = themeOptions.findIndex(option => option.value === currentTheme.value)
    const nextIndex = (currentIndex + 1) % themeOptions.length
    setTheme(themeOptions[nextIndex].value)
  }

  const toggleTwoTheme = () => {
    setTheme(currentTheme.value === 'light' ? 'dark' : 'light')
  }

  const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
  const handleSystemThemeChange = () => {
    if (currentTheme.value === 'system') {
      setThemeUtil('system')
    }
  }

  mediaQuery.addEventListener('change', handleSystemThemeChange)

  return {
    currentTheme,
    actualTheme,
    isDark,
    isLight,
    isSystem,

    setTheme,
    toggleTheme,
    toggleTwoTheme,
    themeOptions
  }
})