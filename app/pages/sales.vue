<script setup>
import { createClient } from '@supabase/supabase-js'

const { $supabase, $auth } = useNuxtApp()
const runtimeConfig = useRuntimeConfig()
const isOwner = computed(() => $auth?.profile.value?.role === 'owner')

const summary = ref([])
const transactions = ref([])
const products = ref([])
const cart = ref([])
const search = ref('')
const confirmMessage = ref('')
const successMessage = ref('')
const isSaving = ref(false)
const showConfirm = ref(false)
const trendRange = ref('day')
const currentDate = new Date()
const selectedDate = ref(currentDate.toISOString().slice(0, 10))
const selectedMonth = ref(`${currentDate.getFullYear()}-${String(currentDate.getMonth() + 1).padStart(2, '0')}`)
const selectedYear = ref(String(currentDate.getFullYear()))
const selectedEmployee = ref('')
const selectedTrendPoint = ref(null)
let salesChannel
let successTimeout

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

const totalItems = computed(() => cart.value.reduce((sum, item) => sum + item.qty, 0))
const subtotal = computed(() => cart.value.reduce((sum, item) => sum + item.price * item.qty, 0))

const trendSettings = {
  day: { label: 'Day' },
  week: { label: 'Week' },
  month: { label: 'Month' },
  year: { label: 'Year' },
}

const yearOptions = computed(() => {
  const years = []
  for (let year = 2024; year <= currentDate.getFullYear(); year += 1) years.push(String(year))
  return years.reverse()
})

const employeeOptions = computed(() => [...new Set(
  transactions.value.map((sale) => sale.employee_name || 'Employee'),
)].sort())

const parseDateInput = (value) => {
  const [year, month, day] = value.split('-').map(Number)
  return new Date(year, month - 1, day)
}

const parseMonthInput = (value) => {
  const [year, month] = value.split('-').map(Number)
  return new Date(year, month - 1, 1)
}

