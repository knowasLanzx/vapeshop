<script setup>
const { $supabase } = useNuxtApp()
const staff = ref([])
const staffError = ref('')
const editingId = ref(null)
const editForm = ref({ display_name: '', role: 'employee' })
const isSaving = ref(false)
const shopDateFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Manila',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
})
const shopDateTimeFormatter = new Intl.DateTimeFormat('en-PH', {
  timeZone: 'Asia/Manila',
  dateStyle: 'medium',
  timeStyle: 'short',
})
const getShopDate = (dateValue) => shopDateFormatter.format(new Date(dateValue))
const selectedDate = ref(getShopDate(new Date()))

const staffForSelectedDate = computed(() => staff.value.map((member) => {
  const dailySales = member.allSales.filter((sale) => getShopDate(sale.created_at) === selectedDate.value)
  const history = dailySales.filter((sale) => sale.sale_type !== 'replacement_charge')
  const replacementHistory = member.allReplacements.filter((replacement) => getShopDate(replacement.created_at) === selectedDate.value)

  return {
    ...member,
    sales: formatPeso(dailySales.reduce((sum, sale) => sum + Number(sale.total_amount || 0), 0)),
    hours: `${history.length} sale${history.length === 1 ? '' : 's'}`,
    history,
    replacementHistory,
  }
}))

const showToday = () => {
  selectedDate.value = getShopDate(new Date())
}

const formatPeso = (value) =>
  new Intl.NumberFormat('en-PH', {
    style: 'currency',
    currency: 'PHP',
    maximumFractionDigits: 0,
  }).format(Number(value) || 0)

const fetchStaff = async () => {
  if (!$supabase) return

  const [
    { data: profiles, error: profilesError },
    { data: sales, error: salesError },
    { data: replacements, error: replacementsError },
  ] = await Promise.all([
    $supabase.from('profiles').select('id, display_name, email, role').in('role', ['employee', 'pending']).order('created_at', { ascending: false }),
    $supabase.from('sales').select('id, employee_id, employee_name, product_name, quantity, total_amount, sale_type, payment_method, created_at').order('created_at', { ascending: false }),
    $supabase.from('inventory_adjustments').select('id, employee_id, employee_name, product_name, quantity, reason, additional_amount, payment_method, created_at').order('created_at', { ascending: false }),
  ])

  if (profilesError || salesError || replacementsError) {
    staffError.value = profilesError?.message || salesError?.message || replacementsError?.message || 'Unable to load staff data.'
    return
  }

  staffError.value = ''

  staff.value = (profiles || []).map((profile) => {
    const name = profile.display_name || 'Staff member'
    const staffSales = (sales || []).filter((sale) => {
      return sale.employee_id === profile.id || (!sale.employee_id && sale.employee_name === name)
    })
    const replacementHistory = (replacements || []).filter((replacement) => {
      return replacement.employee_id === profile.id || (!replacement.employee_id && replacement.employee_name === name)
    })

    return {
      id: profile.id,
      name,
      email: profile.email || 'Email unavailable',
      role: profile.role || 'employee',
      status: profile.role === 'pending' ? 'Pending approval' : 'On duty',
      allSales: staffSales,
      allReplacements: replacementHistory,
    }
  })
}

const startEdit = (member) => {
  editingId.value = member.id
  editForm.value = { display_name: member.name, role: member.role }
}

const cancelEdit = () => {
  editingId.value = null
  editForm.value = { display_name: '', role: 'employee' }
}

const saveProfile = async () => {
  if (!$supabase || !editingId.value || !editForm.value.display_name.trim() || isSaving.value) return

  isSaving.value = true
  const { error } = await $supabase
    .from('profiles')
    .update({ display_name: editForm.value.display_name.trim(), role: editForm.value.role })
    .eq('id', editingId.value)

  if (!error) {
    cancelEdit()
    await fetchStaff()
  }
  isSaving.value = false
}

const removeEmployee = async (member) => {
  if (!$supabase || !window.confirm(`Remove ${member.name} as an employee? Their sales and replacement history will remain.`)) return

  const { error } = await $supabase.from('profiles').delete().eq('id', member.id)
  if (!error) await fetchStaff()
}

const approveEmployee = async (member) => {
  if (!$supabase) return

  const { error } = await $supabase.from('profiles').update({ role: 'employee' }).eq('id', member.id)
  if (!error) await fetchStaff()
}

onMounted(fetchStaff)
</script>

