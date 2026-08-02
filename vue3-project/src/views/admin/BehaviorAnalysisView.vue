<template>
  <div class="admin-page behavior-analysis">
    
    <section class="section-card control-card">
      <div class="filter-bar control-row">
        <select v-model="rangeKey" class="range-select" @change="onRangeChange">
          <option value="today">今天</option>
          <option value="7d">近 7 天</option>
          <option value="30d">近 30 天</option>
          <option value="custom">自定义区间</option>
        </select>
        <div v-if="rangeKey === 'custom'" class="custom-range">
          <input type="date" v-model="customStart" @change="refresh" />
          <span>至</span>
          <input type="date" v-model="customEnd" @change="refresh" />
        </div>
        <button class="refresh-btn" :disabled="loading" @click="refresh">
          <span v-if="loading" class="spinner"></span>
          {{ loading ? '加载中…' : '刷新' }}
        </button>
      </div>
      <div class="meta-row" v-if="snapshot">
        <span class="meta-time" v-if="snapshot.latestDataAt">数据最新：{{ snapshot.latestDataAt }}</span>
        <span class="meta-time" v-if="snapshot.generatedAt">生成：{{ snapshot.generatedAt }}</span>
      </div>
    </section>

    
    <div v-if="snapshot?.rangeAnchoredAt" class="anchor-banner">
      选定日历区间内无行为数据，已自动回退到以最新行为时间（{{ snapshot.rangeAnchoredAt }}）为锚点的数据。
    </div>

    
    <section class="metrics-grid" v-if="snapshot">
      <div v-for="m in metricCards" :key="m.key" class="metric-card">
        <div class="metric-label">{{ m.label }}</div>
        <div class="metric-value">{{ m.value }}</div>
      </div>
    </section>

    
    <section class="charts-grid" v-if="snapshot">
      <div class="chart-card">
        <h3 class="card-title">转化漏斗（浏览 → 加购 → 成交）</h3>
        <BaseChart :option="funnelOption" height="300px" empty-text="暂无漏斗数据" />
      </div>
      <div class="chart-card ai-ctr-card">
        <h3 class="card-title">AI 推荐点击率</h3>
        <div class="ctr-body">
          <div class="ctr-ring">
            <BaseChart :option="ctrGaugeOption" height="200px" />
          </div>
          <div class="ctr-stats">
            <div class="ctr-stat"><span class="ctr-num">{{ aiRecommend.exposures }}</span><span class="ctr-label">推荐曝光</span></div>
            <div class="ctr-stat"><span class="ctr-num">{{ aiRecommend.clicks }}</span><span class="ctr-label">点击次数</span></div>
            <div class="ctr-stat"><span class="ctr-num">{{ (aiRecommend.ctr * 100).toFixed(1) }}%</span><span class="ctr-label">点击率</span></div>
          </div>
        </div>
        <div class="ctr-hint" v-if="aiRecommend.exposures === 0">
          暂无 AI 推荐曝光数据。当前商城推荐位为热门推荐（非 AI），AI 推荐点击率将在接入 AI 推荐组件后自动统计。
        </div>
      </div>
    </section>

    
    <section class="chart-card" v-if="snapshot">
      <h3 class="card-title">行为趋势（浏览 / 加购 / 成交）</h3>
      <BaseChart :option="trendOption" height="300px" empty-text="暂无趋势数据" />
    </section>

    
    <section class="bottom-grid" v-if="snapshot">
      <div class="section-card table-card">
        <h3 class="card-title">浏览 Top10</h3>
        <table class="data-table">
          <thead>
            <tr><th>商品</th><th>浏览次数</th><th>浏览人数</th><th>库存</th></tr>
          </thead>
          <tbody>
            <tr v-for="(p, i) in topViewed" :key="'v' + i">
              <td class="prod-cell">
                <img v-if="p.coverImage" :src="p.coverImage" class="prod-cover" />
                <span>{{ p.name }}</span>
              </td>
              <td>{{ p.actionCount }}</td>
              <td>{{ p.userCount }}</td>
              <td :class="{ 'low-stock': p.stock < 10 }">{{ p.stock }}</td>
            </tr>
            <tr v-if="!topViewed.length"><td colspan="4" class="empty-state">暂无浏览数据（需前端 ProductDetail 上报 view 行为）</td></tr>
          </tbody>
        </table>
      </div>
      <div class="section-card table-card">
        <h3 class="card-title">加购 Top10</h3>
        <table class="data-table">
          <thead>
            <tr><th>商品</th><th>加购次数</th><th>加购人数</th><th>库存</th></tr>
          </thead>
          <tbody>
            <tr v-for="(p, i) in topCarted" :key="'c' + i">
              <td class="prod-cell">
                <img v-if="p.coverImage" :src="p.coverImage" class="prod-cover" />
                <span>{{ p.name }}</span>
              </td>
              <td>{{ p.actionCount }}</td>
              <td>{{ p.userCount }}</td>
              <td :class="{ 'low-stock': p.stock < 10 }">{{ p.stock }}</td>
            </tr>
            <tr v-if="!topCarted.length"><td colspan="4" class="empty-state">暂无加购数据（需前端加购流程上报 cart 行为）</td></tr>
          </tbody>
        </table>
      </div>
    </section>

    
    <section class="section-card alerts-card" v-if="alerts.length">
      <h3 class="card-title">风险预警</h3>
      <div class="alert-item" v-for="(a, i) in alerts" :key="i">{{ a }}</div>
    </section>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import BaseChart from '@/components/charts/BaseChart.vue'
