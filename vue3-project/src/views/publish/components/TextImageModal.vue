<template>
  <div v-if="visible" class="text-image-modal-overlay" @mousedown="handleOverlayMouseDown">
    <div class="text-image-modal" @click.stop>
      <div class="modal-header">
        <h3 class="modal-title">文字配图</h3>
        <button class="close-btn" @click="$emit('close')">
          <SvgIcon name="close" width="20" height="20" />
        </button>
      </div>

      <div class="modal-body">
        <div class="main-content">
          <div class="preview-section">
            <div class="preview-container">
              <div v-if="!previewImage" class="preview-placeholder">
                <SvgIcon name="imgNote" width="48" height="48" />
                <p>{{ placeholderText }}</p>
              </div>
              <img v-else :src="previewImage" class="preview-image" alt="生成的图片" />
              <canvas ref="previewCanvas" class="hidden-canvas" width="400" height="600" style="display: none;"></canvas>
            </div>
          </div>

          <div class="controls-section">
            <div class="font-controls">
              <div class="color-controls">
                <div class="control-group">
                  <label class="control-label">文字颜色</label>
                  <input type="color" v-model="textColor" class="color-picker" />
                </div>
                <div class="control-group">
                  <label class="control-label">描边颜色</label>
                  <input type="color" v-model="strokeColor" class="color-picker" />
                </div>
              </div>
              <div class="control-group">
                <label class="control-label">字体</label>
                <DropdownSelect
                  v-model="selectedFont"
                  :options="fontOptions"
                  placeholder="选择字体"
                  min-width="120px"
                  max-width="200px"
                  size="small"
                />
              </div>
            </div>

            <div class="input-emoji-container">
              <div class="input-section">
                <div class="content-input-wrapper">
                  <ContentEditableInput ref="textInputRef" v-model="inputText" placeholder="输入文字内容"
                    :input-class="'content-textarea'" :max-length="200" />
                  <div class="content-actions">
                    <button class="emoji-btn" @click="toggleEmojiPanel">
                      <SvgIcon name="emoji" class="emoji-icon" width="20" height="20" />
                    </button>
                  </div>
                </div>

                <div v-if="showEmojiPanel" class="emoji-panel-overlay" @click="closeEmojiPanel">
                  <div class="emoji-panel" @click.stop>
                    <EmojiPicker @select="handleEmojiSelect" @close="closeEmojiPanel" />
                  </div>
                </div>
              </div>
            </div>

            <div class="template-section">
              <div class="section-title">选择模版</div>
              <div class="template-scroll-container">
                <div class="template-list">
                  <div v-for="template in templates" :key="template.id" class="template-item"
                    :class="{ active: selectedTemplate?.id === template.id }" @click="selectTemplate(template)">
                    <img :src="template.src" :alt="template.name" class="template-image" v-img-fallback />
                    <span class="template-name">{{ template.name }}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="modal-footer">
        <button class="cancel-btn" @click="$emit('close')">取消</button>
        <button class="upload-btn" @click="handleUpload" :disabled="!previewImage">上传</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue'
import SvgIcon from '@/components/SvgIcon.vue'
import ContentEditableInput from '@/components/ContentEditableInput.vue'
import EmojiPicker from '@/components/EmojiPicker.vue'
import DropdownSelect from '@/components/DropdownSelect.vue'

