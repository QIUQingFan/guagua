<template>
  <div v-if="show" class="captcha-modal-overlay" @click="$emit('close')">
    <div class="captcha-modal" @click.stop>
      <div class="modal-header">
        <h4>请输入验证码</h4>
        <button class="close-btn" @click="$emit('close')">
          <SvgIcon name="close" width="20" height="20" />
        </button>
      </div>
      <div class="captcha-content">
        <div class="captcha-image-wrapper" @click="$emit('refresh')" :class="{ 'clickable': !isLoading }"
          title="点击刷新验证码">
          <div v-if="isLoading" class="captcha-loading">
            <div class="loading-spinner"></div>
            <span>加载中...</span>
          </div>
          <div v-else-if="captchaSvg" class="captcha-image" v-html="captchaSvg"></div>
          <div v-else class="captcha-error">验证码加载失败，点击重试</div>
        </div>

        <div class="captcha-inputs">
          <input v-for="(char, index) in captchaInputs" :key="index" type="text" :value="char"
            @input="handleInputChange($event, index)" @keydown="handleKeyDown($event, index)"
            @paste="handlePaste($event, index)" class="captcha-input-box" maxlength="1"
            :ref="el => inputRefs[index] = el" />
        </div>
      </div>
      <div class="form-actions">
        <button class="btn btn-outline" @click="$emit('close')">取消</button>
        <button class="btn btn-primary" @click="$emit('confirm')" :disabled="!captchaText.trim()">
          确认
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, toRefs, watch, nextTick } from 'vue'
import SvgIcon from '@/components/SvgIcon.vue'

const props = defineProps({
  show: {
    type: Boolean,
    default: false
  },
  captchaSvg: {
    type: String,
    default: ''
  },
  captchaText: {
    type: String,
    default: ''
  },
  isLoading: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['close', 'refresh', 'confirm', 'update:captchaText'])

const { captchaText } = toRefs(props)
const inputRefs = ref([])
const captchaInputs = ref(['', '', '', ''])

watch(() => props.show, (newValue) => {
  if (newValue) {
    captchaInputs.value = ['', '', '', '']
    nextTick(() => {
      inputRefs.value[0]?.focus()
    })
  }
})

watch(() => props.captchaSvg, () => {
  captchaInputs.value = ['', '', '', '']
  emit('update:captchaText', '')
  nextTick(() => {
    inputRefs.value[0]?.focus()
  })
})

const handleInputChange = (event, index) => {
  const value = event.target.value
  if (value.length > 1) {
    event.target.value = value[0]
    captchaInputs.value[index] = value[0]
  } else {
    captchaInputs.value[index] = value
  }

  const fullCode = captchaInputs.value.join('')
  emit('update:captchaText', fullCode)
  if (value) {
    for (let i = index + 1; i < captchaInputs.value.length; i++) {
      if (!captchaInputs.value[i]) {
        inputRefs.value[i]?.focus()
        return
      }
    }
    inputRefs.value[3]?.focus()
  }
}

const handleKeyDown = (event, index) => {
  if (event.key === 'Backspace') {
    if (captchaInputs.value[index]) {
      captchaInputs.value[index] = ''
      const fullCode = captchaInputs.value.join('')
      emit('update:captchaText', fullCode)
    } else if (index > 0) {
      captchaInputs.value[index - 1] = ''
      const fullCode = captchaInputs.value.join('')
      emit('update:captchaText', fullCode)
      inputRefs.value[index - 1]?.focus()
    }
    event.preventDefault()
  }
  if (event.key === 'Enter') {
    emit('confirm')
  }
  if (event.key === 'ArrowLeft' && index > 0) {
    inputRefs.value[index - 1]?.focus()
  }
  if (event.key === 'ArrowRight' && index < 3) {
    inputRefs.value[index + 1]?.focus()
  }
}

const handlePaste = (event, index) => {
  event.preventDefault()
  const pastedText = event.clipboardData.getData('text').slice(0, 4)
  const chars = pastedText.split('')

  for (let i = 0; i < chars.length && (index + i) < 4; i++) {
    captchaInputs.value[index + i] = chars[i]
  }

  const fullCode = captchaInputs.value.join('')
  emit('update:captchaText', fullCode)

  const nextIndex = Math.min(index + chars.length, 3)
  inputRefs.value[nextIndex]?.focus()
}
</script>

<style scoped>
.captcha-modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 2000;
  background: rgba(43, 43, 43, 0.5);
}

