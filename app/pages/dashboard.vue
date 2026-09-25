<script setup>
import { createClient } from '@supabase/supabase-js'

const runtimeConfig = useRuntimeConfig()
const metrics = ref([])
const products = ref([])
const sales = ref([])
const inventory = ref([])
const staff = ref([])
const trendRange = ref('week')
let salesChannel

const supabase = computed(() => {
  const url = runtimeConfig.public.supabaseUrl
  const key = runtimeConfig.public.supabaseAnonKey

  if (!url || !key) return null
  return createClient(url, key)
})

const formatPeso = (value) =>
  new Intl.NumberFormat('en-PH', {
    style: 'currency',
    currency: 'PHP',
    maximumFractionDigits: 0,
  }).format(Number(value) || 0)

const getStatus = (stock) => {
  const qty = Number(stock) || 0
  if (qty <= 0) return 'Out of Stock'
  if (qty <= 10) return 'Low Stock'
  return 'Active'
}

const metricPath = (label) => {
  if (label === "Today's Revenue") return '/sales'
  if (label === 'Replacements Today') return '/sales'
  if (label === 'Products') return '/products'
  return '/inventory'
}

const isTodayInShopTimezone = (dateValue) => {
  const formatDate = (date) => new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date)

  return formatDate(new Date(dateValue)) === formatDate(new Date())
}

const trendSettings = {
  week: { label: 'Weekly' },
  month: { label: 'Monthly' },
  year: { label: 'Yearly' },
}

const trendBuckets = computed(() => {
  const now = new Date()
  const buckets = []

  if (trendRange.value === 'week') {
    const weekStart = new Date(now)
    weekStart.setHours(0, 0, 0, 0)
    weekStart.setDate(now.getDate() - now.getDay())

    for (let index = 0; index < 7; index += 1) {
      const date = new Date(weekStart)
      date.setDate(weekStart.getDate() + index)
      buckets.push({
        start: date,
        label: date.toLocaleDateString('en-PH', { weekday: 'short' }),
        value: 0,
      })
    }
  }

  if (trendRange.value === 'month') {
    for (let index = 0; index < 12; index += 1) {
      const date = new Date(now.getFullYear(), index, 1)
      buckets.push({
        start: date,
        label: date.toLocaleDateString('en-PH', { month: 'short' }),
        value: 0,
      })
    }
  }

  if (trendRange.value === 'year') {
    for (let year = 2024; year <= now.getFullYear(); year += 1) {
      buckets.push({
        start: new Date(year, 0, 1),
        label: String(year),
        value: 0,
      })
    }
  }

  sales.value.forEach((sale) => {
    const saleDate = new Date(sale.created_at)
    const bucket = buckets.find((entry) => {
      if (trendRange.value === 'year') {
        return entry.start.getFullYear() === saleDate.getFullYear()
      }

      if (trendRange.value === 'month') {
        return entry.start.getFullYear() === saleDate.getFullYear() && entry.start.getMonth() === saleDate.getMonth()
      }

      return entry.start.toDateString() === new Date(saleDate.getFullYear(), saleDate.getMonth(), saleDate.getDate()).toDateString()
    })

    if (bucket) bucket.value += Number(sale.total_amount || 0)
  })

  return buckets
})

const trendMax = computed(() => Math.max(...trendBuckets.value.map((bucket) => bucket.value), 1))
const trendTotal = computed(() => trendBuckets.value.reduce((sum, bucket) => sum + bucket.value, 0))
const trendPoints = computed(() => trendBuckets.value.map((bucket, index) => {
  const x = trendBuckets.value.length === 1 ? 300 : (index / (trendBuckets.value.length - 1)) * 560 + 20
  const y = 172 - (bucket.value / trendMax.value) * 140
  return { ...bucket, x, y }
}))
const trendLine = computed(() => trendPoints.value.map((point) => `${point.x},${point.y}`).join(' '))
const trendArea = computed(() => `${trendLine.value} 580,172 20,172`)
const trendPeriodLabel = computed(() => trendSettings[trendRange.value].label)

