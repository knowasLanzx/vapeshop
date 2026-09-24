import { createClient } from '@supabase/supabase-js'

export default defineNuxtPlugin(async () => {
  const config = useRuntimeConfig()
  const user = useState<any | null>('auth-user', () => null)
  const profile = useState<any | null>('auth-profile', () => null)
  const ready = useState('auth-ready', () => false)
  const url = config.public.supabaseUrl
  const key = config.public.supabaseAnonKey

  if (!url || !key) {
    ready.value = true
    return { provide: { supabase: null, auth: { user, profile, ready, refreshProfile: async () => null, clear: () => {} } } }
  }

  const supabase = createClient(url, key)

  const refreshProfile = async () => {
    const { data: { session } } = await supabase.auth.getSession()
    user.value = session?.user ?? null

    if (!user.value) {
      profile.value = null
      return null
    }

    const { data } = await supabase
      .from('profiles')
      .select('id, role, display_name')
      .eq('id', user.value.id)
      .maybeSingle()

    profile.value = data
    return data
  }

  const clear = () => {
    user.value = null
    profile.value = null
  }

  const { data: { session } } = await supabase.auth.getSession()
  user.value = session?.user ?? null
  if (user.value) await refreshProfile()
  ready.value = true

  supabase.auth.onAuthStateChange((_event, session) => {
    user.value = session?.user ?? null
    if (!session) profile.value = null
  })

  return { provide: { supabase, auth: { user, profile, ready, refreshProfile, clear } } }
})
