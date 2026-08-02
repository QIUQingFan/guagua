<script setup>
import WaterfallFlow from '@/components/WaterfallFlow.vue'
import FloatingBtn from './FloatingBtn.vue'
import { ref, onMounted, onUnmounted } from 'vue'

const props = defineProps({
    category: {
        type: [String, Number],
        default: 'general'
    }
})

const refreshKey = ref(0)
const isImgOnly = ref(false)

function handleReload() {
    window.dispatchEvent(new CustomEvent('floating-btn-reload-request'))
}

function handleToggleImgOnly(imgOnlyState) {
    isImgOnly.value = imgOnlyState
    refreshKey.value++
}

function handleFloatingBtnReload() {
    refreshKey.value++
    
    setTimeout(() => {
        document.dispatchEvent(new CustomEvent('force-recheck'))
    }, 100)
}

onMounted(() => {
    window.addEventListener('floating-btn-reload', handleFloatingBtnReload)
})

onUnmounted(() => {
    window.removeEventListener('floating-btn-reload', handleFloatingBtnReload)
})
</script>

<template>
    <div class="explore-page">
        <WaterfallFlow :refresh-key="refreshKey" :category="category" :type="isImgOnly ? 1 : null" />
        <FloatingBtn @reload="handleReload" @toggle-img-only="handleToggleImgOnly" />
    </div>
</template>

<style scoped>
.explore-page {
    position: relative;
    width: 100%;
    height: 100%;
}
</style>