.captcha-modal {
  background: var(--bg-color-primary);
  border-radius: 16px;
  width: 250px;
  max-width: 90vw;
  overflow: hidden;
  border: 1px solid var(--border-color-primary);
}

.modal-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 14px;
  border-bottom: 1px solid var(--border-color-primary);
  flex-shrink: 0;
  background: var(--bg-color-primary);
}

.modal-header h4 {
  margin: 0;
  color: var(--text-color-primary);
}

.close-btn {
  width: 30px;
  height: 30px;
  background: var(--bg-color-secondary);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  border: none;
  cursor: pointer;
  padding: 5px;
  color: var(--text-color-primary);
  transition: all 0.2s ease;
}

.close-btn:hover {
  color: var(--text-color-secondary);
  transform: scale(1.1);
  transition: all 0.2s ease;
}

.close-btn svg {
  width: 16px;
  height: 16px;
}

.captcha-content {
  padding: 12px;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.captcha-image-container {
  display: flex;
  align-items: center;
  gap: 8px;
  height: 40px;
}

.captcha-loading,
.captcha-image,
.captcha-error {
  width: 120px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--border-color-primary);
  background: var(--bg-color-secondary);
}

.captcha-loading {
  flex-direction: row;
  gap: 8px;
  color: var(--text-color-secondary);
  font-size: 14px;
}

.loading-spinner {
  width: 20px;
  height: 20px;
  border: 2px solid var(--border-color-secondary);
  border-top: 2px solid var(--primary-color);
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  0% {
    transform: rotate(0deg);
  }

  100% {
    transform: rotate(360deg);
  }
}

.captcha-image {
  cursor: pointer;
  transition: opacity 0.2s ease;
  overflow: hidden;
}

.captcha-image:hover {
  opacity: 0.8;
}

.captcha-error {
  color: var(--primary-color);
  font-size: 14px;
}

.captcha-image-wrapper.clickable {
  cursor: pointer;
  margin-bottom: 20px;
}

.captcha-image-wrapper.clickable:hover {
  border-color: var(--primary-color);
  background: var(--bg-color-tertiary);
}

.captcha-inputs {
  display: flex;
  gap: 8px;
  justify-content: center;
  margin-bottom: 12px;
}

.captcha-input-box {
  width: 40px;
  height: 40px;
  border: 1.5px solid var(--border-color-primary);
  border-radius: 5px;
  font-size: 18px;
  font-weight: 600;
  text-align: center;
  background: var(--bg-color-primary);
  color: var(--text-color-primary);
  caret-color: var(--primary-color);
  transition: all 0.2s ease;
  box-sizing: border-box;
}

.captcha-input-box:focus {
  outline: none;
  border-color: var(--primary-color);
  background: var(--bg-color-primary);
}

.form-actions {
  display: flex;
  justify-content: center;
  gap: 10px;
  margin-bottom: 10px;
}

.btn {
  padding: 8px 16px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  transition: all 0.2s;
  text-decoration: none;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-primary {
  background-color: var(--primary-color);
  color: white;
}

.btn-primary:hover:not(:disabled) {
  background-color: var(--primary-color-dark);
}

.btn-outline {
  background-color: transparent;
  color: var(--text-color-secondary);
  border: 1px solid var(--border-color-primary);
}

.btn-outline:hover:not(:disabled) {
  background-color: var(--bg-color-secondary);
}
</style>
