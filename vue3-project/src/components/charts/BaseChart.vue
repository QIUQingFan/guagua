<template>
  <div class="base-chart-wrap" :style="{ height }">
    <div ref="elRef" class="base-chart-canvas"></div>
    <div v-if="empty" class="base-chart-empty">{{ emptyText }}</div>
  </div>
</template>

<script setup>
import { ref, shallowRef, watch, onMounted, onBeforeUnmount, nextTick } from 'vue'
import * as echarts from 'echarts'

const props = defineProps({
  option: { type: Object, default: () => ({}) },
  height: { type: String, default: '240px' },
  loading: { type: Boolean, default: false },
  emptyText: { type: String, default: '暂无数据' },
})

const elRef = ref(null)
let chart = null
let ro = null
const empty = ref(false)

function computeEmpty(option) {
  if (!option || typeof option !== 'object') return true
  const series = option.series
  if (!Array.isArray(series) || series.length === 0) return true
  return series.every(s => {
    const d = s && s.data
    return !d || (Array.isArray(d) && d.length === 0)
  })
}

function render() {
  if (!chart || !props.option) return
  empty.value = computeEmpty(props.option)
  chart.setOption(props.option, { notMerge: false })
  chart.resize()
}

onMounted(async () => {
  await nextTick()
  if (!elRef.value) return
  chart = echarts.init(elRef.value)
  if (typeof ResizeObserver !== 'undefined') {
    ro = new ResizeObserver(() => {
      chart?.resize()
    })
    ro.observe(elRef.value)
  }
  render()
})

watch(
  () => props.option,
  () => render(),
  { deep: true }
)

onBeforeUnmount(() => {
  ro?.disconnect()
  ro = null
  chart?.dispose()
  chart = null
})

defineExpose({
  resize: () => chart?.resize(),
  getInstance: () => chart,
})
</script>

<style scoped>
.base-chart-wrap {
  position: relative;
  width: 100%;
}
.base-chart-canvas {
  width: 100%;
  height: 100%;
}
.base-chart-empty {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-color-quaternary, #9ca3af);
  font-size: 13px;
  pointer-events: none;
}
</style>
