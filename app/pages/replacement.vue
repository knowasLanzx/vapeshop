<script setup>
const { $supabase, $auth } = useNuxtApp()
const replacementSources = ref([])
const products = ref([])
const selectedSourceKey = ref('')
const selectedProductId = ref('')
const quantity = ref(1)
const paymentMethod = ref('')
const reason = ref('Defective product')
const message = ref('')
const successMessage = ref('')
const isSaving = ref(false)
const showConfirm = ref(false)
let successTimeout

const isEmployee = computed(() => $auth?.profile.value?.role === 'employee')
const reasons = ['Defective product', 'Damaged product', 'Wrong product', 'Customer replacement']
const selectedSource = computed(() => replacementSources.value.find((source) => source.key === selectedSourceKey.value))
const selectedProduct = computed(() => products.value.find((product) => String(product.id) === String(selectedProductId.value)))
const maximumQuantity = computed(() => Math.min(Number(selectedSource.value?.remaining_quantity) || 0, Number(selectedProduct.value?.stock) || 0))
const originalUnitPrice = computed(() => {
  return Number(selectedSource.value?.unit_price) || 0
})
const additionalAmount = computed(() => {
  if (!selectedProduct.value) return 0
  return Math.max(0, Number(selectedProduct.value.price) - originalUnitPrice.value) * Number(quantity.value || 0)
})

const formatPeso = (value) => new Intl.NumberFormat('en-PH', {
  style: 'currency',
  currency: 'PHP',
  maximumFractionDigits: 2,
}).format(Number(value) || 0)

const fetchReplacementOptions = async () => {
  if (!$supabase) return

  const [salesResult, adjustmentsResult, productsResult] = await Promise.all([
    $supabase
      .from('sales')
      .select('id, product_id, product_name, flavor, category, quantity, total_amount, created_at, sale_type')
      .eq('sale_type', 'sale')
      .gt('quantity', 0)
      .order('created_at', { ascending: false }),
    $supabase.from('inventory_adjustments')
      .select('id, sale_id, source_adjustment_id, product_id, product_name, quantity, replacement_unit_price, created_at')
      .not('sale_id', 'is', null),
    $supabase.from('products').select('id, name, flavor, category, price, stock').gt('stock', 0).order('name'),
  ])

  const error = salesResult.error || adjustmentsResult.error || productsResult.error
  if (error) {
    message.value = error.message
    return
  }

  const adjustments = adjustmentsResult.data || []
  const replacedSoldQuantities = adjustments.reduce((totals, adjustment) => {
    if (adjustment.source_adjustment_id === null) {
      totals[adjustment.sale_id] = (totals[adjustment.sale_id] || 0) + Number(adjustment.quantity || 0)
    }
    return totals
  }, {})
  const replacedReplacementQuantities = adjustments.reduce((totals, adjustment) => {
    if (adjustment.source_adjustment_id !== null) {
      totals[adjustment.source_adjustment_id] = (totals[adjustment.source_adjustment_id] || 0) + Number(adjustment.quantity || 0)
    }
    return totals
  }, {})

  replacementSources.value = [
    ...(salesResult.data || []).map((sale) => ({
      key: `sale:${sale.id}`,
      source_type: 'sale',
      id: sale.id,
      sale_id: sale.id,
      product_id: sale.product_id,
      product_name: sale.product_name,
      flavor: sale.flavor,
      unit_price: Number(sale.quantity) ? Number(sale.total_amount || 0) / Number(sale.quantity) : 0,
      remaining_quantity: Number(sale.quantity) - Number(replacedSoldQuantities[sale.id] || 0),
      created_at: sale.created_at,
    })),
    ...adjustments.map((adjustment) => ({
      key: `replacement:${adjustment.id}`,
      source_type: 'replacement',
      id: adjustment.id,
      sale_id: adjustment.sale_id,
      product_id: adjustment.product_id,
      product_name: adjustment.product_name,
      unit_price: Number(adjustment.replacement_unit_price) || 0,
      remaining_quantity: Number(adjustment.quantity) - Number(replacedReplacementQuantities[adjustment.id] || 0),
      created_at: adjustment.created_at,
    })),
  ].filter((source) => source.remaining_quantity > 0)
  products.value = productsResult.data || []
}

