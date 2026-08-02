/**
 * 防滚动穿透的统一解决方案
 * 当模态框打开时，直接禁用底层页面的滚动
 */
import { ref, onUnmounted } from 'vue'

const lockCount = ref(0)
let originalBodyStyle = ''

/**
 * 锁定页面滚动
 */
const lockScroll = () => {
  if (lockCount.value === 0) {
    originalBodyStyle = document.body.style.cssText
    
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop
    
    document.body.style.cssText = `
      ${originalBodyStyle}
      position: fixed;
      top: -${scrollTop}px;
      left: 0;
      right: 0;
      width: 100%;
      overflow: hidden;
    `
  }
  lockCount.value++
}

/**
 * 解锁页面滚动
 */
const unlockScroll = () => {
  if (lockCount.value > 0) {
    lockCount.value--
    
    if (lockCount.value === 0) {
      const scrollTop = Math.abs(parseInt(document.body.style.top) || 0)
      
      document.body.style.cssText = originalBodyStyle
      
      window.scrollTo(0, scrollTop)
    }
  }
}

/**
 * 使用滚动锁定的组合式函数
 */
export function useScrollLock() {
  let isLocked = false
  
  const lock = () => {
    if (!isLocked) {
      lockScroll()
      isLocked = true
    }
  }
  
  const unlock = () => {
    if (isLocked) {
      unlockScroll()
      isLocked = false
    }
  }
  
  onUnmounted(() => {
    unlock()
  })
  
  return {
    lock,
    unlock,
    isLocked: () => isLocked
  }
}