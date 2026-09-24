export default defineNuxtRouteMiddleware(async (to) => {
  if (import.meta.server) return

  const { $auth } = useNuxtApp()

  if (to.path === '/login') return

  if (to.path === '/') {
    if (!$auth?.user.value || !$auth.profile.value) return navigateTo('/login')
    return navigateTo($auth.profile.value.role === 'owner' ? '/dashboard' : '/sales')
  }

  if (!$auth?.user.value || !$auth.profile.value) return navigateTo('/login')

  if (!['owner', 'employee'].includes($auth.profile.value.role)) return navigateTo('/login')

  if ($auth.profile.value.role !== 'owner' && ['/dashboard', '/inventory', '/staff'].includes(to.path)) {
    return navigateTo('/sales')
  }
})