const handleSaleChange = () => {
  quantity.value = 1
  paymentMethod.value = ''
  message.value = ''
}

const handleProductChange = () => {
  quantity.value = 1
  paymentMethod.value = ''
  message.value = ''
}

const recordReplacement = async () => {
  if (!$supabase || !selectedSource.value || !selectedProduct.value || isSaving.value) return
  if (Number(quantity.value) < 1 || Number(quantity.value) > maximumQuantity.value) {
    message.value = 'The selected sale or replacement product no longer has enough available quantity.'
    showConfirm.value = false
    await fetchReplacementOptions()
    return
  }

  isSaving.value = true
  message.value = ''

  const { data, error } = await $supabase.rpc('complete_replacement', {
    p_source_type: selectedSource.value.source_type,
    p_source_id: Number(selectedSource.value.id),
    p_replacement_product_id: Number(selectedProduct.value.id),
    p_quantity: Number(quantity.value),
    p_reason: reason.value,
    p_payment_method: additionalAmount.value > 0 ? paymentMethod.value : null,
  })

  if (error) {
    message.value = error.message
    showConfirm.value = false
    isSaving.value = false
    await fetchReplacementOptions()
    return
  }

  const chargedAmount = Number(Array.isArray(data) ? data[0]?.additional_amount : data?.additional_amount) || 0
  successMessage.value = chargedAmount > 0
    ? `Replacement completed. ${formatPeso(chargedAmount)} was added to sales.`
    : 'Replacement completed successfully.'
  showConfirm.value = false
  selectedSourceKey.value = ''
  selectedProductId.value = ''
  quantity.value = 1
  paymentMethod.value = ''
  await fetchReplacementOptions()
  clearTimeout(successTimeout)
  successTimeout = setTimeout(() => {
    successMessage.value = ''
  }, 3000)
  isSaving.value = false
}

onMounted(async () => {
  if (!isEmployee.value) {
    await navigateTo('/dashboard')
    return
  }
  await fetchReplacementOptions()
})

onUnmounted(() => clearTimeout(successTimeout))
</script>

