<script setup>
import { createClient } from '@supabase/supabase-js'

const { $auth } = useNuxtApp()
const runtimeConfig = useRuntimeConfig()
const defaultImage = ''

const products = ref([])
const isOwner = computed(() => $auth?.profile.value?.role === 'owner')
const showProductForm = ref(false)

const supabase = computed(() => {
  const url = runtimeConfig.public.supabaseUrl
  const key = runtimeConfig.public.supabaseAnonKey

  if (!url || !key) return null

  return createClient(url, key)
})

const form = ref({
  id: null,
  image: '',
  name: '',
  flavor: '',
  category: '',
  price: '',
  stock: '',
})

const isEditing = ref(false)

const categoryOptions = ['E-liquid', 'Disposable', 'Device', 'Pod', 'Accessories']
const maxImageSize = 5 * 1024 * 1024

const fileName = ref('No file chosen')
const fileError = ref('')

const formatPeso = (value) =>
  new Intl.NumberFormat('en-PH', {
    style: 'currency',
    currency: 'PHP',
    maximumFractionDigits: 0,
  }).format(value)

const statusClass = (status) => {
  if (status === 'Low Stock') return 'warning'
  if (status === 'Out of Stock') return 'danger'
  return 'success'
}

const resetForm = () => {
  isEditing.value = false
  showProductForm.value = false
  form.value = {
    id: null,
    image: '',
    name: '',
    flavor: '',
    category: '',
    price: '',
    stock: '',
  }
  fileName.value = 'No file chosen'
  fileError.value = ''
}

const handleFileChange = (event) => {
  const file = event.target.files?.[0]
  if (!file) return

  if (file.size > maxImageSize) {
    form.value.image = ''
    fileName.value = 'No file chosen'
    fileError.value = 'Image must be 5 MB or smaller.'
    event.target.value = ''
    return
  }

  fileName.value = file.name
  fileError.value = ''

  const reader = new FileReader()
  reader.onload = () => {
    form.value.image = reader.result
  }
  reader.readAsDataURL(file)
}

const getDerivedStatus = (stock) => {
  const qty = Number(stock) || 0
  if (qty <= 0) return 'Out of Stock'
  if (qty <= 10) return 'Low Stock'
  return 'Active'
}

const fetchProducts = async () => {
  if (!supabase.value) return

  const { data, error } = await supabase.value.from('products').select('*').order('created_at', { ascending: false })

  if (!error && data) {
    products.value = data.map((item) => ({
      id: item.id,
      image: item.image || defaultImage,
      name: item.name,
      flavor: item.flavor || '',
      category: item.category,
      price: Number(item.price) || 0,
      stock: Number(item.stock) || 0,
      status: item.status || getDerivedStatus(item.stock),
    }))
  }
}

const saveProduct = async () => {
  if (fileError.value) return

  const payload = {
    image: form.value.image || defaultImage,
    name: form.value.name.trim(),
    flavor: form.value.flavor.trim(),
    category: form.value.category.trim(),
    price: Number(form.value.price) || 0,
    stock: Number(form.value.stock) || 0,
    status: getDerivedStatus(form.value.stock),
  }

  if (!payload.name || !payload.category) return

  if (supabase.value) {
    if (isEditing.value && form.value.id !== null) {
      const { error } = await supabase.value
        .from('products')
        .update({
          ...payload,
          updated_at: new Date().toISOString(),
        })
        .eq('id', form.value.id)

      if (!error) await fetchProducts()
    } else {
      const { error } = await supabase.value.from('products').insert([
        {
          ...payload,
          created_at: new Date().toISOString(),
        },
      ])

      if (!error) await fetchProducts()
    }
  }

  resetForm()
}

const editProduct = (product) => {
  isEditing.value = true
  showProductForm.value = true
  form.value = { ...product, flavor: product.flavor || '' }
}

const deleteProduct = async (id) => {
  if (supabase.value) {
    await supabase.value.from('products').delete().eq('id', id)
    await fetchProducts()
  }

  if (isEditing.value && form.value.id === id) {
    resetForm()
  }
}

onMounted(async () => {
  if (!isOwner.value) {
    await navigateTo('/sales')
    return
  }

  await fetchProducts()
})
</script>

