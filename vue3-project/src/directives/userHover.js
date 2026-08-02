import { createApp } from 'vue'
import UserInfoCard from '@/components/UserInfoCard.vue'
import messageManager from '@/utils/messageManager'
import router from '@/router'

function isMobileDevice() {
  return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) || 
         ('ontouchstart' in window) || 
         (navigator.maxTouchPoints > 0)
}

export const vUserHover = {
  mounted(el, binding) {
    if (isMobileDevice()) {
      return
    }

    let cardInstance = null
    let cardElement = null
    let hoverTimer = null
    let leaveTimer = null

    const handleMouseEnter = async (event) => {
      if (leaveTimer) {
        clearTimeout(leaveTimer)
        leaveTimer = null
      }

      hoverTimer = setTimeout(async () => {
        try {
          const userInfo = await binding.value.getUserInfo()

          if (!cardInstance) {
            const cardApp = createApp(UserInfoCard, {
              visible: true,
              userInfo: userInfo,
              onFollow: binding.value.onFollow || (() => { }),
              onUnfollow: binding.value.onUnfollow || (() => { }),
              onClick: () => {
                hideCard()
              }
            })

            cardApp.provide('$message', messageManager)
            cardApp.use(router)

            cardElement = document.createElement('div')
            document.body.appendChild(cardElement)

            cardInstance = cardApp.mount(cardElement)
          }

          const rect = el.getBoundingClientRect()
          const cardWidth = 360
          const cardHeight = 300 
          const gap = 12 
          const padding = 16 

          let left = rect.right + gap
          let top = rect.top + rect.height / 2 - cardHeight / 2

          if (top < padding) top = padding
          if (top + cardHeight > window.innerHeight - padding) {
            top = window.innerHeight - cardHeight - padding
          }

          cardElement.style.position = 'fixed'
          cardElement.style.left = `${left}px`
          cardElement.style.top = `${top}px`
          cardElement.style.zIndex = '1000'

          cardElement.addEventListener('mouseenter', handleCardMouseEnter)
          cardElement.addEventListener('mouseleave', handleCardMouseLeave)

        } catch (error) {
          console.error('获取用户信息失败:', error)
        }
      }, binding.value.delay || 500)
    }

    const handleMouseLeave = () => {
      if (hoverTimer) {
        clearTimeout(hoverTimer)
        hoverTimer = null
      }

      leaveTimer = setTimeout(() => {
        hideCard()
      }, 200)
    }

    const handleCardMouseEnter = () => {
      if (leaveTimer) {
        clearTimeout(leaveTimer)
        leaveTimer = null
      }
    }

    const handleCardMouseLeave = () => {
      leaveTimer = setTimeout(() => {
        hideCard()
      }, 200)
    }

    const hideCard = () => {
      if (cardInstance && cardElement) {
        cardElement.removeEventListener('mouseenter', handleCardMouseEnter)
        cardElement.removeEventListener('mouseleave', handleCardMouseLeave)

        if (cardElement.firstChild) {
          cardElement.firstChild.style.display = 'none'
        }

        setTimeout(() => {
          if (cardElement && cardElement.parentNode) {
            cardElement.parentNode.removeChild(cardElement)
          }
          if (cardInstance && cardInstance.unmount) {
            cardInstance.unmount()
          }
          cardInstance = null
          cardElement = null
        }, 100)
      }
    }

    el.addEventListener('mouseenter', handleMouseEnter)
    el.addEventListener('mouseleave', handleMouseLeave)

    el._userHoverCleanup = () => {
      el.removeEventListener('mouseenter', handleMouseEnter)
      el.removeEventListener('mouseleave', handleMouseLeave)

      if (hoverTimer) {
        clearTimeout(hoverTimer)
      }
      if (leaveTimer) {
        clearTimeout(leaveTimer)
      }

      hideCard()
    }
  },

  unmounted(el) {
    if (isMobileDevice()) {
      return
    }

    if (el._userHoverCleanup) {
      el._userHoverCleanup()
    }
  }
}