import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useNavigationStore } from '@/stores/navigation'

/**
 * 通用的路由组合式函数
 * 提供路由相关的常用功能
 */
export function useRouteUtils() {
  const route = useRoute()
  const router = useRouter()
  const navigationStore = useNavigationStore()

  const currentPath = computed(() => route.path)

  const isExplorePage = computed(() => route.path.startsWith('/explore'))

  const isCurrentPath = (path) => computed(() => route.path === path)

  const navigateTo = (path, scrollToTop = true) => {
    if (scrollToTop) {
      navigationStore.navigateAndScrollToTop(path)
    } else {
      router.push(path)
    }
  }

  const handleExploreClick = (event) => {
    navigationStore.handleExploreClick(event, route.path)
  }

  return {
    route,
    router,
    currentPath,
    isExplorePage,
    isCurrentPath,
    navigateTo,
    handleExploreClick
  }
}