const props = defineProps({
  visible: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['close', 'generate'])

const textInputRef = ref(null)
const previewCanvas = ref(null)
const inputText = ref('')
const showEmojiPanel = ref(false)
const selectedTemplate = ref(null)
const previewImage = ref('')
const templates = ref([])
const fontSize = ref(40)
const selectedFont = ref('微软雅黑')

const fontOptions = [
  { label: '微软雅黑', value: '微软雅黑' },
  { label: '宋体', value: '宋体' },
  { label: '楷体', value: '楷体' },
  { label: '黑体', value: '黑体' },
  { label: '仿宋', value: 'FangSong' },
  { label: '华文细黑', value: 'STXihei' },
  { label: '华文彩云', value: 'STCaiyun' },
  { label: '华文楷体', value: 'STKaiti' },
  { label: '华文宋体', value: 'STSong' },
  { label: '华文黑体', value: 'STHeiti' },
  { label: '华文仿宋', value: 'STFangsong' },
  { label: '华文隶书', value: 'STLiti' }
]

const calculateOptimalFontSize = () => {
  if (!inputText.value) return 30
  
  const lines = processText(inputText.value)
  const maxLineLength = Math.max(...lines.map(line => line.length))
  
  if (maxLineLength <= 5) {
    return 55
  } else if (maxLineLength <= 7) {
    return 45
  } else if (maxLineLength === 8) {
    return 40
  } else if (maxLineLength === 9) {
    return 35
  } else {
    return 30  
  }
}
const textColor = ref('#000000')
const strokeColor = ref('#ffffff')

const loadTemplates = async () => {
  try {
    const frameModules = import.meta.glob('../../../../assets/frames/*.(jpg|jpeg|png|gif|webp)', { eager: true })

    const templateList = []
    let index = 1

    for (const path in frameModules) {
      const module = frameModules[path]
      templateList.push({
        id: index,
        name: `模版${index}`,
        src: module.default || path
      })
      index++
    }

    templates.value = templateList
  } catch (error) {
    console.error('加载模版失败:', error)
  }
}

const processText = (text) => {
  if (!text) return []
  
  const tempDiv = document.createElement('div')
  tempDiv.innerHTML = text
  
  const brElements = tempDiv.querySelectorAll('br')
  brElements.forEach(br => {
    br.replaceWith('\n')
  })
  
  const divElements = tempDiv.querySelectorAll('div')
  divElements.forEach(div => {
    div.insertAdjacentText('beforebegin', '\n')
  })
  
  let cleanText = tempDiv.textContent || tempDiv.innerText || ''
  
  cleanText = cleanText.replace(/&amp;/g, '&').replace(/&nbsp;/g, ' ')
  
  const lines = cleanText.split('\n')
  
  const filteredLines = lines.filter(line => line.trim().length > 0)
  
  return filteredLines
}

const drawCanvas = async () => {
  if (!previewCanvas.value || !selectedTemplate.value) {
    return
  }

  const canvas = previewCanvas.value
  const ctx = canvas.getContext('2d')

  ctx.clearRect(0, 0, canvas.width, canvas.height)

  try {
    const img = new Image()
    img.crossOrigin = 'anonymous'

    await new Promise((resolve, reject) => {
      img.onload = resolve
      img.onerror = reject
      img.src = selectedTemplate.value.src
    })

    const canvasRatio = canvas.width / canvas.height
    const imgRatio = img.width / img.height

    let drawWidth, drawHeight, offsetX, offsetY

    if (imgRatio > canvasRatio) {
      drawHeight = canvas.height
      drawWidth = drawHeight * imgRatio
      offsetX = (canvas.width - drawWidth) / 2
      offsetY = 0
    } else {
      drawWidth = canvas.width
      drawHeight = drawWidth / imgRatio
      offsetX = 0
      offsetY = (canvas.height - drawHeight) / 2
    }

    ctx.drawImage(img, offsetX, offsetY, drawWidth, drawHeight)

    if (inputText.value.trim()) {
      const lines = processText(inputText.value)

      const currentFontSize = calculateOptimalFontSize()
      fontSize.value = currentFontSize

      ctx.font = `bold ${currentFontSize}px ${selectedFont.value}, Arial, sans-serif`
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      ctx.lineWidth = 3

      const lineHeight = currentFontSize + 10
      const totalHeight = lines.length * lineHeight
      const startY = (canvas.height - totalHeight) / 2 + lineHeight / 2

      lines.forEach((line, index) => {
        if (line && typeof line === 'string') {
          const y = startY + index * lineHeight
          const x = canvas.width / 2

          ctx.strokeStyle = strokeColor.value
          ctx.strokeText(line, x, y)

          ctx.fillStyle = textColor.value
          ctx.fillText(line, x, y)
        }
      })
    }
  } catch (error) {
    console.error('绘制canvas失败:', error)
  }
}

onMounted(() => {
  loadTemplates()
})

const canGenerate = computed(() => {
  return inputText.value.trim() && selectedTemplate.value
})

const placeholderText = computed(() => {
  const hasText = inputText.value.trim()
  const hasTemplate = selectedTemplate.value

  if (!hasText && !hasTemplate) {
    return '请输入文字并选择模版'
  } else if (hasTemplate && !hasText) {
    return '请输入文字内容'
  } else if (hasText && !hasTemplate) {
    return '请选择模版'
  } else {
    return '图片生成中...'
  }
})

const handleOverlayMouseDown = (event) => {
  if (event.target === event.currentTarget) {
    emit('close')
  }
}

const toggleEmojiPanel = () => {
  showEmojiPanel.value = !showEmojiPanel.value
}

const closeEmojiPanel = () => {
  showEmojiPanel.value = false
}

const handleEmojiSelect = (emoji) => {
  const emojiChar = emoji.i
  const inputElement = textInputRef.value

  if (inputElement && inputElement.insertEmoji) {
    inputElement.insertEmoji(emojiChar)
  } else {
    inputText.value += emojiChar
  }

  closeEmojiPanel()
}

const selectTemplate = (template) => {
  selectedTemplate.value = template
  previewImage.value = ''

  if (inputText.value.trim()) {
    handleGenerate()
  }
}

const handleGenerate = async () => {
  if (!canGenerate.value || !previewCanvas.value) {
    return
  }

  try {
    await drawCanvas()

    await new Promise((resolve) => {
      previewCanvas.value.toBlob((blob) => {
        if (blob) {
          const url = URL.createObjectURL(blob)
          previewImage.value = url
        }
        resolve()
      }, 'image/png', 0.9)
    })
  } catch (error) {
    console.error('生成图片失败:', error)
  }
}

const handleUpload = async () => {
  if (!previewImage.value) return

  try {
    await drawCanvas()

    previewCanvas.value.toBlob((blob) => {
      if (blob) {
        const file = new File([blob], `text-image-${Date.now()}.png`, {
          type: 'image/png'
        })

        const data = {
          text: inputText.value,
          template: selectedTemplate.value,
          imageFile: file,
          imageUrl: previewImage.value
        }

        emit('generate', data)
      }
    }, 'image/png', 0.9)
  } catch (error) {
    console.error('上传图片失败:', error)
  }
}

watch(inputText, (newText) => {
  if (newText.trim() && selectedTemplate.value) {
    handleGenerate()
  } else if (!newText.trim()) {
    previewImage.value = ''
  }
})

watch([textColor, strokeColor, selectedFont], (newValues, oldValues) => {
  if (inputText.value.trim() && selectedTemplate.value) {
    handleGenerate()
  }
})

watch(() => props.visible, (newVal) => {
  if (newVal) {
    inputText.value = ''
    selectedTemplate.value = null
    previewImage.value = ''
    showEmojiPanel.value = false
    textColor.value = '#000000'
    strokeColor.value = '#ffffff'
    selectedFont.value = '微软雅黑'
  }
})
</script>

<style scoped>
.text-image-modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: var(--overlay-bg);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 1rem;
}