import { getBehaviorSnapshot } from '@/api/dashboard.js'

const loading = ref(false)
const rangeKey = ref('7d')
const customStart = ref('')
const customEnd = ref('')
const snapshot = ref(null)

const funnel = computed(() => snapshot.value?.funnel || {})
const topViewed = computed(() => snapshot.value?.behaviorTopN?.viewed || [])
const topCarted = computed(() => snapshot.value?.behaviorTopN?.carted || [])
const aiRecommend = computed(() => snapshot.value?.aiRecommend || { exposures: 0, clicks: 0, ctr: 0 })
const alerts = computed(() => snapshot.value?.alerts || [])

const metricCards = computed(() => [
  { key: 'views', label: '浏览（人+商品）', value: funnel.value.views ?? 0 },
  { key: 'carts', label: '加购（人+商品）', value: funnel.value.carts ?? 0 },
  { key: 'purchases', label: '成交（人+商品）', value: funnel.value.purchases ?? 0 },
  { key: 'conv', label: '整体转化率', value: fmtPercent(funnel.value.overallConversionRate) },
])

function fmtPercent(v) { return `${(Number(v || 0) * 100).toFixed(1)}%` }

function buildRangeParam() {
  if (rangeKey.value === 'custom' && customStart.value && customEnd.value) {
    return { range: 'custom', startDate: customStart.value, endDate: customEnd.value }
  }
  return { range: rangeKey.value }
}

async function refresh() {
  loading.value = true
  try {
    const params = buildRangeParam()
    const res = await getBehaviorSnapshot(params.range, params.startDate, params.endDate)
    snapshot.value = res?.data ?? res
  } catch (e) {
    console.error('[Behavior] refresh error', e)
  } finally {
    loading.value = false
  }
}

function onRangeChange() {
  if (rangeKey.value !== 'custom') refresh()
}


const funnelOption = computed(() => {
  const f = funnel.value
  return {
    tooltip: {
      trigger: 'item',
      formatter: (p) => {
        const rates = [100, (f.viewToCartRate * 100).toFixed(1), (f.cartToPurchaseRate * 100).toFixed(1)]
        return `${p.name}<br/>数量：${p.value}<br/>阶段转化率：${rates[p.dataIndex] || 0}%`
      },
    },
    color: ['#3b82f6', '#f59e0b', '#10b981'],
    series: [{
      type: 'funnel',
      left: '10%', right: '10%', top: 10, bottom: 10,
      minSize: '30%',
      label: { show: true, position: 'inside', formatter: '{b}\n{c}', color: '#fff' },
      gap: 4,
      data: [
        { name: '浏览', value: f.views ?? 0 },
        { name: '加购', value: f.carts ?? 0 },
        { name: '成交', value: f.purchases ?? 0 },
      ],
    }],
  }
})


const ctrGaugeOption = computed(() => ({
  series: [{
    type: 'gauge',
    startAngle: 90, endAngle: -270,
    radius: '90%',
    pointer: { show: true },
    progress: { show: true, overlap: false, roundCap: true, clip: false, itemStyle: { color: '#dc1257' } },
    axisLine: { lineStyle: { width: 14, color: [[1, 'rgba(15,23,42,0.08)']] } },
    splitLine: { show: false },
    axisTick: { show: false },
    axisLabel: { show: false },
    data: [{ value: Number((aiRecommend.value.ctr * 100).toFixed(1)), name: 'CTR%' }],
    title: { offsetCenter: [0, '70%'], fontSize: 12, color: '#6b7280' },
    detail: {
      valueAnimation: true, offsetCenter: [0, '40%'],
      formatter: '{value}%', fontSize: 22, fontWeight: 700, color: '#dc1257',
    },
    max: 100,
  }],
}))