<template>
  <div v-if="isEmployee" class="replacement-page">
    <div v-if="successMessage" class="success-toast" role="status">{{ successMessage }}</div>
    <header class="topbar">
      <div><p class="eyebrow">Employee</p><h1>Product replacement</h1></div>
      <NuxtLink to="/sales" class="secondary-btn">Back to sales</NuxtLink>
    </header>

    <section class="panel">
      <p class="eyebrow">Replacement workflow</p>
      <h2>Replace a defective item</h2>
      <p class="description">Choose whether the defective item came from an original sale or an earlier replacement. Each item unit can be replaced once.</p>

      <form class="replacement-form" @submit.prevent="showConfirm = true">
        <label>
          Item to replace
          <select v-model="selectedSourceKey" required @change="handleSaleChange">
            <option value="">Choose an item</option>
            <optgroup label="Originally sold">
              <option v-for="source in replacementSources.filter((item) => item.source_type === 'sale')" :key="source.key" :value="source.key">
                {{ source.product_name }}{{ source.flavor ? ` · ${source.flavor}` : '' }} — {{ formatPeso(source.unit_price) }} each — {{ source.remaining_quantity }} available — sold {{ new Date(source.created_at).toLocaleDateString() }}
              </option>
            </optgroup>
            <optgroup label="Previously replaced">
              <option v-for="source in replacementSources.filter((item) => item.source_type === 'replacement')" :key="source.key" :value="source.key">
                {{ source.product_name }} — {{ formatPeso(source.unit_price) }} each — {{ source.remaining_quantity }} available — replaced {{ new Date(source.created_at).toLocaleDateString() }}
              </option>
            </optgroup>
          </select>
          <small v-if="!replacementSources.length">No sold or replaced items are available for another replacement.</small>
        </label>

        <div v-if="selectedSource" class="product-preview">
          <span>{{ selectedSource.source_type === 'sale' ? 'Originally sold item' : 'Previously replaced item' }}</span>
          <strong>{{ selectedSource.product_name }} · {{ formatPeso(originalUnitPrice) }} each</strong>
          <span>{{ selectedSource.remaining_quantity }} unit(s) still eligible for replacement</span>
        </div>

        <label>
          Replace with
          <select v-model="selectedProductId" required @change="handleProductChange">
            <option value="">Select an available product</option>
            <option v-for="product in products" :key="product.id" :value="String(product.id)">
              {{ product.name }}{{ product.flavor ? ` · ${product.flavor}` : '' }} — {{ formatPeso(product.price) }} — {{ product.stock }} in stock
            </option>
          </select>
          <small v-if="!products.length">No products are currently in stock.</small>
        </label>

        <label>
          Quantity
          <input v-model.number="quantity" type="number" min="1" step="1" :max="maximumQuantity || 1" required />
        </label>

        <label>
          Reason
          <select v-model="reason" required>
            <option v-for="item in reasons" :key="item" :value="item">{{ item }}</option>
          </select>
        </label>

        <div v-if="selectedSource && selectedProduct" class="price-summary">
          <span>Original item price</span><strong>{{ formatPeso(originalUnitPrice * quantity) }}</strong>
          <span>Replacement item price</span><strong>{{ formatPeso(Number(selectedProduct.price) * quantity) }}</strong>
          <span>Customer add-on</span><strong>{{ formatPeso(additionalAmount) }}</strong>
          <small v-if="Number(selectedProduct.price) < originalUnitPrice" class="full-row">
            The replacement costs less; no refund is calculated by this workflow.
          </small>
        </div>

        <p v-if="message" class="form-message error" role="alert">{{ message }}</p>
        <div class="form-actions">
          <NuxtLink to="/sales" class="secondary-btn">Cancel</NuxtLink>
          <button class="primary-btn" type="submit" :disabled="!selectedSource || !selectedProduct || maximumQuantity < 1 || quantity > maximumQuantity || isSaving">
            Review replacement
          </button>
        </div>
      </form>
    </section>

    <div v-if="showConfirm" class="confirm-overlay" @click.self="showConfirm = false">
      <section class="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="confirm-replacement-title">
        <button class="close-confirm" type="button" aria-label="Close confirmation" @click="showConfirm = false">×</button>
        <p class="eyebrow">Final confirmation</p>
        <h2 id="confirm-replacement-title">Confirm replacement</h2>
        <div class="confirm-summary">
          <span>Item to replace</span><strong>{{ selectedSource?.product_name }}</strong>
          <span>Replacement</span><strong>{{ selectedProduct?.name }}</strong>
          <span>Quantity</span><strong>{{ quantity }}</strong>
          <span>Reason</span><strong>{{ reason }}</strong>
          <span>Customer add-on</span><strong>{{ formatPeso(additionalAmount) }}</strong>
          <span>Payment method</span>
          <template v-if="additionalAmount > 0">
            <select v-model="paymentMethod" class="review-payment-select" required aria-label="Payment method for add-on">
              <option value="">Choose Cash or GCash</option>
              <option value="cash">Cash</option>
              <option value="gcash">GCash</option>
            </select>
          </template>
          <strong v-else>No payment due</strong>
        </div>
        <p class="description">The replacement stock, history, and any additional sales charge will be saved together.</p>
        <div class="confirm-actions">
          <button class="secondary-btn" type="button" @click="showConfirm = false">Go back</button>
          <button class="primary-btn" type="button" :disabled="isSaving || (additionalAmount > 0 && !paymentMethod)" @click="recordReplacement">
            {{ isSaving ? 'Saving...' : 'Confirm replacement' }}
          </button>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.replacement-page { min-height: 100vh; padding: 26px; }
