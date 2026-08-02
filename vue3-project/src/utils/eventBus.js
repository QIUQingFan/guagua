import { ref } from 'vue'

class EventBus {
  constructor() {
    this.events = {}
  }

  
  on(event, callback) {
    if (!this.events[event]) {
      this.events[event] = []
    }
    this.events[event].push(callback)
  }

  
  off(event, callback) {
    if (!this.events[event]) return
    
    const index = this.events[event].indexOf(callback)
    if (index > -1) {
      this.events[event].splice(index, 1)
    }
  }

  
  emit(event, data) {
    if (!this.events[event]) return
    
    this.events[event].forEach(callback => {
      callback(data)
    })
  }

  
  clear() {
    this.events = {}
  }
}

export const eventBus = new EventBus()

export const EVENT_TYPES = {
  USER_LIKED_POST: 'user_liked_post',
  USER_UNLIKED_POST: 'user_unliked_post',
  USER_COLLECTED_POST: 'user_collected_post',
  USER_UNCOLLECTED_POST: 'user_uncollected_post',
  USER_PROFILE_REFRESH: 'user_profile_refresh'
}