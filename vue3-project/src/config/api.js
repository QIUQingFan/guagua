
const useRealApi = String(import.meta.env.VITE_USE_REAL_API || '').toLowerCase() === 'true'
const resolvedBaseURL = useRealApi ? (import.meta.env.VITE_API_BASE_URL || '/api') : '/api'

export const apiConfig = {
  baseURL: resolvedBaseURL,

  timeout: 60000, 

  defaultHeaders: {
    'Content-Type': 'application/json'
  },

  pagination: {
    defaultPageSize: 20,
    maxPageSize: 100
  },

  upload: {
    image: {
      maxFileSize: 10 * 1024 * 1024, 
      allowedTypes: ['image/jpeg', 'image/png', 'image/webp'],
      maxCount: 9 
    },
    video: {
      maxFileSize: 100 * 1024 * 1024, 
      allowedTypes: ['video/mp4', 'video/avi', 'video/mov', 'video/wmv', 'video/flv', 'video/webm'],
      maxCount: 1 
    }
  }
}

export default apiConfig