.text-image-modal {
  background: var(--bg-color-primary);
  border-radius: 8px;
  width: 100%;
  max-width: 700px;
  max-height: 90vh;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  box-shadow: 0 4px 20px var(--shadow-color);
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 20px 30px;
  border-bottom: 1px solid var(--border-color-primary);
  flex-shrink: 0;
  background: var(--bg-color-primary);
}

.modal-title {
  font-size: 1.25rem;
  font-weight: 600;
  color: var(--text-color-primary);
  margin: 0;
}

.close-btn {
  background: none;
  border: none;
  cursor: pointer;
  padding: 5px;
  color: var(--text-color-secondary);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
}

.close-btn:hover {
  color: var(--text-color-primary);
  background-color: var(--bg-color-secondary);
}

.modal-body {
  flex: 1;
  overflow-y: auto;
  padding: 30px;
  display: flex;
  flex-direction: column;
  gap: 30px;
  background: var(--bg-color-primary);
}

.main-content {
  display: flex;
  flex-direction: row;
  gap: 30px;
  flex: 1;
}

.preview-section {
  flex: 0 0 300px;
  text-align: center;
}

.controls-section {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 20px;
  min-width: 0;
}

.input-emoji-container {
  display: flex;
  flex-direction: column;
  gap: 16px;
  flex: 1;
}

