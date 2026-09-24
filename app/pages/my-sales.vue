<script setup>
const { $supabase, $auth } = useNuxtApp()
const transactions = ref([])
const isEmployee = computed(() => $auth?.profile.value?.role === 'employee')

const formatPeso = (value) =>
  new Intl.NumberFormat('en-PH', {
    style: 'currency',
    currency: 'PHP',
    maximumFractionDigits: 0,
  }).format(Number(value) || 0)

const fetchMySales = async () => {
  if (!$supabase || !$auth?.user.value) return

  const { data, error } = await $supabase
    .from('sales')
    .select('*')
    .eq('employee_id', $auth.user.value.id)
    .order('created_at', { ascending: false })

  if (!error && data) transactions.value = data
}

onMounted(async () => {
  if (!isEmployee.value) {
    await navigateTo('/dashboard')
    return
  }

  await fetchMySales()
})
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
      <div class="panel-header">
        <div>
          <h2>My sale history</h2>
          <p class="muted">Products sold by {{ $auth?.profile.value?.display_name || 'you' }}</p>
        </div>
        <strong>{{ transactions.length }} sale{{ transactions.length === 1 ? '' : 's' }}</strong>
      </div>

      <div v-if="!transactions.length" class="empty-state">You have not recorded any sales yet.</div>

      <div v-else class="sale-list">
        <article v-for="sale in transactions" :key="sale.id" class="sale-item">
          <div>
            <h3>{{ sale.product_name }}</h3>
            <p>{{ sale.flavor || 'No flavor' }} · {{ sale.category || 'Product' }}</p>
          </div>
          <div class="sale-meta">
            <span>{{ sale.quantity }} sold</span>
            <strong>{{ formatPeso(sale.total_amount) }}</strong>
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

  .sale-meta {
    width: 100%;
    align-items: flex-start;
    flex-wrap: wrap;
    text-align: left;
  }
}
</style>
