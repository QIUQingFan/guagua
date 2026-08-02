import { useIntersectionObserver } from '@vueuse/core'
import { vUserHover } from './userHover'
import { vClickOutside } from './clickOutside'
import vEscapeKey from './escapeKey'
import defaultAvatar from '@/assets/imgs/瓜呱.png'
import defaultPlaceholder from '@/assets/imgs/瓜呱.png'

class ImageLoadQueue {
  constructor(maxConcurrent = 6) {
    this.maxConcurrent = maxConcurrent
    this.running = 0
    this.queue = []
  }

  add(task) {
    return new Promise((resolve, reject) => {
      this.queue.push({ task, resolve, reject })
      this.process()
    })
  }

  async process() {
    if (this.running >= this.maxConcurrent || this.queue.length === 0) {
      return
    }

    this.running++
    const { task, resolve, reject } = this.queue.shift()

    try {
      const result = await task()
      resolve(result)
    } catch (error) {
      reject(error)
    } finally {
      this.running--
      this.process()
    }
  }
}

const globalImageQueue = new ImageLoadQueue(4) 

class StuckItemManager {
  constructor() {
    this.pendingItems = new Map()
    this.checkInterval = null
    this.isChecking = false
  }

  addItem(el, binding) {
    this.pendingItems.set(el, {
      binding,
      addedAt: Date.now(),
      checked: false
    })
    this.startChecking()
  }

  removeItem(el) {
    this.pendingItems.delete(el)
    if (this.pendingItems.size === 0) {
      this.stopChecking()
    }
  }

  startChecking() {
    if (this.checkInterval || this.isChecking) return

    this.checkInterval = setInterval(() => {
      this.checkStuckItems()
    }, 5000) 
  }

  stopChecking() {
    if (this.checkInterval) {
      clearInterval(this.checkInterval)
      this.checkInterval = null
    }
  }

  checkStuckItems() {
    if (this.isChecking) return
    this.isChecking = true

    const now = Date.now()
    for (const [el, info] of this.pendingItems) {
      if (now - info.addedAt > 10000 && !info.checked) {
        if (this.isElementInViewport(el)) {
          this.forceLoadImage(el, info.binding)
          info.checked = true
        }
      }
    }

    this.isChecking = false
  }

  isElementInViewport(el) {
    const rect = el.getBoundingClientRect()
    return (
      rect.top < window.innerHeight + 100 &&
      rect.bottom > -100 &&
      rect.left < window.innerWidth &&
      rect.right > 0
    )
  }

  forceLoadImage(el, binding) {
    const img = new Image()
    img.onload = () => {
      el.src = binding.value
      el.classList.add('fade-in')
      el.dispatchEvent(new Event('load'))
      this.removeItem(el)
    }
    img.onerror = () => {
      const isAvatar = el.classList.contains('lazy-avatar')
      const placeholderImg = isAvatar ? defaultAvatar : defaultPlaceholder
      el.src = placeholderImg
      el.alt = '图片加载失败'
      el.dispatchEvent(new Event('load'))
      this.removeItem(el)
    }

    setTimeout(() => {
      if (!el.src || el.src === 'data:' || el.src.includes('blob:')) {
        const isAvatar = el.classList.contains('lazy-avatar')
        const placeholderImg = isAvatar ? defaultAvatar : defaultPlaceholder
        el.src = placeholderImg
        el.alt = '图片加载超时'
        el.dispatchEvent(new Event('load'))
        this.removeItem(el)
      }
    }, 5000)

    img.src = binding.value
  }
}

const stuckItemManager = new StuckItemManager()

const loadImageImmediately = (el, src) => {
  const img = new Image()

  const timeout = setTimeout(() => {
    img.onload = null
    img.onerror = null
    const isAvatar = el.classList.contains('lazy-avatar')
    const placeholderImg = isAvatar ? defaultAvatar : defaultPlaceholder
    el.src = placeholderImg
    el.alt = '图片加载超时'
    el.style.opacity = '1'
    el.style.visibility = 'visible'
    el.dispatchEvent(new Event('load'))
    stuckItemManager.removeItem(el)
  }, 3000) 

  img.onload = () => {
    clearTimeout(timeout)
    el.src = src
    el.style.opacity = '1'
    el.style.visibility = 'visible'
    el.classList.add('fade-in')
    el.dispatchEvent(new Event('load'))
    stuckItemManager.removeItem(el)
  }

  img.onerror = () => {
    clearTimeout(timeout)
    const isAvatar = el.classList.contains('lazy-avatar')
    const placeholderImg = isAvatar ? defaultAvatar : defaultPlaceholder
    el.src = placeholderImg
    el.alt = '图片加载失败'
    el.style.opacity = '1'
    el.style.visibility = 'visible'
    el.dispatchEvent(new Event('load'))
    stuckItemManager.removeItem(el)
  }

  img.src = src
}