.preview-container {
  width: 100%;
  border: 2px dashed var(--border-color-primary);
  border-radius: 3px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--bg-color-primary);
  min-height: 400px;
  overflow: hidden;
  position: relative;
}

.preview-container:has(.preview-image) {
  border: none;
}

.preview-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  color: var(--text-color-secondary);
}

.preview-placeholder p {
  margin: 0;
  font-size: 18px;
}

.preview-canvas {
  display: block;
  border-radius: 8px;
  border: 1px solid var(--border-color-primary);
  max-width: 100%;
  height: auto;
}

.preview-image {
  max-width: 100%;
  max-height: 400px;
  border-radius: 8px;
  object-fit: contain;
  display: block;
  margin: 0 auto;
}

.hidden-canvas {
  display: none !important;
}

.input-section {
  position: relative;
}

.content-input-wrapper {
  position: relative;
  border: 1px solid var(--border-color-primary);
  border-radius: 8px;
  background: var(--bg-color-primary);
  transition: all 0.2s ease;
}

.content-input-wrapper:focus-within {
  border-color: var(--primary-color);
}

.content-textarea {
  width: 100%;
  padding: 1rem;
  padding-bottom: 3rem;
  border: none;
  border-radius: 8px;
  background: transparent;
  color: var(--text-color-primary);
  font-size: 16px;
  line-height: 1.5;
  transition: all 0.2s ease;
  min-height: 80px;
  box-sizing: border-box;
  caret-color: var(--primary-color);
}

.content-textarea:focus {
  outline: none;
}

.content-textarea:empty:before {
  content: attr(placeholder);
  color: var(--text-color-secondary);
  pointer-events: none;
}

.content-actions {
  position: absolute;
  bottom: 0.5rem;
  left: 1rem;
  display: flex;
  align-items: center;
  gap: 8px;
}

.emoji-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border: none;
  background: transparent;
  color: var(--text-color-secondary);
  border-radius: 50%;
  cursor: pointer;
  transition: all 0.2s ease;
}

.emoji-btn:hover {
  background: var(--bg-color-secondary);
  color: var(--text-color-primary);
}

.emoji-icon {
  width: 20px;
  height: 20px;
}

.emoji-panel-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: transparent;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  animation: fadeIn 0.2s ease;
}

.emoji-panel {
  background: var(--bg-color-primary);
  border-radius: 12px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
  overflow: hidden;
  animation: scaleIn 0.2s ease;
  max-width: 90vw;
  max-height: 80vh;
}

@keyframes fadeIn {
  from {
    opacity: 0;
  }

  to {
    opacity: 1;
  }
}

@keyframes scaleIn {
  from {
    opacity: 0;
    transform: scale(0.8);
  }

  to {
    opacity: 1;
    transform: scale(1);
  }
}

