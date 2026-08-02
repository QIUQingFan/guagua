/**
 * 视频缩略图生成工具
 * 使用Canvas API从视频文件中提取第一帧作为缩略图
 */

/**
 * 生成视频缩略图
 * @param {File} videoFile - 视频文件
 * @param {Object} options - 配置选项
 * @param {number} options.width - 缩略图宽度，默认640
 * @param {number} options.height - 缩略图高度，默认360
 * @param {boolean} options.useOriginalSize - 是否使用视频原始尺寸，默认false
 * @param {number} options.quality - 图片质量，默认0.8
 * @param {string} options.format - 图片格式，默认'image/jpeg'
 * @param {number} options.seekTime - 截取时间点（秒），默认1秒
 * @returns {Promise<{success: boolean, blob?: Blob, dataUrl?: string, error?: string}>}
 */
export async function generateVideoThumbnail(videoFile, options = {}) {
  const {
    width = 640,
    height = 360,
    useOriginalSize = false,
    quality = 0.8,
    format = 'image/jpeg',
    seekTime = 1
  } = options

  return new Promise((resolve) => {
    try {
      
      const video = document.createElement('video')
      video.crossOrigin = 'anonymous'
      video.muted = true
      video.playsInline = true
      
      
      const canvas = document.createElement('canvas')
      const ctx = canvas.getContext('2d')
      
      
      canvas.width = width
      canvas.height = height

      
      video.addEventListener('loadedmetadata', () => {
        
        if (useOriginalSize) {
          canvas.width = video.videoWidth
          canvas.height = video.videoHeight
        } else {
          
          canvas.width = width
          canvas.height = height
        }

        
        const targetTime = Math.min(seekTime, video.duration - 0.1)
        video.currentTime = targetTime
      })

      
      video.addEventListener('seeked', () => {
        try {
          if (useOriginalSize) {
            
            ctx.drawImage(video, 0, 0, video.videoWidth, video.videoHeight)
          } else {
            
            ctx.fillStyle = '#000000'
            ctx.fillRect(0, 0, canvas.width, canvas.height)
            
            const videoAspectRatio = video.videoWidth / video.videoHeight
            const canvasAspectRatio = canvas.width / canvas.height
            
            let drawWidth = canvas.width
            let drawHeight = canvas.height
            let offsetX = 0
            let offsetY = 0
            
            if (videoAspectRatio > canvasAspectRatio) {
              drawHeight = canvas.height
              drawWidth = canvas.height * videoAspectRatio
              offsetX = (canvas.width - drawWidth) / 2
            } else {
              drawWidth = canvas.width
              drawHeight = canvas.width / videoAspectRatio
              offsetY = (canvas.height - drawHeight) / 2
            }
            
            ctx.drawImage(video, offsetX, offsetY, drawWidth, drawHeight)
          }
          
          
          canvas.toBlob((blob) => {
            if (blob) {
              
              const dataUrl = canvas.toDataURL(format, quality)
              
              resolve({
                success: true,
                blob: blob,
                dataUrl: dataUrl
              })
            } else {
              resolve({
                success: false,
                error: '无法生成缩略图Blob'
              })
            }
            
            
            URL.revokeObjectURL(video.src)
          }, format, quality)
          
        } catch (error) {
          console.error('绘制视频帧失败:', error)
          resolve({
            success: false,
            error: '绘制视频帧失败: ' + error.message
          })
          URL.revokeObjectURL(video.src)
        }
      })

      
      video.addEventListener('error', (e) => {
        console.error('视频加载失败:', e)
        resolve({
          success: false,
          error: '视频加载失败'
        })
        URL.revokeObjectURL(video.src)
      })

      
      const timeout = setTimeout(() => {
        resolve({
          success: false,
          error: '视频加载超时'
        })
        URL.revokeObjectURL(video.src)
      }, 10000) 

      
      video.addEventListener('loadedmetadata', () => {
        clearTimeout(timeout)
      })

      
      video.src = URL.createObjectURL(videoFile)
      video.load()
      
    } catch (error) {
      console.error('生成视频缩略图失败:', error)
      resolve({
        success: false,
        error: '生成视频缩略图失败: ' + error.message
      })
    }
  })
}

/**
 * 将Blob转换为File对象
 * @param {Blob} blob - Blob对象
 * @param {string} filename - 文件名
 * @returns {File} File对象
 */
export function blobToFile(blob, filename) {
  return new File([blob], filename, { type: blob.type })
}

/**
 * 生成缩略图文件名
 * @param {string} videoFilename - 视频文件名
 * @returns {string} 缩略图文件名
 */
export function generateThumbnailFilename(videoFilename) {
  const nameWithoutExt = videoFilename.replace(/\.[^/.]+$/, '')
  return `${nameWithoutExt}_thumbnail.jpg`
}