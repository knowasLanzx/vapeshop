<script setup>
const { $supabase, $auth } = useNuxtApp()
const transactions = ref([])
const replacements = ref([])
const isEmployee = computed(() => $auth?.profile.value?.role === 'employee')
const shopDateFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Manila',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
})
const todayInShop = () => shopDateFormatter.format(new Date())
const currentShopDay = ref(todayInShop())
const selectedHistoryDate = ref(todayInShop())
let dayRefreshInterval

const activities = computed(() => [
  ...transactions.value
    .filter((entry) => entry.sale_type !== 'replacement_charge' && shopDateFormatter.format(new Date(entry.created_at)) === selectedHistoryDate.value)
    .map((entry) => ({ ...entry, activityType: 'sale' })),
  ...replacements.value
    .filter((entry) => shopDateFormatter.format(new Date(entry.created_at)) === selectedHistoryDate.value)
    .map((entry) => ({ ...entry, activityType: 'replacement' })),
].sort((a, b) => new Date(b.created_at) - new Date(a.created_at)))

const todaySalesTotal = computed(() => transactions.value
  .filter((entry) => shopDateFormatter.format(new Date(entry.created_at)) === currentShopDay.value)
  .reduce((sum, entry) => sum + Number(entry.total_amount || 0), 0))

const formatPeso = (value) =>
  new Intl.NumberFormat('en-PH', {
    style: 'currency',
    currency: 'PHP',
    maximumFractionDigits: 0,
  }).format(Number(value) || 0)

const fetchMySales = async () => {
  if (!$supabase || !$auth?.user.value) return

  const [salesResult, replacementsResult] = await Promise.all([
    $supabase
      .from('sales')
      .select('*')
      .eq('employee_id', $auth.user.value.id)
      .order('created_at', { ascending: false }),
    $supabase
      .from('inventory_adjustments')
      .select('id, product_name, quantity, reason, additional_amount, payment_method, created_at')
      .eq('employee_id', $auth.user.value.id)
      .not('sale_id', 'is', null)
      .order('created_at', { ascending: false }),
  ])

  if (!salesResult.error && salesResult.data) transactions.value = salesResult.data
  if (!replacementsResult.error && replacementsResult.data) replacements.value = replacementsResult.data
}

onMounted(async () => {
  dayRefreshInterval = setInterval(() => {
    const today = todayInShop()
    if (currentShopDay.value !== today) {
      currentShopDay.value = today
      selectedHistoryDate.value = today
    }
  }, 60_000)

  if (!isEmployee.value) {
    await navigateTo('/dashboard')
    return
  }

  await fetchMySales()
})

onUnmounted(() => clearInterval(dayRefreshInterval))
</script>

<template>
  <div v-if="isEmployee" class="my-sales-page">
    <header class="topbar">
      <div>
        <p class="eyebrow">Employee</p>
        <h1>My Sale</h1>
      </div>
      <NuxtLink to="/sales" class="primary-btn">New sale</NuxtLink>
    </header>

    <section class="panel">
      <div class="daily-total">
        <div>
          <p class="eyebrow">Today's sales · {{ currentShopDay }}</p>
          <h2>{{ formatPeso(todaySalesTotal) }}</h2>
        </div>
        <span>Resets each day</span>
      </div>

      <div class="panel-header">
        <div>
          <h2>My sale history</h2>
          <p class="muted">Sales and replacements by {{ $auth?.profile.value?.display_name || 'you' }}</p>
        </div>
        <div class="history-controls">
          <label for="my-history-date">History date</label>
          <input id="my-history-date" v-model="selectedHistoryDate" type="date" />
          <button type="button" class="today-btn" @click="selectedHistoryDate = currentShopDay">Today</button>
          <strong>{{ activities.length }} entr{{ activities.length === 1 ? 'y' : 'ies' }}</strong>
        </div>
      </div>

      <div v-if="!activities.length" class="empty-state">No sales or replacements for {{ selectedHistoryDate }}.</div>

      <div v-else class="sale-list">
        <article v-for="sale in activities" :key="`${sale.activityType}-${sale.id}`" class="sale-item">
          <div>
            <h3>{{ sale.product_name }}</h3>
            <p v-if="sale.activityType === 'replacement'">{{ sale.quantity }} replaced · {{ sale.reason }}</p>
            <p v-else>{{ sale.flavor || 'No flavor' }} · {{ sale.category || 'Product' }}</p>
          </div>
          <div class="sale-meta">
            <span>{{ sale.quantity }} {{ sale.activityType === 'replacement' ? 'replaced' : 'sold' }}</span>
            <strong v-if="sale.activityType === 'replacement' && Number(sale.additional_amount) > 0">
              +{{ formatPeso(sale.additional_amount) }}
            </strong>
            <strong v-else-if="sale.activityType === 'sale'">{{ formatPeso(sale.total_amount) }}</strong>
            <span v-if="sale.payment_method" class="payment-tag">{{ sale.payment_method === 'gcash' ? 'GCash' : 'Cash' }}</span>
            <small>{{ new Date(sale.created_at).toLocaleString() }}</small>
          </div>
        </article>
      </div>
    </section>
  </div>
