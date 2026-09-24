<script setup>
import { createClient } from '@supabase/supabase-js'

const runtimeConfig = useRuntimeConfig()
const inventory = ref([])
const summary = ref([])
const inventoryQuery = ref('')
const categoryFilter = ref('')
const stockFilter = ref('')

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

const categoryOptions = computed(() => [...new Set(inventory.value.map((item) => item.category))].sort())
const filteredInventory = computed(() => {
  const query = inventoryQuery.value.trim().toLowerCase()

  return inventory.value.filter((item) => {
    const matchesQuery = !query || [item.item, item.flavor].some((field) => (field || '').toLowerCase().includes(query))
    const matchesCategory = !categoryFilter.value || item.category === categoryFilter.value
    const matchesStock = !stockFilter.value || item.status === stockFilter.value
    return matchesQuery && matchesCategory && matchesStock
  })
})

const fetchInventory = async () => {
  if (!supabase.value) return

  const { data, error } = await supabase.value
    .from('products')
    .select('*')
    .order('created_at', { ascending: false })

  if (error) return

  inventory.value = (data || []).map((item) => {
    const stock = Number(item.stock) || 0
    const price = Number(item.price) || 0
    const status = stock <= 0 ? 'Out of Stock' : stock <= 10 ? 'Low Stock' : 'Active'

    return {
      item: item.name,
      flavor: item.flavor || '—',
      category: item.category,
      stock,
      status,
      value: price * stock,
    }
  }).sort((first, second) => {
    const priority = { 'Low Stock': 0, 'Out of Stock': 1, Active: 2 }
    return priority[first.status] - priority[second.status]
  })

  const totalItems = inventory.value.reduce((sum, item) => sum + item.stock, 0)
  const totalValue = inventory.value.reduce((sum, item) => sum + item.value, 0)

  summary.value = [
    { label: 'Items', value: String(inventory.value.length) },
    { label: 'Stock', value: String(totalItems) },
    { label: 'Low Stock', value: String(inventory.value.filter((item) => item.status === 'Low Stock').length) },
    { label: 'Inventory Value', value: formatPeso(totalValue) },
  ]
}

onMounted(async () => {
  await fetchInventory()
})
</script>

<template>
  <div class="page-shell">
    <header class="topbar">
      <div>
        <p class="eyebrow">Inventory</p>
        <h1>Stock Control</h1>
      </div>
      <button class="primary-btn">Restock List</button>
    </header>

    <section class="stats-grid">
      <article v-for="item in summary" :key="item.label" class="stat-card">
        <span>{{ item.label }}</span>
        <strong>{{ item.value }}</strong>
      </article>
    </section>

    <section class="panel">
      <div class="panel-header">
        <h3>Inventory Items</h3>
        <div class="inventory-filters">
          <input v-model="inventoryQuery" type="search" placeholder="Search item or flavor" />
          <select v-model="categoryFilter" aria-label="Filter by category">
            <option value="">All categories</option>
            <option v-for="category in categoryOptions" :key="category" :value="category">{{ category }}</option>
          </select>
          <select v-model="stockFilter" aria-label="Filter by stock status">
            <option value="">All stock</option>
            <option value="Active">In stock</option>
            <option value="Low Stock">Low stock</option>
            <option value="Out of Stock">Out of stock</option>
          </select>
        </div>
      </div>

      <table>
        <thead>
          <tr>
            <th>Item</th>
            <th>Flavor</th>
            <th>Category</th>
            <th>Stock</th>
            <th>Status</th>
            <th>Inventory Value</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in filteredInventory" :key="row.item">
            <td>{{ row.item }}</td>
            <td>{{ row.flavor }}</td>
            <td>{{ row.category }}</td>
            <td>{{ row.stock }}</td>
            <td>
              <span
                :class="[
                  'status',
                  row.status === 'Active' ? 'healthy' : row.status === 'Low Stock' ? 'low' : 'medium'
                ]"
              >
                <span v-if="row.status === 'Low Stock'" class="stock-alert-dot" aria-label="Low stock"></span>
                {{ row.status }}
              </span>
            </td>
            <td>{{ formatPeso(row.value) }}</td>
          </tr>
        </tbody>
      </table>
      <p v-if="!filteredInventory.length" class="empty-state">No inventory items match these filters.</p>
    </section>
  </div>
</template>

<style scoped>
.page-shell {
  padding: 26px;
}

.topbar,
.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
}

.topbar {
  margin-bottom: 24px;
}

h1,
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
.panel-header button {
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

.panel-header button {
  background: #f2f2f2;
  color: #111111;
}

.inventory-filters {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 8px;
}

.inventory-filters input,
.inventory-filters select {
  min-width: 135px;
  border: 1px solid rgba(17, 17, 17, 0.1);
  border-radius: 9px;
  padding: 8px 10px;
  background: #fafafa;
  color: #111111;
  font: inherit;
}

.inventory-filters input {
  min-width: 190px;
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

.panel {
  padding: 18px 20px;
}

table {
  width: 100%;
  border-collapse: collapse;
  margin-top: 16px;
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

.status {
  display: inline-flex;
  padding: 6px 9px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
}

.status.healthy {
  background: rgba(17, 17, 17, 0.08);
  color: #111111;
}

.status.medium {
  background: rgba(17, 17, 17, 0.06);
  color: #333333;
}

.status.low {
  background: rgba(217, 52, 52, 0.1);
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

.empty-state {
  margin: 18px 0 0;
  color: #666666;
  font-size: 13px;
}

@media (max-width: 900px) {
  .stats-grid {
    grid-template-columns: 1fr;
  }

  .topbar,
  .panel-header {
    flex-direction: column;
    align-items: flex-start;
  }

  .inventory-filters {
    width: 100%;
    justify-content: stretch;
  }

  .inventory-filters input,
  .inventory-filters select {
    flex: 1 1 150px;
  }
}
</style>