<template>
  <div v-if="isOwner" class="products-page">
    <main class="content-area">
      <div v-if="showProductForm" class="form-overlay" @click.self="resetForm">
        <aside class="panel form-panel">
          <button class="close-form" type="button" aria-label="Close product form" @click="resetForm">×</button>
        <div class="page-header">
          <div>
            <p class="eyebrow">Inventory</p>
            <h1>Products</h1>
          </div>
          <NuxtLink to="/dashboard" class="back-link">Overview</NuxtLink>
        </div>

        <div class="form-box">
          <h3>{{ isEditing ? 'Edit Product' : 'Add Product' }}</h3>

        <label class="file-upload">
          <span>Product image</span>
          <input type="file" accept="image/*" @change="handleFileChange" />
          <small>{{ fileName }}</small>
          <small v-if="fileError" class="file-error">{{ fileError }}</small>
        </label>

        <label>
          <span>Product name</span>
          <input v-model="form.name" type="text" placeholder="e.g. Blueberry Burst" />
        </label>

        <label>
          <span>Flavor</span>
          <input v-model="form.flavor" type="text" placeholder="e.g. Blueberry, Mint, Tobacco" />
        </label>

        <label>
          <span>Category</span>
          <select v-model="form.category">
            <option value="">Select category</option>
            <option v-for="option in categoryOptions" :key="option" :value="option">
              {{ option }}
            </option>
          </select>
        </label>

        <div class="two-column">
          <label>
            <span>Price</span>
            <input v-model="form.price" type="number" min="0" placeholder="420" />
          </label>

          <label>
            <span>Stock</span>
            <input v-model="form.stock" type="number" min="0" placeholder="25" />
          </label>
        </div>

          <div class="form-actions">
            <button class="secondary-btn" type="button" @click="resetForm">Clear</button>
            <button class="primary-btn" type="button" @click="saveProduct">
              {{ isEditing ? 'Save changes' : 'Add product' }}
            </button>
          </div>
        </div>
        </aside>
      </div>

      <section class="panel list-panel">
        <div class="toolbar">
          <div>
            <p class="eyebrow">Catalog</p>
            <h2>Inventory Items</h2>
          </div>
          <button class="primary-btn" type="button" @click="showProductForm = true; isEditing = false">+ Product</button>
        </div>

        <div class="product-grid">
          <article v-for="product in products" :key="product.id" class="product-card">
            <img :src="product.image" :alt="product.name" />

            <div class="card-body">
              <div class="row top-row">
                <h3>{{ product.name }}</h3>
                <span :class="['status-badge', statusClass(product.status)]">{{ product.status }}</span>
              </div>

              <p class="category">{{ product.flavor }} · {{ product.category }}</p>

              <div class="stats-row">
                <div>
                  <span class="label">Price</span>
                  <strong>{{ formatPeso(product.price) }}</strong>
                </div>
                <div>
                  <span class="label">Stock</span>
                  <strong>{{ product.stock }}</strong>
                </div>
              </div>
            </div>

            <div class="card-actions">
              <button class="ghost-btn" type="button" @click="editProduct(product)">Edit</button>
              <button class="danger-btn" type="button" @click="deleteProduct(product.id)">Delete</button>
            </div>
          </article>
        </div>
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

button,
input,
select {
  font: inherit;
}

.products-page {
  min-height: 100vh;
  display: flex;
  background: #f5f5f5;
}

.content-area {
  flex: 1;
  display: grid;
  grid-template-columns: 1fr;
  gap: 22px;
  padding: 26px;
}

.form-overlay {
  position: fixed;
  inset: 0;
  z-index: 20;
  display: grid;
  place-items: center;
  padding: 20px;
  background: rgba(17, 17, 17, 0.35);
}

.panel {
  background: #ffffff;
  border: 1px solid rgba(17, 17, 17, 0.06);
  border-radius: 20px;
  box-shadow: 0 8px 22px rgba(17, 17, 17, 0.04);
}

.form-panel {
  position: relative;
  width: min(420px, 100%);
  max-height: calc(100vh - 40px);
  overflow-y: auto;
  scrollbar-width: thin;
  scrollbar-color: #9a9a9a transparent;
  padding: 22px;
}

.form-panel::-webkit-scrollbar {
  width: 7px;
}

