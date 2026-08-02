import { getCategories } from '@/api/categories'

const DEFAULT_CHANNELS = [
  { id: 'recommend', label: '推荐', path: '/recommend' }
]

let dynamicChannels = [...DEFAULT_CHANNELS]

export const loadChannelsFromAPI = async () => {
  try {
    const response = await getCategories()
    if (response.success !== false && response.data) {
      const categoryChannels = response.data.map(category => ({
        id: category.id,
        label: category.name,
        path: `/${category.category_title}` 
      }))
      
      dynamicChannels = [...DEFAULT_CHANNELS, ...categoryChannels]
      return dynamicChannels
    }
  } catch (error) {
    console.error('加载分类数据失败:', error)
  }
  
  return DEFAULT_CHANNELS
}

export const getChannels = () => {
  return dynamicChannels
}

export const CHANNELS = dynamicChannels

export const getValidChannelPaths = () => {
  return dynamicChannels.map(ch => ch.path.substring(1)) 
}

export const getChannelIdByPath = (path) => {
  
  let channelPath = path
  if (path.startsWith('/explore/')) {
    channelPath = path.replace('/explore', '')
  } else if (path === '/explore') {
    return 'recommend' 
  }

  const channel = dynamicChannels.find(ch => ch.path === channelPath)
  return channel ? channel.id : 'recommend'
}

export const getChannelPath = (channelId) => {
  const channel = dynamicChannels.find(ch => ch.id === channelId)
  return channel ? channel.path : '/recommend'
}