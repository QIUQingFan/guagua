<template>
  <FormModal ref="formModalRef" :visible="visible" :title="modalTitle" :form-fields="formFields" :form-data="formData"
    :loading="saving" :confirm-text="getButtonText()" @update:visible="$emit('update:visible', $event)"
    @update:form-data="updateFormData" @submit="handleSave" @close="handleClose" />
  <MessageToast v-if="showToast" :message="toastMessage" :type="toastType" @close="handleToastClose" />
</template>

<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { updatePost, getPostDetail } from '@/api/posts'
import { getCategories } from '@/api/categories'
import FormModal from '@/views/admin/components/FormModal.vue'
import MessageToast from '@/components/MessageToast.vue'

const props = defineProps({
  visible: {
    type: Boolean,
    default: false
  },
  post: {
    type: Object,
    default: () => ({})
  }
})

const emit = defineEmits(['update:visible', 'save'])

const saving = ref(false)
const formModalRef = ref(null) 

const formData = ref({
  title: '',
  content: '',
  category: '',
  tags: [],
  images: [],
  image_urls: [],
  type: 1  
})

const showToast = ref(false)
const toastMessage = ref('')
const toastType = ref('success')

const categories = ref([])

const fetchCategories = async () => {
  try {
    const response = await getCategories()
    if (response.success) {
      categories.value = response.data.map(cat => ({
        value: cat.id,
        label: cat.name
      }))
    } else {
      console.error('获取分类数据失败')
      categories.value = []
    }
  } catch (error) {
    console.error('获取分类失败:', error)
    categories.value = []
  }
}

const formFields = computed(() => {
  const baseFields = [
    {
      key: 'title',
      label: '标题',
      type: 'text',
      placeholder: '请输入标题',
      required: true,
      maxLength: 100
    },
    {
      key: 'content',
      label: '内容',
      type: 'content-editable-input',
      placeholder: '请输入内容',
      required: true,
      maxLength: 2000
    },
    {
      key: 'category',
      label: '分类',
      type: 'select',
      placeholder: '请选择分类',
      options: categories.value,
      required: true
    },
    {
      key: 'tags',
      label: '标签 (最多10个)',
      type: 'tags',
      maxTags: 10
    }
  ]

  if (formData.value.type === 2) {
    baseFields.push({
      key: 'video_upload',
      label: '视频',
      type: 'video-upload',
      placeholder: '点击更换视频',
      ref: 'videoComponent' 
    })
  } else {
    baseFields.push({
      key: 'image_urls',
      label: '图片',
      type: 'multi-image-upload',
      maxImages: 9
    })
  }

  return baseFields
})

const updateFormData = (newData) => {
  formData.value = { ...formData.value, ...newData }
}

const modalTitle = computed(() => {
  return formData.value.type === 2 ? '编辑视频笔记' : '编辑图文笔记'
})

const canSave = computed(() => {
  return formData.value.title.trim() && formData.value.content.trim()
})

const getButtonText = () => {
  if (saving.value) {
    return '保存中...'
  }
  return '保存'
}

const processPostData = (data) => {
  const newData = {
    title: data.title || '',
    content: data.content || '',
    category: data.category || '',
    tags: data.tags || [],
    images: [],
    image_urls: [],
    video_url: data.video_url || '',
    cover_url: data.cover_url || '',
    video_upload: null,
    type: data.type || 1
  }

  if (data.category && categories.value.length > 0) {
    const categoryItem = categories.value.find(cat => cat.label === data.category)
    newData.category = categoryItem ? categoryItem.value : ''
  }

  if (data.tags) {
    newData.tags = Array.isArray(data.tags)
      ? data.tags.map(tag => typeof tag === 'object' ? tag.name : tag)
      : []
  }

  if (data.images) {
    const images = Array.isArray(data.images) ? data.images : []
    newData.image_urls = images.filter(url => url)
  }

  if (data.video_url) {
    newData.video_upload = {
      url: data.video_url,
      coverUrl: data.cover_url,
      name: '已上传的视频',
      size: 0,
      uploaded: true,
      preview: data.video_url
    }
  }

  return newData
}

const initializeForm = async (postData) => {
  if (categories.value.length === 0) {
    await fetchCategories()
  }

  if (postData && postData.id) {
    try {
      if (postData.type) {
        formData.value.type = postData.type
      }

      const fullPost = await getPostDetail(postData.id)

      if (fullPost && fullPost.originalData) {
        const originalData = fullPost.originalData
        let processedData = processPostData({
          title: fullPost.title,
          content: originalData.content || fullPost.content,
          category: fullPost.category,
          tags: originalData.tags,
          images: originalData.images,
          type: fullPost.type  
        })

        if (fullPost.type === 2 && fullPost.video_url) {
          processedData.video_url = fullPost.video_url
          processedData.cover_url = fullPost.cover_url || ''
          processedData.video_upload = {
            url: fullPost.video_url,
            coverUrl: fullPost.cover_url,
            name: '已上传的视频',
            size: 0,
            uploaded: true,
            preview: fullPost.video_url
          }
        }

        formData.value = processedData

        if (fullPost.type === 2 && fullPost.video_url) {
        }
      } else {
        console.error('获取笔记详情失败: 数据格式不正确')
        formData.value = processPostData(postData)
      }
    } catch (error) {
      console.error('获取笔记详情失败:', error)
      formData.value = processPostData(postData)
    }
  } else {
    formData.value = processPostData({})
  }
}

watch(
  [() => props.visible, () => props.post && props.post.id],
  ([visible, id], [prevVisible, prevId]) => {
    if (!visible || !id) return
    if (!prevVisible || id !== prevId) {
      initializeForm(props.post)
    }
  },
  { immediate: true }
)

const showMessage = (message, type = 'success') => {
  toastMessage.value = message
  toastType.value = type
  showToast.value = true
}

const handleToastClose = () => {
  showToast.value = false
}

const handleClose = () => {
  emit('update:visible', false)
}

const handleUploadError = (error) => {
  showMessage(error, 'error')
}

onMounted(() => {
  fetchCategories()
})

const handleSave = async (processedData) => {
  if (!canSave.value) {
    showMessage('请填写完整信息', 'error')
    return
  }
  if (saving.value) return

  await savePost(processedData)
}

const savePost = async (processedData) => {
  try {
    saving.value = true

    if (processedData.video_upload) {
      delete processedData.video_upload
    }
    const postData = {
      title: (processedData.title || '').trim(),
      content: (processedData.content || '').trim(),
      category_id: processedData.category,
      tags: processedData.tags || []
    }

    if (formData.value.type === 2) {
      if (processedData.video_url) {
        postData.video = {
          url: processedData.video_url,
          coverUrl: processedData.cover_url || null
        }
      } else {
        postData.video = null
      }
      postData.images = [] 
    } else {
      postData.images = processedData.image_urls || []
      postData.video = null 
    }

    const response = await updatePost(props.post.id, postData)
    if (response.success) {
      showMessage('保存成功', 'success')
      setTimeout(() => {
        emit('save')
      }, 100)
    } else {
      showMessage(response.message || '更新失败', 'error')
    }
  } catch (error) {
    console.error('更新失败:', error)
    showMessage('更新失败，请重试', 'error')
  } finally {
    saving.value = false
  }
}
</script>