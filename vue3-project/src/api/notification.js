import { notificationApi } from './index.js'
import request from './request.js'

export const getCommentNotifications = (params = {}) => {
  return request.get('/notifications/comments', { params })
}

export const getLikeNotifications = (params = {}) => {
  return request.get('/notifications/likes', { params })
}

export const getFollowNotifications = (params = {}) => {
  return request.get('/notifications/follows', { params })
}

export const getCollectionNotifications = (params = {}) => {
  return request.get('/notifications/collections', { params })
}

export async function markNotificationAsRead(notificationId) {
  try {
    const response = await notificationApi.markAsRead(notificationId)
    return response.data || response
  } catch (error) {
    console.error('标记通知已读失败:', error)
    throw error
  }
}

export async function markAllNotificationsAsRead() {
  try {
    const response = await notificationApi.markAllAsRead()
    return response.data || response
  } catch (error) {
    console.error('标记所有通知已读失败:', error)
    throw error
  }
}

export async function getUnreadNotificationCount() {
  try {
    const response = await notificationApi.getUnreadCount()
    return response.data || response
  } catch (error) {
    console.error('获取未读通知数量失败:', error)
    throw error
  }
}

export async function getUnreadNotificationCountByType() {
  try {
    const response = await notificationApi.getUnreadCountByType()
    return response.data || response
  } catch (error) {
    console.error('获取按类型分组的未读通知数量失败:', error)
    throw error
  }
}

export async function deleteNotification(notificationId) {
  try {
    const response = await notificationApi.deleteNotification(notificationId)
    return response.data || response
  } catch (error) {
    console.error('删除通知失败:', error)
    throw error
  }
}