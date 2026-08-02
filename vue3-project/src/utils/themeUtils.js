/**
 * 主题工具函数
 * 用于管理应用的主题系统
 */

export const getSystemTheme = () => {
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

export const applyTheme = (theme) => {
  let actualTheme = theme
  if (theme === 'system') {
    actualTheme = getSystemTheme()
  }
  document.documentElement.setAttribute('data-theme', actualTheme)
  return actualTheme
}

export const getSavedTheme = () => {
  return localStorage.getItem('theme') || 'system'
}

export const saveTheme = (theme) => {
  localStorage.setItem('theme', theme)
}

export const initTheme = () => {
  const savedTheme = getSavedTheme()
  const appliedTheme = applyTheme(savedTheme)

  
  const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
  const handleSystemThemeChange = () => {
    const currentSavedTheme = getSavedTheme()
    if (currentSavedTheme === 'system') {
      applyTheme('system')
    }
  }

  mediaQuery.addEventListener('change', handleSystemThemeChange)

  return {
    savedTheme,
    appliedTheme,
    cleanup: () => {
      mediaQuery.removeEventListener('change', handleSystemThemeChange)
    }
  }
}

export const setTheme = (theme) => {
  saveTheme(theme)
  return applyTheme(theme)
}

export const themeOptions = [
  {
    value: 'system',
    label: '跟随系统',
    icon: 'setting'
  },
  {
    value: 'light',
    label: '浅色模式',
    icon: 'sun'
  },
  {
    value: 'dark',
    label: '深色模式',
    icon: 'moon'
  }
]