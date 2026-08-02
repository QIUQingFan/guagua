<script setup>
import { computed, ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { getCategories } from '@/api/categories'
import ExplorePageTemplate from './components/ExplorePageTemplate.vue'

const route = useRoute()
const categories = ref([])

const channelType = computed(() => {
    if (route.params.channel) {
        return route.params.channel
    }
    return route.name || 'recommend'
})

const channelConfig = computed(() => {
    const config = {
        'recommend': { category: 'recommend', title: '推荐' }
    }
    
    categories.value.forEach(category => {
        config[category.category_title] = {
            category: category.id, 
            title: category.name
        }
        config[category.id] = {
            category: category.id,
            title: category.name
        }
    })
    
    return config
})

const currentChannel = computed(() => {
    return channelConfig.value[channelType.value] || channelConfig.value['recommend']
})

const loadCategories = async () => {
    try {
        const response = await getCategories()
        if (response.success !== false && response.data) {
            categories.value = response.data
        }
    } catch (error) {
        console.error('加载分类失败:', error)
    }
}

onMounted(() => {
    loadCategories()
})
</script>

<template>
    <ExplorePageTemplate :category="currentChannel.category" />
</template>
