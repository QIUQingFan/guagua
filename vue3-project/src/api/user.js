import { userApi } from './index.js'

export async function getUsers(params = {}) {
  try {
    const response = await userApi.getUsers(params)
    return response
  } catch (error) {
    console.error('获取用户列表失败:', error)
    throw error
  }
}

export async function getUserInfo(userId) {
  try {
    const userInfo = await userApi.getUserInfo(userId)
    return userInfo
  } catch (error) {
    console.error('获取用户信息失败:', error)
    return {
      id: userId,
      avatar: null,
      nickname: `用户${userId}`,
      bio: '还没有简介',
      followCount: 0,
      fansCount: 0,
      likeAndCollectCount: 0,
      isFollowing: false,
      images: []
    }
  }
}