const fetchDashboardData = async () => {
  if (!supabase.value) return

  const [productsResult, salesResult, profilesResult, replacementsResult] = await Promise.all([
    supabase.value.from('products').select('*').order('created_at', { ascending: false }),
    supabase.value.from('sales').select('*').order('created_at', { ascending: false }),
    supabase.value.from('profiles').select('display_name, role').order('created_at', { ascending: false }),
    supabase.value.from('inventory_adjustments').select('quantity, created_at'),
  ])

  const productRows = productsResult.data || []
  const saleRows = salesResult.data || []
  const profileRows = profilesResult.data || []
  const replacementRows = replacementsResult.data || []

  products.value = productRows.map((product) => {
    const stock = Number(product.stock) || 0
    const soldCount = saleRows.filter((sale) => sale.product_id === product.id).reduce((sum, sale) => sum + Number(sale.quantity || 0), 0)

    return {
      name: product.name,
      category: product.category,
      stock,
      price: formatPeso(product.price),
      sold: soldCount,
      status: getStatus(stock),
    }
  })

  sales.value = saleRows.map((row) => ({
    id: row.id,
    created_at: row.created_at,
    total_amount: row.total_amount,
    time: new Date(row.created_at).toLocaleString(),
    amount: formatPeso(row.total_amount),
    channel: row.employee_name || 'In shop',
  }))

  inventory.value = productRows.slice(0, 6).map((product) => ({
    item: product.name,
    level: getStatus(product.stock),
    units: Number(product.stock) || 0,
    reorder: Number(product.stock) <= 10 ? 'Restock' : 'OK',
  }))

  const employeeCounts = saleRows.reduce((acc, sale) => {
    const key = sale.employee_name || 'Employee'
    acc[key] = (acc[key] || 0) + Number(sale.total_amount || 0)
    return acc
  }, {})

  staff.value = profileRows.map((profile) => ({
    name: profile.display_name || 'Staff member',
    role: profile.role || 'employee',
    sales: formatPeso(employeeCounts[profile.display_name || 'Staff member'] || 0),
    status: 'Active',
  }))

  const todaysSales = saleRows.filter((sale) => isTodayInShopTimezone(sale.created_at))
  const totalRevenue = todaysSales
    .reduce((sum, sale) => sum + Number(sale.total_amount || 0), 0)
  const replacementUnitsToday = replacementRows
    .filter((replacement) => isTodayInShopTimezone(replacement.created_at))
    .reduce((sum, replacement) => sum + Number(replacement.quantity || 0), 0)
  const totalProducts = productRows.length
  const lowStockCount = productRows.filter((product) => Number(product.stock) <= 10).length
  const totalStock = productRows.reduce((sum, product) => sum + Number(product.stock || 0), 0)

  metrics.value = [
    { label: "Today's Revenue", value: formatPeso(totalRevenue), delta: 'Live', tone: 'dark' },
    { label: 'Replacements Today', value: String(replacementUnitsToday), delta: 'Today', tone: 'dark' },
    { label: 'Products', value: String(totalProducts), delta: 'Stock', tone: 'dark' },
    { label: 'Low Stock', value: String(lowStockCount), delta: 'Alert', tone: 'dark' },
    { label: 'Units', value: String(totalStock), delta: 'In hand', tone: 'dark' },
  ]
}

onMounted(async () => {
  await fetchDashboardData()

  if (supabase.value) {
    salesChannel = supabase.value
      .channel('dashboard-sales')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'sales' }, fetchDashboardData)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'inventory_adjustments' }, fetchDashboardData)
      .subscribe()
  }
})

onUnmounted(() => {
  if (salesChannel && supabase.value) supabase.value.removeChannel(salesChannel)
})
</script>