const trendBuckets = computed(() => {
  const now = new Date()
  const buckets = []

  if (trendRange.value === 'day') {
    const dayStart = parseDateInput(selectedDate.value)
    dayStart.setHours(0, 0, 0, 0)

    for (let hour = 0; hour < 24; hour += 1) {
      const date = new Date(dayStart)
      date.setHours(hour)
      buckets.push({
        start: date,
        label: date.toLocaleTimeString('en-PH', { hour: 'numeric' }),
        value: 0,
        sales: [],
      })
    }
  }

  if (trendRange.value === 'week') {
    const weekStart = parseDateInput(selectedDate.value)
    weekStart.setHours(0, 0, 0, 0)
    weekStart.setDate(weekStart.getDate() - weekStart.getDay())

    for (let index = 0; index < 7; index += 1) {
      const date = new Date(weekStart)
      date.setDate(weekStart.getDate() + index)
      buckets.push({
        start: date,
        label: date.toLocaleDateString('en-PH', { weekday: 'short' }),
        value: 0,
        sales: [],
      })
    }
  }

  if (trendRange.value === 'month') {
    const monthStart = parseMonthInput(selectedMonth.value)
    const daysInMonth = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 0).getDate()
    for (let day = 1; day <= daysInMonth; day += 1) {
      buckets.push({
        start: new Date(monthStart.getFullYear(), monthStart.getMonth(), day),
        label: String(day),
        value: 0,
        sales: [],
      })
    }
  }

  if (trendRange.value === 'year') {
    for (let month = 0; month < 12; month += 1) {
      const date = new Date(Number(selectedYear.value), month, 1)
      buckets.push({
        start: date,
        label: date.toLocaleDateString('en-PH', { month: 'short' }),
        value: 0,
        sales: [],
      })
    }
  }

  transactions.value.forEach((sale) => {
    if (selectedEmployee.value && (sale.employee_name || 'Employee') !== selectedEmployee.value) return

    const saleDate = new Date(sale.created_at)
    const bucket = buckets.find((entry) => {
      if (trendRange.value === 'day') {
        return entry.start.toDateString() === saleDate.toDateString() && entry.start.getHours() === saleDate.getHours()
      }

      if (trendRange.value === 'month') {
        return entry.start.toDateString() === new Date(saleDate.getFullYear(), saleDate.getMonth(), saleDate.getDate()).toDateString()
      }

      if (trendRange.value === 'year') {
        return entry.start.getFullYear() === saleDate.getFullYear() && entry.start.getMonth() === saleDate.getMonth()
      }

      return entry.start.toDateString() === new Date(saleDate.getFullYear(), saleDate.getMonth(), saleDate.getDate()).toDateString()
    })

    if (bucket) {
      bucket.value += Number(sale.total_amount || 0)
      bucket.sales.push(sale)
    }
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
const trendSelectionLabel = computed(() => {
  if (trendRange.value === 'day') return parseDateInput(selectedDate.value).toLocaleDateString('en-PH', { dateStyle: 'long' })
  if (trendRange.value === 'week') return `Week of ${parseDateInput(selectedDate.value).toLocaleDateString('en-PH', { dateStyle: 'medium' })}`
  if (trendRange.value === 'month') return parseMonthInput(selectedMonth.value).toLocaleDateString('en-PH', { month: 'long', year: 'numeric' })
  return selectedYear.value
})
const trackedSales = computed(() => trendBuckets.value.flatMap((bucket) => bucket.sales))
const trackedRevenue = computed(() => trackedSales.value.reduce((sum, sale) => sum + Number(sale.total_amount || 0), 0))
const trackedSummary = computed(() => [
  { label: 'Total Sales', value: formatPeso(trackedRevenue.value) },
  { label: 'Transactions', value: String(trackedSales.value.length) },
  { label: 'Items Sold', value: String(trackedSales.value.reduce((sum, sale) => sum + Number(sale.quantity || 0), 0)) },
  { label: 'Avg. Ticket', value: formatPeso(trackedSales.value.length ? trackedRevenue.value / trackedSales.value.length : 0) },
])
const filteredTransactions = computed(() => {
  if (!selectedEmployee.value) return transactions.value
  return transactions.value.filter((sale) => (sale.employee_name || 'Employee') === selectedEmployee.value)
})
const selectTrendPoint = (point) => {
  selectedTrendPoint.value = point
}

watch([trendRange, selectedDate, selectedMonth, selectedYear, selectedEmployee], () => {
  selectedTrendPoint.value = null
})

const fetchSales = async () => {
  if (!supabase.value) return

  const { data, error } = await supabase.value
    .from('sales')
    .select('*')
    .order('created_at', { ascending: false })

  if (!error && data) {
    transactions.value = data
    const totalRevenue = data.reduce((sum, item) => sum + Number(item.total_amount || 0), 0)
    const totalTransactions = data.length
    const totalQty = data.reduce((sum, item) => sum + Number(item.quantity || 0), 0)

    summary.value = [
      { label: 'Total Sales', value: formatPeso(totalRevenue) },
      { label: 'Transactions', value: String(totalTransactions) },
      { label: 'Items Sold', value: String(totalQty) },
      { label: 'Avg. Ticket', value: formatPeso(totalTransactions ? totalRevenue / totalTransactions : 0) },
    ]
  }
}

const fetchProducts = async () => {
  if (!supabase.value) return

  const { data, error } = await supabase.value.from('products').select('*').order('created_at', { ascending: false })
  if (!error && data) {
    products.value = data.map((item) => ({
      id: item.id,
      name: item.name,
      flavor: item.flavor || '',
      category: item.category,
      price: Number(item.price) || 0,
      stock: Number(item.stock) || 0,
      image: item.image || '',
    }))
  }
}

const filteredProducts = computed(() => {
  const query = search.value.trim().toLowerCase()
  if (!query) return products.value

  return products.value.filter((product) => {
    return [product.name, product.flavor, product.category].some((field) =>
      (field || '').toLowerCase().includes(query),
    )
  })
})

const addToCart = (product) => {
  const existing = cart.value.find((item) => item.id === product.id)
  if (existing) {
    if (existing.qty >= product.stock) return
    existing.qty += 1
    return
  }

  cart.value.push({
    id: product.id,
    name: product.name,
    flavor: product.flavor,
    category: product.category,
    price: Number(product.price) || 0,
    stock: Number(product.stock) || 0,
    qty: 1,
  })
}

const adjustQty = (id, nextQty) => {
  const item = cart.value.find((entry) => entry.id === id)
  if (!item) return

  if (nextQty <= 0) {
    cart.value = cart.value.filter((entry) => entry.id !== id)
    return
  }

  const product = products.value.find((entry) => entry.id === id)
  const maxQty = product ? product.stock : item.stock

  if (nextQty > maxQty) return
  item.qty = nextQty
}

const completeSale = async () => {
  if (!supabase.value || !cart.value.length || isSaving.value) return

  isSaving.value = true
  confirmMessage.value = ''

  try {
    for (const item of cart.value) {
      const product = products.value.find((entry) => entry.id === item.id)
      if (!product) continue

      const nextStock = Number(product.stock) - item.qty
      if (nextStock < 0) {
        confirmMessage.value = 'Not enough stock for one or more items.'
        return
      }

      const { error: stockError } = await supabase.value
        .from('products')
        .update({
          stock: nextStock,
          status: nextStock <= 0 ? 'Out of Stock' : nextStock <= 10 ? 'Low Stock' : 'Active',
          updated_at: new Date().toISOString(),
        })
        .eq('id', item.id)

      if (stockError) {
        confirmMessage.value = `Stock update failed: ${stockError.message}`
        return
      }
    }

    const employeeName = $auth?.profile.value?.display_name || 'Employee'
    const employeeId = $auth?.user.value?.id || null

    const rows = cart.value.map((item) => ({
      product_id: item.id,
      product_name: item.name,
      flavor: item.flavor || null,
      category: item.category || null,
      quantity: item.qty,
      total_amount: Number(item.price * item.qty),
      employee_name: employeeName,
      employee_id: employeeId,
      created_at: new Date().toISOString(),
    }))

    const { error: saleError } = await supabase.value.from('sales').insert(rows)

    if (saleError) {
      confirmMessage.value = `Sale save failed: ${saleError.message}`
      return
    }

    cart.value = []
    confirmMessage.value = ''
    showConfirm.value = false
    successMessage.value = 'Sale completed successfully.'
    clearTimeout(successTimeout)
    successTimeout = setTimeout(() => {
      successMessage.value = ''
    }, 1800)
    await fetchProducts()
    await fetchSales()
  } finally {
    isSaving.value = false
  }
}

onMounted(async () => {
  await fetchSales()
  await fetchProducts()

  if (supabase.value) {
    salesChannel = supabase.value
      .channel('sales-page-sales')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'sales' }, fetchSales)
      .subscribe()
  }
})

onUnmounted(() => {
  if (salesChannel && supabase.value) supabase.value.removeChannel(salesChannel)
  clearTimeout(successTimeout)
})
</script>

<template>
  <div v-if="isOwner" class="page-shell owner-sales">
    <header class="topbar">
      <div>
        <p class="eyebrow">Sales</p>
        <h1>All sales</h1>
      </div>
      <button class="primary-btn" type="button">Export Report</button>
    </header>

    <section class="stats-grid">
      <article v-for="item in trackedSummary" :key="item.label" class="stat-card">
        <span>{{ item.label }}</span>
        <strong>{{ item.value }}</strong>
      </article>
    </section>

    <section class="panel trend-panel">
      <div class="panel-header">
        <div>
          <p class="eyebrow">Sales overview</p>
          <h2>Track revenue</h2>
        </div>
        <div class="trend-tabs" role="tablist" aria-label="Sales graph period">
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

      <div class="trend-filter">
        <label v-if="trendRange === 'day' || trendRange === 'week'">
          {{ trendRange === 'day' ? 'Select date' : 'Select a date in the week' }}
          <input v-model="selectedDate" type="date" />
        </label>
        <label v-else-if="trendRange === 'month'">
          Select month
          <input v-model="selectedMonth" type="month" />
        </label>
        <label v-else>
          Select year
          <select v-model="selectedYear">
            <option v-for="year in yearOptions" :key="year" :value="year">{{ year }}</option>
          </select>
        </label>
      </div>

      <div class="trend-summary">
        <strong>{{ formatPeso(trendTotal) }}</strong>
        <span>{{ trendSelectionLabel }} revenue</span>
      </div>

      <div class="trend-chart" role="img" :aria-label="`${trendSettings[trendRange].label} sales graph`">
        <svg viewBox="0 0 600 190" preserveAspectRatio="none" @click="selectedTrendPoint = null">
          <line v-for="line in [32, 102, 172]" :key="line" x1="20" :y1="line" x2="580" :y2="line" />
          <polygon :points="trendArea" />
          <polyline :points="trendLine" />
          <circle
            v-for="point in trendPoints"
            :key="`hit-${point.x}`"
            :cx="point.x"
            :cy="point.y"
            r="12"
            class="trend-hit-area"
            tabindex="0"
            @click.stop="selectTrendPoint(point)"
            @keydown.enter="selectTrendPoint(point)"
          />
          <circle
            v-for="point in trendPoints"
            :key="point.x"
            :cx="point.x"
            :cy="point.y"
            r="4"
            tabindex="0"
            @click.stop="selectTrendPoint(point)"
            @keydown.enter="selectTrendPoint(point)"
          />
          <g
            v-if="selectedTrendPoint"
            class="trend-callout"
            :transform="`translate(${Math.min(Math.max(selectedTrendPoint.x - 42, 8), 500)}, ${Math.max(selectedTrendPoint.y - 12, 16)})`"
          >
            <text x="0" y="0">{{ selectedTrendPoint.label }} sales {{ formatPeso(selectedTrendPoint.value) }}</text>
          </g>
        </svg>
      </div>
      <div class="chart-labels">
        <span v-for="(point, index) in trendPoints" :key="`${point.label}-${point.x}`" :class="{ 'hide-small-label': trendRange === 'day' && index % 4 !== 0 }">
          {{ point.label }}
        </span>
      </div>

    </section>

    <section class="panel sales-panel">
      <div class="panel-header">
        <h3>Sold products</h3>
        <label class="employee-filter">
          Employee
          <select v-model="selectedEmployee">
            <option value="">All employees</option>
            <option v-for="employee in employeeOptions" :key="employee" :value="employee">{{ employee }}</option>
          </select>
        </label>
      </div>

      <table>
        <thead>
          <tr>
            <th>Product</th>
            <th>Flavor</th>
            <th>Qty</th>
            <th>Employee</th>
            <th>Total</th>
            <th>Time</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="entry in filteredTransactions" :key="entry.id">
            <td>{{ entry.product_name }}</td>
            <td>{{ entry.flavor || '—' }}</td>
            <td>{{ entry.quantity }}</td>
            <td>{{ entry.employee_name || 'Employee' }}</td>
            <td>{{ formatPeso(entry.total_amount) }}</td>
            <td>{{ new Date(entry.created_at).toLocaleString() }}</td>
          </tr>
        </tbody>
      </table>
    </section>
  </div>

  <div v-else class="sales-page employee-sales">
    <div v-if="successMessage" class="success-toast" role="status">{{ successMessage }}</div>
    <header class="topbar">
      <div>
        <p class="eyebrow">Employee</p>
        <h1>New sale</h1>
      </div>
      <button class="primary-btn" type="button" @click="showConfirm = true" :disabled="!cart.length || isSaving">Complete sale</button>
    </header>

    <section class="sale-layout">
      <div class="panel catalog-panel">
        <div class="catalog-header">
          <div>
            <p class="eyebrow">Products</p>
            <h2>Catalog</h2>
          </div>
          <input v-model="search" type="search" placeholder="Search products" />
        </div>

        <div class="product-list">
          <button v-for="product in filteredProducts" :key="product.id" type="button" class="product-item" @click="addToCart(product)">
            <div class="thumb" v-if="product.image">
              <img :src="product.image" :alt="product.name" />
            </div>
            <div class="thumb fallback" v-else>{{ product.name.charAt(0) }}</div>

            <div class="product-copy">
              <div class="product-line">
                <h3>{{ product.name }}</h3>
                <span class="stock-pill">{{ product.stock }} left</span>
              </div>
              <p>{{ product.flavor || 'No flavor' }} · {{ product.category }}</p>
              <strong>{{ formatPeso(product.price) }}</strong>
            </div>
          </button>
        </div>
      </div>

      <aside class="panel cart-panel">
        <div class="cart-header">
          <div>
            <p class="eyebrow">Current sale</p>
            <h2>My sale</h2>
          </div>
        </div>

        <div v-if="!cart.length" class="empty-state">Select a product to add it to the sale.</div>

        <div v-else class="cart-lines">
          <div v-for="item in cart" :key="item.id" class="cart-line">
            <div>
              <h3>{{ item.name }}</h3>
              <span>{{ item.flavor || 'No flavor' }}</span>
            </div>

            <div class="line-controls">
              <button type="button" @click="adjustQty(item.id, item.qty - 1)">−</button>
              <strong>{{ item.qty }}</strong>
              <button type="button" @click="adjustQty(item.id, item.qty + 1)">+</button>
            </div>

            <strong>{{ formatPeso(item.price * item.qty) }}</strong>
          </div>
        </div>

        <div class="totals">
          <div>
            <span>Items</span>
            <strong>{{ totalItems }}</strong>
          </div>
          <div>
            <span>Total</span>
            <strong>{{ formatPeso(subtotal) }}</strong>
          </div>
        </div>

        <p v-if="confirmMessage" class="confirm-message" role="status">{{ confirmMessage }}</p>
      </aside>
    </section>

    <div v-if="showConfirm" class="confirm-overlay" role="presentation" @click.self="showConfirm = false">
      <section class="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="confirm-sale-title">
        <p class="eyebrow">Review sale</p>
        <h2 id="confirm-sale-title">Confirm sold products</h2>
        <p class="confirm-copy">Double-check the products and quantities before posting this sale.</p>

        <div class="confirm-items">
          <div v-for="item in cart" :key="item.id" class="confirm-item">
            <div>
              <strong>{{ item.name }}</strong>
              <span>{{ item.flavor || 'No flavor' }}</span>
            </div>
            <div class="confirm-item-meta">
              <span>×{{ item.qty }}</span>
              <strong>{{ formatPeso(item.price * item.qty) }}</strong>
            </div>
          </div>
        </div>

        <div class="confirm-total">
          <span>Total</span>
          <strong>{{ formatPeso(subtotal) }}</strong>
        </div>

        <div class="confirm-actions">
          <button class="secondary-btn" type="button" @click="showConfirm = false">Go back</button>
          <button class="primary-btn" type="button" @click="completeSale" :disabled="isSaving">
            {{ isSaving ? 'Saving...' : 'Confirm sold' }}
          </button>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.page-shell,
.sales-page {
  padding: 26px;
}

.topbar,
.panel-header,
.cart-header,
.catalog-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
}

