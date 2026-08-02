import { defineStore } from 'pinia'
import { ref } from 'vue'
import router from '@/router'
import { useEventStore } from './event'

export const useNavigationStore = defineStore('navigation', () => {
  const currentRoute = ref(null)

  const scrollToTop = (behavior = 'smooth') => {
    window.scrollTo({ top: 0, behavior })
  }

  const triggerExploreRefresh = () => {
    const eventStore = useEventStore()
    eventStore.triggerFloatingBtnReloadRequest()
  }

  const handleExploreClick = (event, currentPath) => {
    if (event) {
      event.preventDefault()
    }

    if (currentPath && currentPath.startsWith('/explore')) {
      scrollToTop()
      triggerExploreRefresh()
    } else {
      router.push('/explore').then(() => {
        scrollToTop()
      })
    }
  }

  const navigateAndScrollToTop = (path, behavior = 'smooth') => {
    router.push(path).then(() => {
      scrollToTop(behavior)
    })
  }

  const setCurrentRoute = (route) => {
    currentRoute.value = route
  }

  return {
    currentRoute,
    scrollToTop,
    triggerExploreRefresh,
    handleExploreClick,
    navigateAndScrollToTop,
    setCurrentRoute
  }
})