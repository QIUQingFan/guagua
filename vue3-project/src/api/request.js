import axios from 'axios'
import apiConfig from '@/config/api.js'
import { HTTP_STATUS, ERROR_MESSAGES } from '@/config/constants.js'

const request = axios.create({
  baseURL: apiConfig.baseURL,
  timeout: apiConfig.timeout,
  headers: apiConfig.defaultHeaders
})

request.interceptors.request.use(
  config => {
    const isAdminRequest = config.url && config.url.includes('/auth/admin/')
    const isInAdminPage = window.location.pathname.startsWith('/admin')

    if (isAdminRequest || isInAdminPage) {
      const adminToken = localStorage.getItem('admin_token')
      if (adminToken) {
        config.headers.Authorization = `Bearer ${adminToken}`
      }
    } else {
      const token = localStorage.getItem('token')
      if (token) {
        config.headers.Authorization = `Bearer ${token}`
      }
    }

    return config
  },
  error => {
    console.error('❌ 请求配置错误:', error)
    return Promise.reject(error)
  }
)

request.interceptors.response.use(
  (response) => {
    if (response.data && response.data.hasOwnProperty('code')) {
      return {
        success: response.data.code === HTTP_STATUS.OK,
        message: response.data.message,
        data: response.data.data
      }
    }

    return response.data
  },
  async error => {
    if (error.response) {
      let errorMessage = ERROR_MESSAGES.REQUEST_FAILED
      switch (error.response.status) {
        case HTTP_STATUS.UNAUTHORIZED:
          console.log('检测到401错误，开始处理未授权访问')
          
          const isAdminPage = window.location.pathname.startsWith('/admin')
          const isAdminRequest = error.config?.url?.includes('/auth/admin/')
          
          console.log('页面类型判断:', { isAdminPage, isAdminRequest })
          
          if (isAdminPage || isAdminRequest) {
            const adminToken = localStorage.getItem('admin_token')
            if (adminToken) {
              console.log('管理员会话过期，清除本地存储')
              localStorage.removeItem('admin_token')
              localStorage.removeItem('admin_refresh_token')
              localStorage.removeItem('admin_info')
              if (!window.location.pathname.includes('/admin/login')) {
                window.location.href = '/admin/login'
              }
              errorMessage = ERROR_MESSAGES.SESSION_EXPIRED
            } else {
              errorMessage = ERROR_MESSAGES.UNAUTHORIZED
            }
          } else {
            const userToken = localStorage.getItem('token')
            if (userToken) {
              console.log('普通用户会话过期，清除本地存储')
              localStorage.removeItem('token')
              localStorage.removeItem('refreshToken')
              localStorage.removeItem('userInfo')
              window.location.href = '/'
              errorMessage = ERROR_MESSAGES.SESSION_EXPIRED
            } else {
              errorMessage = ERROR_MESSAGES.UNAUTHORIZED
            }
          }
          break
        case HTTP_STATUS.FORBIDDEN:
          errorMessage = ERROR_MESSAGES.FORBIDDEN
          break
        case HTTP_STATUS.NOT_FOUND:
          errorMessage = ERROR_MESSAGES.NOT_FOUND
          break
        case HTTP_STATUS.INTERNAL_SERVER_ERROR:
          errorMessage = ERROR_MESSAGES.INTERNAL_SERVER_ERROR
          console.error('服务器内部错误:', error.response.data)
          break
        default:
          errorMessage = error.response.data?.message || `请求失败 (${error.response.status})`
      }

      if (error.response.data && error.response.data.hasOwnProperty('code')) {
        return {
          success: false,
          message: error.response.data.message || errorMessage,
          data: error.response.data.data
        }
      }

      return {
        success: false,
        message: errorMessage,
        data: null
      }
    } else if (error.request) {
      console.error('网络连接失败，请检查网络设置')
      return {
        success: false,
        message: ERROR_MESSAGES.NETWORK_ERROR,
        data: null
      }
    } else {
      console.error('请求配置错误:', error.message)
      return {
        success: false,
        message: error.message || ERROR_MESSAGES.REQUEST_CONFIG_ERROR,
        data: null
      }
    }
  }
)

export default request