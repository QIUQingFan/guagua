import { defineStore } from 'pinia'
import { ref } from 'vue'
import { getChannels, loadChannelsFromAPI, getChannelIdByPath, getChannelPath } from '@/config/channels'

export const useChannelStore = defineStore('channel', () => {
  const channels = ref(getChannels())
  const isLoading = ref(false)

  const activeChannelId = ref('recommend')

  const loadChannels = async () => {
    isLoading.value = true
    try {
      await loadChannelsFromAPI()
      channels.value = getChannels()
    } finally {
      isLoading.value = false
    }
  }

  const setActiveChannel = (channelId) => {
    activeChannelId.value = channelId
  }

  const getChannelIdByPathFn = getChannelIdByPath

  const getChannelPathFn = getChannelPath

  return {
    channels,
    activeChannelId,
    isLoading,
    setActiveChannel,
    loadChannels,
    getChannelIdByPath: getChannelIdByPathFn,
    getChannelPath: getChannelPathFn
  }
})