.topbar, .form-actions, .product-preview { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
.topbar { margin-bottom: 24px; }
h1, h2, p { margin: 0; }
.eyebrow { margin-bottom: 6px; color: #666; font-size: 11px; letter-spacing: .12em; text-transform: uppercase; }
.panel { width: min(720px, 100%); padding: 24px; border: 1px solid rgba(17,17,17,.06); border-radius: 18px; background: #fff; box-shadow: 0 8px 22px rgba(17,17,17,.04); }
.description { margin-top: 8px; color: #666; font-size: 13px; line-height: 1.5; }
.replacement-form { display: grid; gap: 16px; margin-top: 24px; }
.replacement-form label { display: grid; gap: 7px; color: #333; font-size: 12px; font-weight: 700; }
.replacement-form input, .replacement-form select { width: 100%; border: 1px solid rgba(17,17,17,.12); border-radius: 9px; padding: 11px 12px; background: #fafafa; color: #111; font: inherit; }
.replacement-form small { color: #777; font-size: 11px; font-weight: 400; }
.product-preview, .price-summary { padding: 14px; border-radius: 10px; background: #fafafa; }
.product-preview { align-items: flex-start; flex-direction: column; }
.product-preview span, .price-summary span { color: #666; font-size: 12px; }
.price-summary { display: grid; grid-template-columns: 1fr auto; gap: 10px; }
.price-summary strong { text-align: right; }
.price-summary .full-row { grid-column: 1 / -1; }
.payment-method-field { display: grid; gap: 7px; color: #333; font-size: 12px; font-weight: 700; }
.payment-method-field select { width: 100%; border: 1px solid rgba(17,17,17,.12); border-radius: 9px; padding: 11px 12px; background: #fafafa; color: #111; font: inherit; }
.review-payment-select { width: 100%; border: 1px solid rgba(17,17,17,.12); border-radius: 9px; padding: 9px 10px; background: #fff; color: #111; font: inherit; }
.primary-btn, .secondary-btn { display: inline-flex; align-items: center; justify-content: center; border-radius: 10px; padding: 10px 14px; cursor: pointer; font: inherit; font-weight: 700; text-decoration: none; }
.primary-btn { border: 0; background: #111; color: #fff; }
.primary-btn:disabled { cursor: not-allowed; opacity: .5; }
.secondary-btn { border: 1px solid rgba(17,17,17,.12); background: #fff; color: #111; }
.form-message { font-size: 13px; font-weight: 600; }
.form-message.error { color: #a12b2b; }
.form-actions { justify-content: flex-end; }
.success-toast { position: fixed; top: 24px; right: 24px; z-index: 30; max-width: calc(100vw - 48px); padding: 12px 16px; border: 1px solid rgba(26,106,66,.18); border-radius: 10px; background: #f0faf4; color: #1a6a42; box-shadow: 0 10px 26px rgba(17,17,17,.12); font-weight: 700; }
.confirm-overlay { position: fixed; inset: 0; z-index: 20; display: grid; place-items: center; padding: 20px; background: rgba(17,17,17,.35); }
.confirm-modal { position: relative; width: min(460px, 100%); padding: 24px; border-radius: 16px; background: #fff; box-shadow: 0 18px 50px rgba(17,17,17,.18); }
.close-confirm { position: absolute; top: 14px; right: 14px; width: 30px; height: 30px; border: 0; border-radius: 50%; background: #f2f2f2; color: #111; cursor: pointer; font-size: 20px; }
.confirm-summary { display: grid; grid-template-columns: 1fr auto; gap: 10px; margin-top: 20px; padding: 14px; border-radius: 10px; background: #fafafa; }
.confirm-summary span { color: #666; font-size: 12px; }
.confirm-summary strong { text-align: right; }
.confirm-actions { display: flex; justify-content: flex-end; gap: 8px; margin-top: 20px; }
@media (max-width: 700px) { .topbar, .form-actions { align-items: stretch; flex-direction: column; } .form-actions, .form-actions a, .form-actions button { width: 100%; } .success-toast { top: 16px; right: 16px; left: 16px; text-align: center; } }
</style>