.form-panel::-webkit-scrollbar-track {
  background: transparent;
}

.form-panel::-webkit-scrollbar-thumb {
  border: 2px solid #ffffff;
  border-radius: 999px;
  background: #9a9a9a;
}

.form-panel::-webkit-scrollbar-thumb:hover {
  background: #666666;
}

.close-form {
  position: absolute;
  top: 14px;
  right: 14px;
  width: 32px;
  height: 32px;
  border: 0;
  border-radius: 50%;
  background: #f2f2f2;
  color: #111111;
  cursor: pointer;
  font-size: 22px;
  line-height: 1;
}

.list-panel {
  padding: 22px;
}

.page-header,
.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  margin-bottom: 24px;
}

.eyebrow {
  margin: 0 0 4px;
  color: #666666;
  font-size: 11px;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

h1,
h2,
h3,
p {
  margin: 0;
}

.back-link {
  color: #111111;
  text-decoration: none;
  font-weight: 600;
}

.file-error {
  color: #b42323;
  font-weight: 600;
}

.form-box {
  display: grid;
  gap: 16px;
}

.form-box h3 {
  font-size: 24px;
}

label {
  display: grid;
  gap: 8px;
  font-size: 13px;
  color: #3c3c3c;
}

input,
select {
  width: 100%;
  border: 1px solid rgba(17, 17, 17, 0.1);
  background: #fafafa;
  border-radius: 12px;
  padding: 12px 14px;
  color: #111111;
}

.file-upload input {
  padding: 10px;
  background: #f2f2f2;
}

.file-upload small {
  color: #666666;
}

input:focus,
select:focus {
  outline: 2px solid rgba(17, 17, 17, 0.12);
  border-color: rgba(17, 17, 17, 0.3);
}

.two-column {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.form-actions {
  display: flex;
  gap: 10px;
  margin-top: 8px;
}

.primary-btn,
.secondary-btn,
.ghost-btn,
.danger-btn {
  border: none;
  border-radius: 12px;
  padding: 11px 15px;
  cursor: pointer;
  transition: 0.2s ease;
}

.primary-btn {
  background: #111111;
  color: #ffffff;
  font-weight: 600;
}

.secondary-btn {
  background: #f2f2f2;
  color: #111111;
}

.ghost-btn {
  background: #f5f5f5;
  color: #111111;
}

.danger-btn {
  background: #111111;
  color: #ffffff;
}

.product-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 18px;
}

.product-card {
  border: 1px solid rgba(17, 17, 17, 0.08);
  background: #fafafa;
  border-radius: 18px;
  overflow: hidden;
}

.product-card img {
  display: block;
  width: 100%;
  height: 180px;
  object-fit: cover;
  background: #e5e5e5;
}

.card-body {
  padding: 16px 16px 12px;
}

.top-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 10px;
}

.top-row h3 {
  font-size: 18px;
}

.category {
  margin-top: 8px;
  color: #666666;
  font-size: 13px;
}

.stats-row {
  margin-top: 16px;
  display: flex;
  justify-content: space-between;
  gap: 12px;
}

.label {
  display: block;
  color: #666666;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  margin-bottom: 4px;
}

.stats-row strong {
  font-size: 18px;
}

.status-badge {
  display: inline-flex;
  align-items: center;
  padding: 6px 10px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
}

.status-badge.success {
  background: rgba(17, 17, 17, 0.08);
  color: #111111;
}

.status-badge.warning {
  background: rgba(217, 52, 52, 0.1);
  color: #b42323;
}

.status-badge .stock-alert-dot {
  width: 7px;
  height: 7px;
  flex: 0 0 7px;
  margin-right: 6px;
  border-radius: 50%;
  background: #d93434;
  box-shadow: 0 0 0 3px rgba(217, 52, 52, 0.14);
}

.status-badge.danger {
  background: rgba(17, 17, 17, 0.12);
  color: #111111;
}

.card-actions {
  display: flex;
  gap: 8px;
  padding: 0 16px 16px;
}

.card-actions button {
  flex: 1;
}

@media (max-width: 900px) {
  .products-page {
    flex-direction: column;
  }

  .content-area {
    grid-template-columns: 1fr;
  }
}
</style>