.font-controls {
  background: var(--bg-color-primary);
  border-radius: 8px;
  padding: 8px 10px;
  border: 1px solid var(--border-color-primary);
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.control-group {
  display: flex;
  align-items: center;
  gap: 12px;
}

.control-group:last-child {
  margin-bottom: 0;
}

.control-label {
  font-size: 14px;
  font-weight: 500;
  color: var(--text-color-primary);
  margin: 0;
}

.color-controls {
  display: flex;
  flex-direction: row;
  gap: 16px;
}

.color-picker {
  width: 25px;
  height: 25px;
  box-shadow: 0 0 0 2px var(--border-color-primary);
  border-radius: 50%;
  cursor: pointer;
  background: none;
  padding: 0;
}

.color-picker::-webkit-color-swatch-wrapper {
  padding: 0;
  border: none;
  border-radius: 6px;
}

.color-picker::-webkit-color-swatch {
  border: none;
  border-radius: 6px;
}

.template-section {
  flex-shrink: 0;
}

.section-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--text-color-primary);
}

.template-scroll-container {
  overflow-x: auto;
  scrollbar-width: thin;
  scrollbar-color: var(--scrollbar-thumb-color) transparent;
}

.template-scroll-container::-webkit-scrollbar {
  height: 6px;
}

.template-scroll-container::-webkit-scrollbar-track {
  background: var(--scrollbar-track-color);
  border-radius: 3px;
}

.template-scroll-container::-webkit-scrollbar-thumb {
  background: var(--scrollbar-thumb-color);
  border-radius: 3px;
}

.template-scroll-container::-webkit-scrollbar-thumb:hover {
  background: var(--scrollbar-thumb-hover-color);
}

.template-list {
  display: flex;
  gap: 12px;
  padding: 8px 12px;
}

.template-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  flex-shrink: 0;
  width: 80px;
  cursor: pointer;
  transition: all 0.2s ease;
}

.template-item:hover .template-image {
  scale: 1.05;
  border: 1px solid var(--primary-color-shadow);
}

.template-item.active .template-image {
  scale: 1.05;
  border: 1px solid var(--primary-color);
}

.template-image {
  width: 80px;
  height: 120px;
  object-fit: cover;
  border-radius: 8px;
  border: 1px solid var(--border-color-primary);
  user-select: none;
}

.template-name {
  display: block;
  font-size: 12px;
  color: var(--text-color-secondary);
  font-weight: 500;
  margin: 4px 0 0 0;
  user-select: none;
}

.modal-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 16px;
  padding: 8px 30px;
  border-top: 1px solid var(--border-color-primary);
  background: var(--bg-color-primary);
  flex-shrink: 0;
}

.cancel-btn,
.upload-btn {
  padding: 10px 24px;
  border-radius: 8px;
  font-size: 16px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s ease;
  border: none;
  min-width: 80px;
}

.cancel-btn {
  background: var(--bg-color-primary);
  color: var(--text-color-secondary);
  border: 1px solid var(--border-color-primary);
}

.cancel-btn:hover {
  background: var(--bg-color-secondary);
  color: var(--text-color-primary);
}

.upload-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
  transform: none;
  box-shadow: none;
}

.upload-btn {
  background: var(--primary-color);
  color: white;
}

.upload-btn:hover {
  background-color: var(--primary-color-dark);
}

@media (max-width: 768px) {
  .color-controls {
    flex-direction: row;
    gap: 24px;
  }

}
@media (max-width: 640px) {
  .text-image-modal {
    margin: 0.5rem;
    max-width: none;
  }

  .modal-header,
  .modal-body,
  .modal-footer {
    padding: 1rem;
  }

  .main-content {
    flex-direction: column;
    gap: 20px;
  }

  .preview-section {
    flex: none;
  }

  .preview-container {
    min-height: 250px;
  }

  .preview-image {
    max-height: 300px;
  }

  .template-item {
    width: 100px;
  }

  .template-image {
    width: 100px;
  }
}
</style>