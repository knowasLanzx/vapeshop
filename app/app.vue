<script setup>
const route = useRoute()
const { $supabase, $auth } = useNuxtApp()

const navItems = [
  { label: 'Dashboard', path: '/dashboard' },
  { label: 'Products', path: '/products' },
  { label: 'Sales', path: '/sales' },
  { label: 'My Sale', path: '/my-sales' },
  { label: 'Inventory', path: '/inventory' },
  { label: 'Staff', path: '/staff' },
]

const isActive = (path) => route.path === path
const isAuthRoute = computed(() => ['/', '/login'].includes(route.path))
const visibleNavItems = computed(() => {
  const role = $auth?.profile.value?.role

  if (role === 'owner') {
    return navItems.filter((item) => item.path !== '/my-sales')
  }

  return navItems.filter((item) => ['/sales', '/my-sales'].includes(item.path))
})

const signOut = async () => {
  await $supabase?.auth.signOut()
  $auth?.clear()
  await navigateTo('/login')
}
</script>

<template>
  <div v-if="isAuthRoute" class="auth-shell">
    <NuxtPage />
  </div>

  <div v-else class="app-shell">
    <aside class="sidebar">
      <div class="brand-wrap">
        <div class="brand-mark">V</div>
        <div>
          <p class="eyebrow">POS</p>
          <h1>VapeShop</h1>
        </div>
      </div>

      <nav class="nav">
        <NuxtLink
          v-for="item in visibleNavItems"
          :key="item.label"
          :to="item.path"
          :class="['nav-item', { active: isActive(item.path) }]"
        >
          <span>{{ item.label }}</span>
        </NuxtLink>
      </nav>

      <div class="sidebar-card">
        <p class="card-label">Signed in as</p>
        <h3>{{ $auth?.profile.value?.role === 'owner' ? 'Owner' : 'Employee' }}</h3>
        <span>{{ $auth?.user.value?.email }}</span>
        <button class="sign-out-btn" type="button" @click="signOut">Sign out</button>
      </div>
    </aside>

    <main class="page-shell">
      <NuxtPage />
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

.auth-shell,
.app-shell {
  min-height: 100vh;
  display: flex;
  background: #f5f5f5;
  color: #111111;
}

.auth-shell {
  display: block;
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

.brand-wrap h1 {
  margin: 0;
  color: #ffffff;
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
  color: #111111;
}

.sidebar-card span,
.card-label {
  color: #636363;
}

.sign-out-btn {
  display: block;
  margin-top: 14px;
  border: 0;
  padding: 0;
  background: transparent;
  color: #111111;
  font-weight: 700;
  cursor: pointer;
}

.page-shell {
  flex: 1;
  min-width: 0;
}

@media (max-width: 980px) {
  .app-shell {
    flex-direction: column;
  }

  .sidebar {
    width: 100%;
    min-height: auto;
    position: static;
    border-right: none;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  }
}
</style>