const trendOption = computed(() => {
  const trends = snapshot.value?.trends || []
  return {
    tooltip: { trigger: 'axis' },
    legend: { top: 4, right: 12, data: ['浏览', '加购', '成交'], textStyle: { color: '#6b7280' } },
    grid: { left: 16, right: 20, top: 40, bottom: 12, containLabel: true },
    xAxis: { type: 'category', boundaryGap: false, data: trends.map(t => (t.date || '').slice(5)), axisLine: { lineStyle: { color: '#e5e7eb' } }, axisLabel: { color: '#9ca3af' } },
    yAxis: { type: 'value', name: '次数', splitLine: { lineStyle: { color: '#f0f0f0' } }, axisLabel: { color: '#9ca3af' } },
    series: [
      { name: '浏览', type: 'line', smooth: true, data: trends.map(t => t.views ?? 0),
        lineStyle: { color: '#3b82f6', width: 2 }, itemStyle: { color: '#3b82f6' }, symbol: 'circle', symbolSize: 6 },
      { name: '加购', type: 'line', smooth: true, data: trends.map(t => t.carts ?? 0),
        lineStyle: { color: '#f59e0b', width: 2 }, itemStyle: { color: '#f59e0b' }, symbol: 'circle', symbolSize: 6 },
      { name: '成交', type: 'line', smooth: true, data: trends.map(t => t.purchases ?? 0),
        lineStyle: { color: '#10b981', width: 2 }, itemStyle: { color: '#10b981' }, symbol: 'circle', symbolSize: 6 },
    ],
  }
})

onMounted(() => refresh())
</script>

<style scoped>
.behavior-analysis { animation: fadeSlide 0.25s ease; }

.control-card { padding: 14px 20px; }
.control-row { flex-wrap: wrap; }
.custom-range { display: flex; align-items: center; gap: 8px; font-size: 13px; color: var(--text-color-secondary); }
.custom-range input { padding: 7px 10px; border: 1px solid var(--border-color-primary); border-radius: 8px; background: var(--card-bg); color: var(--text-color-primary); font-size: 13px; }
.refresh-btn { padding: 8px 16px; border: none; border-radius: 8px; font-size: 13px; font-weight: 600; cursor: pointer; display: flex; align-items: center; gap: 6px; white-space: nowrap; background: var(--primary-color); color: #fff; transition: background 0.2s ease; }
.refresh-btn:disabled { opacity: 0.6; cursor: not-allowed; }
.refresh-btn:not(:disabled):hover { background: var(--primary-color-dark); }
.meta-row { margin-top: 10px; display: flex; gap: 16px; flex-wrap: wrap; }
.meta-time { color: var(--text-color-quaternary); font-size: 12px; }

.anchor-banner { background: rgba(245, 158, 11, 0.1); border: 1px solid rgba(245, 158, 11, 0.3); border-left: 3px solid var(--series-warning); color: #92400e; padding: 10px 14px; border-radius: 8px; font-size: 13px; }
[data-theme="dark"] .anchor-banner { color: #fbbf24; }

.charts-grid { display: grid; grid-template-columns: 1.4fr 1fr; gap: var(--space-md); }

.ctr-body { display: flex; gap: 16px; align-items: center; }
.ctr-ring { flex: 0 0 200px; }
.ctr-stats { flex: 1; display: flex; flex-direction: column; gap: 12px; }
.ctr-stat { display: flex; flex-direction: column; }
.ctr-num { font-size: 20px; font-weight: 700; color: var(--text-color-primary); font-variant-numeric: tabular-nums; }
.ctr-label { font-size: 12px; color: var(--text-color-tertiary); margin-top: 2px; }
.ctr-hint { margin-top: 12px; font-size: 12px; color: var(--text-color-quaternary); line-height: 1.6; }

.bottom-grid { display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-md); }

.prod-cell { display: flex; align-items: center; gap: 8px; }
.prod-cover { width: 30px; height: 30px; border-radius: 6px; object-fit: cover; }
.low-stock { color: var(--series-negative); font-weight: 600; }

.alert-item {
  padding: 11px 14px;
  background: rgba(245, 158, 11, 0.08);
  border: 1px solid rgba(245, 158, 11, 0.25);
  border-left: 3px solid var(--series-warning);
  border-radius: 8px;
  color: #9a3412;
  font-size: 13px;
  margin-bottom: 8px;
  line-height: 1.6;
}
[data-theme="dark"] .alert-item { color: #fbbf24; }

.spinner { width: 13px; height: 13px; border: 2px solid rgba(255,255,255,0.3); border-top-color: #fff; border-radius: 50%; animation: spin 0.6s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

@media (max-width: 1200px) {
  .charts-grid, .bottom-grid { grid-template-columns: 1fr; }
  .ctr-body { flex-direction: column; }
}
@media (max-width: 768px) {
  .control-row { flex-direction: column; align-items: stretch; }
}
</style>
