<script setup>
import SvgIcon from '@/components/SvgIcon.vue';
import { computed } from 'vue';

const props = defineProps({
    /**
     * 动画持续时间（秒）
     * @type {number}
     * @default 1.5
     * @description 控制整个动画序列的持续时间，包括滑入和旋转效果
     */
    duration: {
        type: Number,
        default: 1.5 
    }
});

/**
 * 计算动画样式的响应式对象
 * @description 根据传入的duration属性生成CSS自定义属性
 * @returns {Object} 包含CSS变量的样式对象
 */
const animationStyle = computed(() => ({
    '--animation-duration': `${props.duration}s`
}));
</script>

<template>
    <div class="loading-spinner" :style="animationStyle">
        <SvgIcon name="loading" class="spinner-icon" width="28" height="28" />
    </div>
</template>

<style scoped>
/**
 * 加载动画容器样式
 * @description 提供滑入动画效果和基础布局样式
 * 使用CSS变量支持动态动画持续时间
 */
.loading-spinner {
    padding: 5px 10px;
    display: flex;
    justify-content: center;
    align-items: center;
    animation: slideDown 1.5s ease-in-out;
    width: 100%;
    overflow-x: hidden;
    position: relative;
    top: 18px;
    z-index: 101;
    box-sizing: border-box;
}

/**
 * 加载图标样式
 * @description 控制图标颜色和旋转动画
 * 使用主题色彩变量，支持暗色模式切换
 */
.spinner-icon {
    color: var(--text-color-primary);
    animation: spinThreeStage 1.5s ease-in-out;
}

@keyframes slideDown {
    0% {
        transform: scale(0.7) translateY(-50%);
        opacity: 0.7;
    }

    33.33% {
        transform: scale(1) translateY(0);
        opacity: 1;
    }

    66.66% {
        transform: scale(1) translateY(0);
        opacity: 1;
    }

    100% {
        transform: scale(0.7) translateY(-50%);
        opacity: 0.7;
    }
}

@keyframes spinThreeStage {
    0% {
        transform: rotate(0deg);
    }

    33.33% {
        transform: rotate(360deg);
    }

    66.66% {
        transform: rotate(720deg);
    }

    100% {
        transform: rotate(1080deg);
    }
}
</style>