<template>
  <div class="dashboard-shell">
    <main class="main-panel">
      <header class="topbar">
        <div>
          <p class="eyebrow">Dashboard</p>
          <h2>Store overview</h2>
        </div>

      </header>

      <section class="stats-grid">
        <article
          v-for="metric in metrics"
          :key="metric.label"
          :class="['stat-card stat-card-link', { 'low-stock-metric': metric.label === 'Low Stock' }]"
          role="link"
          tabindex="0"
          @click="navigateTo(metricPath(metric.label))"
          @keydown.enter="navigateTo(metricPath(metric.label))"
        >
          <div class="stat-top">
            <span>{{ metric.label }}</span>
            <span :class="['badge', metric.tone]">{{ metric.delta }}</span>
          </div>
          <strong>{{ metric.value }}</strong>
        </article>
      </section>

      <section class="content-grid">
        <div class="panel large-panel">
          <div class="panel-header">
            <h3>Top Products</h3>
            <button type="button" @click="navigateTo('/products')">View all</button>
          </div>

          <div class="product-list">
            <div v-for="product in products" :key="product.name" class="product-item">
              <div>
                <h4>{{ product.name }}</h4>
                <p>{{ product.category }}</p>
              </div>
              <div class="product-meta">
                <span :class="{ 'low-stock-copy': product.stock <= 10 }">
                  <span v-if="product.stock <= 10" class="stock-alert-dot" aria-label="Low stock"></span>
                  {{ product.stock }} in stock
                </span>
                <strong>{{ product.price }}</strong>
              </div>
              <div class="mini-pill">{{ product.sold }} sold</div>
            </div>
          </div>
        </div>

        <div class="panel">
          <div class="panel-header">
            <h3>Sales Trend</h3>
            <div class="trend-tabs" role="tablist" aria-label="Sales trend period">
              <button
                v-for="range in Object.keys(trendSettings)"
                :key="range"
                type="button"
                :class="{ active: trendRange === range }"
                @click="trendRange = range"
              >
                {{ trendSettings[range].label }}
              </button>
            </div>
          </div>

          <div class="trend-summary">
            <strong>{{ formatPeso(trendTotal) }}</strong>
            <span>{{ trendPeriodLabel }} revenue</span>
          </div>

          <div class="trend-chart" role="img" :aria-label="`${trendPeriodLabel} sales trend`">
            <svg viewBox="0 0 600 190" preserveAspectRatio="none">
              <line v-for="line in [32, 102, 172]" :key="line" x1="20" :y1="line" x2="580" :y2="line" />
              <polygon :points="trendArea" />
              <polyline :points="trendLine" />
              <circle v-for="point in trendPoints" :key="point.x" :cx="point.x" :cy="point.y" r="3.5" />
            </svg>
          </div>
          <div class="chart-labels">
            <span v-for="point in trendPoints" :key="`${point.label}-${point.x}`">{{ point.label }}</span>
          </div>
        </div>
      </section>

      <section class="bottom-grid">
        <div class="panel">
          <div class="panel-header">
            <h3>Inventory</h3>
            <button type="button" @click="navigateTo('/products')">Restock</button>
          </div>

          <table>
            <thead>
              <tr>
                <th>Item</th>
                <th>Level</th>
                <th>Units</th>
                <th>Reorder</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in inventory" :key="row.item">
                <td>{{ row.item }}</td>
                <td>
                  <span :class="['status', row.level.toLowerCase().replace(' ', '-') ]">
                    <span v-if="row.level === 'Low Stock'" class="stock-alert-dot" aria-label="Low stock"></span>
                    {{ row.level }}
                  </span>
                </td>
                <td>{{ row.units }}</td>
                <td>{{ row.reorder }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="panel">
          <div class="panel-header">
            <h3>Staff</h3>
          </div>

          <div class="staff-list">
            <div v-for="member in staff" :key="member.name" class="staff-item">
              <div class="avatar">{{ member.name.charAt(0) }}</div>
              <div>
                <h4>{{ member.name }}</h4>
                <p>{{ member.role }}</p>
              </div>
              <div class="staff-meta">
                <strong>{{ member.sales }}</strong>
                <span>{{ member.status }}</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="panel sales-panel">
        <div class="panel-header">
          <h3>Recent Sales</h3>
          <button>Export</button>
        </div>

        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Amount</th>
              <th>Channel</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="item in sales" :key="item.time">
              <td>{{ item.time }}</td>
              <td>{{ item.amount }}</td>
              <td>{{ item.channel }}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </main>
  </div>
</template>

<style scoped>
:global(body) {
  margin: 0;
  font-family: Inter, 'Segoe UI', sans-serif;
  background: #f5f5f5;
  color: #111111;
}

* {
  box-sizing: border-box;
}

button {
  font: inherit;
}

.dashboard-shell {
  min-height: 100vh;
  display: flex;
  background: #f5f5f5;
  color: #111111;
}

.sidebar {
  position: sticky;
  top: 0;
  width: 260px;
  min-height: 100vh;
  background: #0d0d0d;
  border-right: 1px solid rgba(255, 255, 255, 0.08);
  padding: 24px 18px;
  display: flex;
  flex-direction: column;
  gap: 28px;
}

.brand-wrap {
  display: flex;
  align-items: center;
  gap: 12px;
}

.brand-mark {
  width: 42px;
  height: 42px;
  border-radius: 12px;
  display: grid;
  place-items: center;
  background: #ffffff;
  color: #111111;
  font-weight: 800;
}

.eyebrow {
  margin: 0 0 4px;
  color: #a1a1a1;
  font-size: 11px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.brand-wrap h1,
.topbar h2,
.panel-header h3,
.product-item h4,
.staff-item h4 {
  margin: 0;
}

.brand-wrap h1,
.topbar h2,
.panel-header h3,
.product-item h4,
.staff-item h4,
.stat-card strong,
.sidebar-card h3 {
  color: #111111;
}

.nav {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.nav-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  border: none;
  background: transparent;
  color: #d4d4d4;
  text-align: left;
  padding: 12px 14px;
  border-radius: 12px;
  cursor: pointer;
  transition: 0.2s ease;
  text-decoration: none;
  font-weight: 600;
  letter-spacing: 0.01em;
}

.nav-item.active,
.nav-item:hover {
  background: rgba(255, 255, 255, 0.08);
  color: #ffffff;
}

.sidebar-card {
  margin-top: auto;
  padding: 18px;
  border-radius: 16px;
  background: #f3f3f3;
  border: 1px solid rgba(17, 17, 17, 0.08);
}

.sidebar-card h3 {
  margin: 8px 0;
  font-size: 30px;
}

.sidebar-card span,
.small-text,
.product-item p,
.staff-item p,
.search-box,
table,
.product-meta span,
.card-label {
  color: #636363;
}

.main-panel {
  flex: 1;
  padding: 26px;
}

.topbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 18px;
  margin-bottom: 24px;
}

.toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
}