.topbar {
  margin-bottom: 24px;
}

h1,
h2,
h3,
strong,
p {
  margin: 0;
}

.eyebrow {
  margin: 0 0 6px;
  color: #666666;
  font-size: 11px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.primary-btn,
.panel-header button,
.line-controls button {
  border: none;
  border-radius: 12px;
  padding: 10px 14px;
  cursor: pointer;
  font-weight: 600;
}

.primary-btn {
  background: #111111;
  color: #ffffff;
}

.primary-btn:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.stats-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(160px, 1fr));
  gap: 18px;
  margin-bottom: 22px;
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
  display: flex;
  flex-direction: column;
  gap: 12px;
  color: #494949;
}

.stat-card strong {
  font-size: 28px;
  color: #111111;
}

.sales-panel,
.catalog-panel,
.cart-panel {
  padding: 18px 20px;
}

.trend-panel {
  padding: 18px 20px;
  margin-bottom: 18px;
}

.trend-panel .panel-header {
  margin-bottom: 14px;
}

.trend-tabs {
  display: inline-flex;
  gap: 3px;
  padding: 3px;
  border-radius: 9px;
  background: #f2f2f2;
}

.trend-tabs button {
  padding: 6px 10px;
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

.trend-filter {
  display: flex;
  justify-content: flex-end;
  margin: 0 0 12px;
}

.trend-filter label {
  display: flex;
  align-items: center;
  gap: 8px;
  color: #666666;
  font-size: 12px;
  font-weight: 600;
}

.trend-filter input,
.trend-filter select {
  min-width: 150px;
  border: 1px solid rgba(17, 17, 17, 0.1);
  border-radius: 9px;
  padding: 8px 10px;
  background: #fafafa;
  color: #111111;
}

.trend-summary {
  display: flex;
  align-items: baseline;
  gap: 8px;
  margin-bottom: 8px;
}

.trend-summary strong {
  color: #111111;
  font-size: 24px;
  letter-spacing: -0.03em;
}

.trend-summary span {
  color: #777777;
  font-size: 12px;
}

.trend-chart {
  height: 220px;
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
  display: none;
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
  cursor: pointer;
}

.trend-chart circle:focus,
.trend-chart circle:hover {
  fill: #111111;
  outline: none;
}

.trend-chart .trend-hit-area {
  fill: transparent;
  stroke: transparent;
  cursor: pointer;
}

.trend-chart .trend-hit-area:hover,
.trend-chart .trend-hit-area:focus {
  fill: rgba(17, 17, 17, 0.08);
}

.trend-callout {
  pointer-events: none;
}

.trend-callout text {
  fill: #111111;
  font-size: 11px;
  font-weight: 700;
}

.chart-labels {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(0, 1fr));
  gap: 2px;
  margin-top: 4px;
  color: #666666;
  font-size: 10px;
  text-align: center;
  white-space: nowrap;
}