export const lazyPlugin = {
  install(app) {
    app.directive('img-lazy', {
      mounted(el, binding) {
        if (el.src === binding.value && el.complete && el.naturalWidth > 0) {
          return
        }

        el.style.opacity = '0'
        el.style.visibility = 'hidden'
        el.style.transition = 'opacity 0.3s ease'
        el.dataset.src = binding.value 
        el.setAttribute('v-img-lazy', binding.value)

        stuckItemManager.addItem(el, binding)

        const rect = el.getBoundingClientRect()
        const isInFirstScreen = rect.top < window.innerHeight + 100

        if (isInFirstScreen) {
          loadImageImmediately(el, binding.value)
          return
        }

        const { stop } = useIntersectionObserver(
          el,
          ([{ isIntersecting, intersectionRatio }]) => {
            if (isIntersecting || intersectionRatio > 0) {
              globalImageQueue.add(() => {
                return new Promise((resolve, reject) => {
                  const img = new Image()

                  const loadTimeout = setTimeout(() => {
                    img.onload = null
                    img.onerror = null
                    reject(new Error('加载超时'))
                  }, 8000) 

                  img.onload = () => {
                    clearTimeout(loadTimeout)
                    el.src = binding.value
                    el.style.opacity = '1'
                    el.style.visibility = 'visible'
                    el.classList.add('fade-in')
                    el.dispatchEvent(new Event('load'))
                    stuckItemManager.removeItem(el)
                    resolve()
                  }

                  img.onerror = () => {
                    clearTimeout(loadTimeout)
                    const isAvatar = el.classList.contains('lazy-avatar')
                    const placeholderImg = isAvatar ? defaultAvatar : defaultPlaceholder
                    el.src = placeholderImg
                    el.alt = '图片加载失败'
                    el.style.opacity = '1'
                    el.style.visibility = 'visible'
                    el.dispatchEvent(new Event('load'))
                    stuckItemManager.removeItem(el)
                    resolve()
                  }

                  img.src = binding.value
                })
              }).catch(() => {
                const isAvatar = el.classList.contains('lazy-avatar')
                const placeholderImg = isAvatar ? defaultAvatar : defaultPlaceholder
                el.src = placeholderImg
                el.alt = '图片加载失败'
                el.style.opacity = '1'
                el.style.visibility = 'visible'
                el.dispatchEvent(new Event('load'))
                stuckItemManager.removeItem(el)
              })

              stop()
            }
          },
          {
            rootMargin: '100px', 
            threshold: 0.1, 
          }
        )

        setTimeout(() => {
          if (!el.src || el.src === 'data:' || el.style.opacity === '0') {
            const rect = el.getBoundingClientRect()
            if (rect.top < window.innerHeight + 50 && rect.bottom > -50) {
              loadImageImmediately(el, binding.value)
            }
          }
        }, 1000)
      },

      updated(el, binding) {
        if (binding.value !== binding.oldValue) {
          if (el.src !== binding.value) {
            el.style.opacity = '0'
            stuckItemManager.addItem(el, binding)
          }
        }
      },

      unmounted(el) {
        stuckItemManager.removeItem(el)
      }
    })

    app.directive('user-hover', vUserHover)

    app.directive('click-outside', vClickOutside)

    app.directive('escape-key', vEscapeKey)

    app.directive('img-fallback', {
      mounted(el, binding) {
        const fallback = binding.value === 'avatar' ? defaultAvatar : defaultPlaceholder
        el.dataset.fallbackApplied = '0'
        el.addEventListener('error', () => {
          if (el.dataset.fallbackApplied === '1') return
          el.dataset.fallbackApplied = '1'
          el.src = fallback
          el.alt = '图片加载失败'
        })
        el.addEventListener('load', () => {
          if (el.src !== fallback) {
            el.dataset.fallbackApplied = '0'
          }
        })
      },
      updated(el, binding) {
        el.dataset.fallbackApplied = '0'
      }
    })
  }
}