.search-box {
  min-width: 220px;
  padding: 11px 14px;
  border-radius: 12px;
  background: #ffffff;
  border: 1px solid rgba(17, 17, 17, 0.08);
}

.primary-btn,
.panel-header button {
  border: none;
  border-radius: 12px;
  cursor: pointer;
  transition: 0.2s ease;
}

.primary-btn {
  padding: 11px 16px;
  background: #111111;
  color: #ffffff;
  font-weight: 600;
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(180px, 1fr));
  gap: 18px;
  margin-bottom: 24px;
}

.stat-card,
.panel {
  background: #ffffff;
  border: 1px solid rgba(17, 17, 17, 0.06);
  border-radius: 18px;
  box-shadow: 0 8px 22px rgba(17, 17, 17, 0.04);
}

.stat-card {
  padding: 18px 20px;
}

.stat-card-link {
  cursor: pointer;
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}

.stat-card-link:hover,
.stat-card-link:focus-visible {
  outline: none;
  transform: translateY(-2px);
  box-shadow: 0 12px 26px rgba(17, 17, 17, 0.1);
}

.low-stock-metric strong {
  color: #b42323;
}

.stat-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  color: #494949;
  font-size: 13px;
}

.badge {
  padding: 5px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
  background: #111111;
  color: #ffffff;
}

.badge.dark {
  background: #111111;
  color: #ffffff;
}

.stat-card strong {
  display: block;
  margin-top: 18px;
  font-size: 32px;
  letter-spacing: -0.04em;
}

.content-grid,
.bottom-grid {
  display: grid;
  grid-template-columns: 1.35fr 0.9fr;
  gap: 18px;
  margin-bottom: 18px;
}

.panel {
  padding: 18px 20px;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 18px;
}

.panel-header button {
  background: #f2f2f2;
  color: #111111;
  padding: 8px 12px;
  border: 1px solid rgba(17, 17, 17, 0.06);
}

.product-list,
.staff-list {
  display: grid;
  gap: 12px;
}

.product-item,
.staff-item {
  display: grid;
  grid-template-columns: 1.2fr auto auto;
  align-items: center;
  gap: 12px;
  padding: 12px 14px;
  border-radius: 14px;
  background: #fafafa;
  border: 1px solid rgba(17, 17, 17, 0.05);
}