.hide-small-label {
  visibility: hidden;
}

.sales-panel table,
.catalog-panel table {
  width: 100%;
  border-collapse: collapse;
  margin-top: 18px;
}

.employee-filter {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: #666666;
  font-size: 12px;
  font-weight: 600;
}

.employee-filter select {
  min-width: 150px;
  border: 1px solid rgba(17, 17, 17, 0.1);
  border-radius: 9px;
  padding: 8px 10px;
  background: #fafafa;
  color: #111111;
}

th,
td {
  padding: 12px 10px;
  border-bottom: 1px solid rgba(17, 17, 17, 0.08);
  text-align: left;
}

th {
  color: #111111;
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.sale-layout {
  display: grid;
  grid-template-columns: 1.5fr 0.9fr;
  gap: 18px;
}

.catalog-header input {
  width: min(220px, 100%);
  border: 1px solid rgba(17, 17, 17, 0.1);
  border-radius: 12px;
  padding: 10px 12px;
  background: #fafafa;
}

.product-list {
  display: grid;
  gap: 12px;
  margin-top: 20px;
}

.product-item {
  border: 1px solid rgba(17, 17, 17, 0.08);
  background: #fafafa;
  border-radius: 16px;
  display: flex;
  align-items: center;
  padding: 12px;
  gap: 12px;
  text-align: left;
  cursor: pointer;
}

.thumb {
  width: 58px;
  height: 58px;
  overflow: hidden;
  border-radius: 12px;
  display: grid;
  place-items: center;
  background: #111111;
  color: #ffffff;
  font-weight: 700;
}

.thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.fallback {
  font-size: 22px;
}

.product-copy {
  flex: 1;
}

.product-line {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
}

.product-copy p {
  margin: 6px 0 8px;
  color: #666666;
}

.stock-pill {
  background: #f0f0f0;
  color: #111111;
  border-radius: 999px;
  padding: 6px 9px;
  font-size: 11px;
  font-weight: 700;
}

.empty-state {
  color: #666666;
  margin-top: 18px;
}

.cart-lines {
  display: grid;
  gap: 12px;
  margin-top: 18px;
}

.cart-line {
  display: grid;
  grid-template-columns: minmax(0, 1.5fr) auto auto;
  gap: 12px;
  align-items: center;
  padding: 12px 0;
  border-bottom: 1px solid rgba(17, 17, 17, 0.08);
}

.cart-line h3 {
  margin-bottom: 4px;
}

.cart-line span {
  color: #666666;
  font-size: 12px;
}

.line-controls {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 4px 8px;
  border: 1px solid rgba(17, 17, 17, 0.08);
  border-radius: 12px;
}

.line-controls button {
  background: #111111;
  color: #ffffff;
  padding: 6px 10px;
}

.totals {
  display: grid;
  gap: 12px;
  margin-top: 18px;
}

.totals div {
  display: flex;
  justify-content: space-between;
  align-items: center;
  color: #666666;
}

.confirm-message {
  margin-top: 16px;
  color: #1a6a42;
  font-weight: 600;
}

.success-toast {
  position: fixed;
  top: 24px;
  right: 24px;
  z-index: 20;
  padding: 12px 16px;
  border: 1px solid rgba(26, 106, 66, 0.18);
  border-radius: 10px;
  background: #f0faf4;
  color: #1a6a42;
  box-shadow: 0 10px 26px rgba(17, 17, 17, 0.12);
  font-weight: 700;
}

.confirm-overlay {
  position: fixed;
  inset: 0;
  z-index: 10;
  display: grid;
  place-items: center;
  padding: 20px;
  background: rgba(17, 17, 17, 0.35);
}

.confirm-modal {
  width: min(480px, 100%);
  padding: 24px;
  border: 1px solid rgba(17, 17, 17, 0.08);
  border-radius: 16px;
  background: #ffffff;
  box-shadow: 0 18px 50px rgba(17, 17, 17, 0.18);
}

.confirm-modal h2 {
  margin: 0;
  font-size: 22px;
}

.confirm-copy {
  margin-top: 8px;
  color: #666666;
  font-size: 13px;
}

.confirm-items {
  display: grid;
  gap: 8px;
  max-height: 260px;
  margin-top: 20px;
  overflow-y: auto;
}

.confirm-item,
.confirm-total {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.confirm-item {
  padding: 10px 12px;
  border-radius: 10px;
  background: #fafafa;
}

.confirm-item > div:first-child {
  display: grid;
  gap: 3px;
}

.confirm-item span,
.confirm-item-meta span {
  color: #666666;
  font-size: 12px;
}

.confirm-item-meta {
  display: flex;
  align-items: center;
  gap: 12px;
  white-space: nowrap;
}

.confirm-total {
  margin-top: 16px;
  padding-top: 14px;
  border-top: 1px solid rgba(17, 17, 17, 0.08);
}

.confirm-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 20px;
}

.secondary-btn {
  border: 1px solid rgba(17, 17, 17, 0.12);
  border-radius: 12px;
  padding: 10px 14px;
  background: #ffffff;
  color: #111111;
  cursor: pointer;
  font-weight: 600;
}

@media (max-width: 900px) {
  .sale-layout,
  .stats-grid {
    grid-template-columns: 1fr;
  }

  .topbar,
  .panel-header,
  .cart-header,
  .catalog-header {
    align-items: flex-start;
    flex-direction: column;
  }

  .employee-filter {
    width: 100%;
    justify-content: space-between;
  }

  .trend-tabs {
    width: 100%;
  }

  .trend-tabs button {
    flex: 1;
  }

  .trend-filter {
    justify-content: flex-start;
  }

  .trend-filter label {
    align-items: flex-start;
    flex-direction: column;
  }

  .confirm-actions {
    flex-direction: column-reverse;
  }

  .confirm-actions button {
    width: 100%;
  }

  .success-toast {
    top: 16px;
    right: 16px;
    left: 16px;
    text-align: center;
  }

}
</style>