<template>
  <div class="page-shell">
    <header class="topbar">
      <div>
        <p class="eyebrow">Staff</p>
        <h1>Team Overview</h1>
      </div>
    </header>

    

    <section class="panel">
      <div class="panel-header">
        <h3>Staff Performance</h3>
        <div class="history-controls">
          <label for="staff-history-date">History date</label>
          <input id="staff-history-date" v-model="selectedDate" type="date" />
          <button type="button" @click="showToday">Today</button>
        </div>
      </div>

      <div class="staff-list">
        <p v-if="staffError" class="error-state">{{ staffError }} Run supabase/employee-approval.sql in Supabase.</p>
        <p v-if="!staff.length" class="empty-state">No employee profiles found.</p>
        <article v-for="member in staffForSelectedDate" :key="member.id" class="staff-item">
          <div class="avatar">{{ member.name.charAt(0) }}</div>
          <div v-if="editingId !== member.id" class="info">
            <h4>{{ member.name }}</h4>
            <p>{{ member.email }}</p>
            <p>{{ member.role }}</p>
            <div v-if="member.history.length" class="history-list">
              <p class="history-heading">Sales history</p>
              <div v-for="sale in member.history" :key="sale.id" class="history-item">
                <span>{{ sale.product_name }} · {{ sale.quantity }} sold</span>
                <strong>{{ formatPeso(sale.total_amount) }}</strong>
              </div>
            </div>
            <div v-if="member.replacementHistory.length" class="history-list">
              <p class="history-heading">Replacement history</p>
              <div v-for="replacement in member.replacementHistory" :key="`replacement-${replacement.id}`" class="history-item">
                <span>
                  {{ replacement.product_name }} · {{ replacement.quantity }} replaced
                  <small>{{ replacement.reason }} · {{ shopDateTimeFormatter.format(new Date(replacement.created_at)) }}</small>
                </span>
              </div>
            </div>
            <p v-if="!member.history.length && !member.replacementHistory.length" class="no-activity">
              No sales or replacements for this date.
            </p>
          </div>
          <div v-else class="edit-form">
            <input v-model="editForm.display_name" type="text" aria-label="Employee name" />
            <select v-model="editForm.role" aria-label="Employee role">
              <option value="employee">Employee</option>
              <option value="owner">Owner</option>
            </select>
            <div class="edit-actions">
              <button type="button" @click="cancelEdit">Cancel</button>
              <button type="button" @click="saveProfile" :disabled="isSaving">{{ isSaving ? 'Saving...' : 'Save' }}</button>
            </div>
          </div>
          <div class="meta">
            <strong>{{ member.sales }}</strong>
            <span>{{ member.hours }}</span>
          </div>
          <div class="status-pill" :class="member.status === 'On duty' ? 'on' : 'break'">
            {{ member.status }}
          </div>
          <div v-if="editingId !== member.id" class="member-actions">
            <button type="button" @click="startEdit(member)">Edit</button>
            <button v-if="member.role === 'pending'" type="button" @click="approveEmployee(member)">Make employee</button>
            <button type="button" @click="removeEmployee(member)">Remove</button>
          </div>
        </article>
      </div>
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
h4,
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

.history-controls {
  display: flex;
  align-items: center;
  gap: 8px;
}

.history-controls label {
  color: #666666;
  font-size: 12px;
  font-weight: 600;
}

.history-controls input {
  border: 1px solid rgba(17, 17, 17, 0.12);
  border-radius: 9px;
  padding: 9px 10px;
  background: #ffffff;
  color: #111111;
  font: inherit;
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

.staff-list {
  display: grid;
  gap: 14px;
  margin-top: 16px;
}

.empty-state {
  margin: 0;
  color: #666666;
}

.no-activity {
  margin-top: 10px;
  color: #777777;
  font-size: 11px;
}

.error-state {
  margin: 0;
  padding: 12px;
  border-radius: 10px;
  background: #fff3f3;
  color: #b42323;
  font-size: 13px;
}

.staff-item {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto auto auto;
  align-items: center;
  gap: 14px;
  padding: 14px 16px;
  border-radius: 16px;
  background: #fafafa;
  border: 1px solid rgba(17, 17, 17, 0.05);
}

.avatar {
  width: 42px;
  height: 42px;
  border-radius: 50%;
  display: grid;
  place-items: center;
  background: #111111;
  color: #ffffff;
  font-weight: 700;
}

.info p,
.meta span {
  color: #666666;
  font-size: 12px;
}

.history-list {
  display: grid;
  gap: 5px;
  margin-top: 10px;
}

.history-heading {
  margin: 0;
  color: #333333;
  font-size: 11px;
  font-weight: 700;
}

.history-item {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding-top: 5px;
  border-top: 1px solid rgba(17, 17, 17, 0.07);
  color: #555555;
  font-size: 11px;
}

.history-item strong {
  color: #111111;
  white-space: nowrap;
}

.history-item small {
  display: block;
  margin-top: 3px;
  color: #777777;
  font-size: 10px;
}

.edit-form {
  display: grid;
  gap: 8px;
}

.edit-form input,
.edit-form select {
  min-width: 180px;
  border: 1px solid rgba(17, 17, 17, 0.12);
  border-radius: 8px;
  padding: 8px 10px;
  background: #ffffff;
  color: #111111;
  font: inherit;
}

.edit-actions,
.member-actions {
  display: flex;
  gap: 6px;
}

.edit-actions button,
.member-actions button {
  border: 1px solid rgba(17, 17, 17, 0.1);
  border-radius: 8px;
  padding: 7px 9px;
  background: #ffffff;
  color: #111111;
  cursor: pointer;
  font-size: 11px;
  font-weight: 700;
}

.member-actions button:last-child {
  color: #b42323;
}

.meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
}

.status-pill {
  display: inline-flex;
  padding: 7px 10px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
}

.status-pill.on {
  background: rgba(17, 17, 17, 0.08);
  color: #111111;
}

.status-pill.break {
  background: rgba(17, 17, 17, 0.04);
  color: #333333;
}

@media (max-width: 900px) {
  .stats-grid {
    grid-template-columns: 1fr;
  }

  .staff-item {
    grid-template-columns: auto 1fr;
  }

  .meta,
  .status-pill,
  .member-actions,
  .edit-form {
    justify-self: start;
    align-items: flex-start;
  }

  .topbar,
  .panel-header {
    flex-direction: column;
    align-items: flex-start;
  }

  .history-controls {
    width: 100%;
    flex-wrap: wrap;
  }
}
</style>