.product-item p,
.staff-item p {
  margin: 4px 0 0;
  font-size: 12px;
}

.product-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
}

.product-meta strong {
  font-size: 18px;
}

.mini-pill,
.status {
  display: inline-flex;
  align-items: center;
  padding: 6px 9px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
}

.low-stock-copy {
  display: inline-flex;
  align-items: center;
  color: #b42323;
}

.stock-alert-dot {
  width: 7px;
  height: 7px;
  flex: 0 0 7px;
  margin-right: 6px;
  border-radius: 50%;
  background: #d93434;
  box-shadow: 0 0 0 3px rgba(217, 52, 52, 0.14);
}

.mini-pill {
  background: #111111;
  color: #ffffff;
}

.chart {
  height: 170px;
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
  align-items: end;
  gap: 12px;
  padding: 12px 10px 0;
}

.chart span {
  display: block;
  border-radius: 12px 12px 0 0;
  background: linear-gradient(180deg, #111111, #6b6b6b);
}

.chart-labels {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  text-align: center;
  color: #666666;
  font-size: 12px;
  margin-top: 10px;
}

.trend-tabs {
  display: inline-flex;
  gap: 3px;
  padding: 3px;
  border-radius: 9px;
  background: #f2f2f2;
}

.trend-tabs button {
  padding: 6px 8px;
  border: 0;
  border-radius: 7px;
  background: transparent;
  color: #777777;
  cursor: pointer;
  font-size: 11px;
  font-weight: 700;
}

.trend-tabs button.active {
  background: #111111;
  color: #ffffff;
}

.trend-summary {
  display: flex;
  align-items: baseline;
  gap: 8px;
  margin: -4px 0 8px;
}

.trend-summary strong {
  font-size: 22px;
  letter-spacing: -0.03em;
}

.trend-summary span {
  color: #777777;
  font-size: 12px;
}

.trend-chart {
  height: 190px;
  margin: 0 -4px;
}

.trend-chart svg {
  display: block;
  width: 100%;
  height: 100%;
  overflow: visible;
}

.trend-chart line {
  stroke: #e8e8e8;
  stroke-width: 1;
}

.trend-chart polygon {
  fill: rgba(17, 17, 17, 0.08);
}

.trend-chart polyline {
  fill: none;
  stroke: #111111;
  stroke-linecap: round;
  stroke-linejoin: round;
  stroke-width: 3;
}

.trend-chart circle {
  fill: #ffffff;
  stroke: #111111;
  stroke-width: 2;
}

.panel .chart-labels {
  grid-template-columns: repeat(auto-fit, minmax(0, 1fr));
  gap: 2px;
  margin: 4px 0 0;
  font-size: 10px;
  white-space: nowrap;
}

table {
  width: 100%;
  border-collapse: collapse;
}

th,
td {
  text-align: left;
  padding: 12px 10px;
  border-bottom: 1px solid rgba(17, 17, 17, 0.08);
}

th {
  color: #111111;
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.status.healthy {
  background: rgba(17, 17, 17, 0.08);
  color: #111111;
}

.status.medium {
  background: rgba(17, 17, 17, 0.04);
  color: #444444;
}

.status.low {
  background: rgba(217, 52, 52, 0.1);
  color: #b42323;
}

.status.low-stock {
  background: rgba(217, 52, 52, 0.1);
  color: #b42323;
}

.status.healthy,
.status.low,
.status.medium {
  display: inline-flex;
}

.staff-item {
  grid-template-columns: auto 1fr auto;
}

.avatar {
  width: 38px;
  height: 38px;
  border-radius: 50%;
  display: grid;
  place-items: center;
  background: #111111;
  color: #ffffff;
  font-weight: 700;
}

.staff-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
}

.sales-panel {
  margin-top: 18px;
}

@media (max-width: 980px) {
  .dashboard-shell {
    flex-direction: column;
  }

  .stats-grid,
  .content-grid,
  .bottom-grid {
    grid-template-columns: 1fr;
  }

  .topbar {
    flex-direction: column;
    align-items: flex-start;
  }

  .trend-tabs button {
    padding-inline: 7px;
  }
}
</style>
