import { defineStore } from 'pinia'
import { ref, onMounted, onUnmounted } from 'vue'

export const useEventStore = defineStore('event', () => {
  const eventListeners = ref(new Map())

  const addEventListener = (eventName, handler, target = window) => {
    const key = `${eventName}_${Date.now()}_${Math.random()}`

    target.addEventListener(eventName, handler)

    eventListeners.value.set(key, {
      eventName,
      handler,
      target
    })

    return key
  }

  const removeEventListener = (key) => {
    const listener = eventListeners.value.get(key)
    if (listener) {
      listener.target.removeEventListener(listener.eventName, listener.handler)
      eventListeners.value.delete(key)
    }
  }

  const removeAllEventListeners = () => {
    eventListeners.value.forEach((listener, key) => {
      listener.target.removeEventListener(listener.eventName, listener.handler)
    })
    eventListeners.value.clear()
  }

  const dispatchEvent = (eventName, detail = null, target = window) => {
    const event = detail
      ? new CustomEvent(eventName, { detail })
      : new CustomEvent(eventName)

    target.dispatchEvent(event)
  }

  const triggerFloatingBtnReload = () => {
    dispatchEvent('floating-btn-reload')
  }

  const triggerFloatingBtnReloadRequest = () => {
    dispatchEvent('floating-btn-reload-request')
  }

  return {
    addEventListener,
    removeEventListener,
    removeAllEventListeners,
    dispatchEvent,
    triggerFloatingBtnReload,
    triggerFloatingBtnReloadRequest
  }
})