</template>

<style scoped>
.my-sales-page {
  padding: 26px;
}

.topbar,
.panel-header,
.sale-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.topbar {
  margin-bottom: 24px;
}

h1,
h2,
h3,
p {
  margin: 0;
}

.eyebrow {
  margin-bottom: 6px;
  color: #666666;
  font-size: 11px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.primary-btn {
  padding: 10px 14px;
  border-radius: 12px;
  background: #111111;
  color: #ffffff;
  font-weight: 600;
  text-decoration: none;
}

.panel {
  padding: 20px;
  border: 1px solid rgba(17, 17, 17, 0.06);
  border-radius: 18px;
  background: #ffffff;
  box-shadow: 0 8px 22px rgba(17, 17, 17, 0.04);
}

.panel-header {
  margin-bottom: 18px;
}

.history-controls {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 9px;
  color: #666666;
  font-size: 12px;
}

.history-controls input {
  border: 1px solid rgba(17, 17, 17, 0.12);
  border-radius: 9px;
  padding: 8px 10px;
  background: #fafafa;
  color: #111111;
  font: inherit;
}

.history-controls strong {
  color: #111111;
}

.today-btn {
  border: 1px solid rgba(17, 17, 17, 0.12);
  border-radius: 9px;
  padding: 8px 10px;
  background: #ffffff;
  color: #111111;
  cursor: pointer;
  font: inherit;
  font-weight: 600;
}

.daily-total {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  margin-bottom: 24px;
  padding: 18px;
  border-radius: 14px;
  background: #f5f5f5;
}

.daily-total h2 {
  margin-top: 4px;
  font-size: 26px;
}

.daily-total > span,
.payment-tag {
  color: #666666;
  font-size: 12px;
}

.panel-header h2 {
  font-size: 18px;
}

.muted,
.sale-item p,
.sale-meta,
.empty-state {
  color: #666666;
  font-size: 12px;
}

.muted {
  margin-top: 5px;
}

.sale-list {
  display: grid;
  gap: 10px;
}

.sale-item {
  padding: 14px;
  border: 1px solid rgba(17, 17, 17, 0.06);
  border-radius: 12px;
  background: #fafafa;
}

.sale-item h3 {
  font-size: 15px;
}

.sale-item p {
  margin-top: 5px;
}

.sale-meta {
  display: flex;
  align-items: flex-end;
  gap: 12px;
  text-align: right;
}

.sale-meta strong {
  color: #111111;
}

.sale-meta small {
  white-space: nowrap;
}

@media (max-width: 700px) {
  .topbar,
  .panel-header,
  .sale-item {
    align-items: flex-start;
    flex-direction: column;
  }

  .history-controls {
    width: 100%;
  }

  .sale-meta {
    width: 100%;
    align-items: flex-start;
    flex-wrap: wrap;
    text-align: left;
  }

  .daily-total {
    align-items: flex-start;
    flex-direction: column;
  }
}
</style>
