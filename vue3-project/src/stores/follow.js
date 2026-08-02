import { defineStore } from 'pinia'
import { ref } from 'vue'
import { userApi } from '@/api/index.js'

export const useFollowStore = defineStore('follow', () => {
  const userFollowStates = ref(new Map())

  const followingList = ref([])

  const updateUserFollowState = (userId, followed, isMutual = false, buttonType = 'follow') => {
    userFollowStates.value.set(userId.toString(), { followed, isMutual, buttonType })
  }

  const getUserFollowState = (userId) => {
    const hasState = userFollowStates.value.has(userId.toString())
    const state = userFollowStates.value.get(userId.toString()) || { followed: false, isMutual: false, buttonType: 'follow' }
    if (process.env.NODE_ENV === 'development' && hasState) {
    }
    return { ...state, hasState }
  }

  const followUser = async (userId) => {

    const currentState = getUserFollowState(userId)

    let newButtonType = 'unfollow'
    let newIsMutual = currentState.isMutual

    if (currentState.buttonType === 'back') {
      newButtonType = 'mutual'
      newIsMutual = true
    }

    updateUserFollowState(userId, true, newIsMutual, newButtonType)

    const userIdStr = userId.toString()
    if (!followingList.value.some(user => user.user_id === userIdStr)) {
      followingList.value.push({ user_id: userIdStr })
    }

    try {
      await userApi.followUser(userId)
      return { success: true }
    } catch (error) {
      console.error('关注失败:', error)

      if (error.message && error.message.includes('已经关注过了')) {
        updateUserFollowState(userId, true, newIsMutual, newButtonType)
        return { success: true }
      }

      updateUserFollowState(userId, false, currentState.isMutual, currentState.buttonType)
      followingList.value = followingList.value.filter(user => user.user_id !== userIdStr)
      return { success: false, error: error.message }
    }
  }

  const unfollowUser = async (userId) => {

    const currentState = getUserFollowState(userId)

    let newButtonType = 'follow'
    let newIsMutual = false

    if (currentState.buttonType === 'mutual') {
      newButtonType = 'back'
      newIsMutual = false
    }

    updateUserFollowState(userId, false, newIsMutual, newButtonType)

    const userIdStr = userId.toString()
    followingList.value = followingList.value.filter(user => user.user_id !== userIdStr)

    try {
      await userApi.unfollowUser(userId)
      return { success: true }
    } catch (error) {
      console.error('取消关注失败:', error)

      if (error.message && error.message.includes('还没有关注')) {
        updateUserFollowState(userId, false, newIsMutual, newButtonType)
        return { success: true }
      }

      updateUserFollowState(userId, true, currentState.isMutual, currentState.buttonType)
      if (!followingList.value.some(user => user.user_id === userIdStr)) {
        followingList.value.push({ user_id: userIdStr })
      }
      return { success: false, error: error.message }
    }
  }

  const toggleUserFollow = async (userId) => {
    const currentState = getUserFollowState(userId)
    const isCurrentlyFollowed = currentState.followed

    let result
    if (isCurrentlyFollowed) {
      result = await unfollowUser(userId)
    } else {
      result = await followUser(userId)
    }

    return result
  }

  const initUserFollowState = (userId, followed, isMutual = false, buttonType = null) => {
    if (!buttonType) {
      buttonType = followed ? 'unfollow' : 'follow'
    }
    updateUserFollowState(userId, followed, isMutual, buttonType)
  }

  const initUsersFollowStates = (users) => {

    users.forEach(user => {
      const followed = user.followed || user.isFollowing || false
      const isMutual = user.isMutual || false
      const buttonType = user.buttonType || (followed ? 'unfollow' : 'follow')
      initUserFollowState(user.user_id, followed, isMutual, buttonType)
    })
  }

  const fetchFollowStatus = async (userId) => {
    try {
      const response = await userApi.getFollowStatus(userId)
      if (response.success) {
        const { followed, isMutual, buttonType } = response.data
        initUserFollowState(userId, followed, isMutual, buttonType)
        return { success: true, data: response.data }
      }
      return { success: false, error: '获取关注状态失败' }
    } catch (error) {
      console.error('获取关注状态失败:', error)
      return { success: false, error: error.message }
    }
  }

  return {
    userFollowStates,
    followingList,
    updateUserFollowState,
    getUserFollowState,
    followUser,
    unfollowUser,
    toggleUserFollow,
    initUserFollowState,
    initUsersFollowStates,
    fetchFollowStatus
  }
})