<script setup>
const { $supabase, $auth } = useNuxtApp()
const mode = ref('signin')
const fullName = ref('')
const email = ref('')
const password = ref('')
const confirmPassword = ref('')
const loading = ref(false)
const errorMessage = ref('')
const successMessage = ref('')

const resetMessages = () => {
  errorMessage.value = ''
  successMessage.value = ''
}

const ensurePendingProfile = async (userId, name, emailValue) => {
  if (!$supabase) return

  const { error } = await $supabase.from('profiles').upsert({
    id: userId,
    email: emailValue,
    display_name: name.trim(),
    role: 'pending',
  }, { onConflict: 'id' })

  if (error) console.error('Pending profile setup failed:', error)
}

onMounted(async () => {
  if (!$auth?.user.value) return
  if ($auth.profile.value) {
    await navigateTo('/dashboard')
  } else {
    errorMessage.value = 'This account has no owner or employee role assigned. Ask the owner to set up your account.'
  }
})

const login = async () => {
  if (!$supabase || loading.value) return

  loading.value = true
  resetMessages()

  const { error } = await $supabase.auth.signInWithPassword({
    email: email.value.trim().toLowerCase(),
    password: password.value,
  })

  if (error) {
    errorMessage.value = 'Sign in failed. Check your email and password.'
    loading.value = false
    return
  }

  const profile = await $auth.refreshProfile()
  if (!profile || !['owner', 'employee'].includes(profile.role)) {
    await $supabase.auth.signOut()
    $auth.clear()
    errorMessage.value = profile?.role === 'pending'
      ? 'Your account is waiting for owner approval.'
      : 'This account has no assigned role. Ask the owner to set up your account.'
    loading.value = false
    return
  }

  await navigateTo('/dashboard')
  loading.value = false
}

const signUp = async () => {
  if (!$supabase || loading.value) return

  if (!fullName.value.trim()) {
    errorMessage.value = 'Please enter your full name.'
    return
  }

  if (password.value !== confirmPassword.value) {
    errorMessage.value = 'Passwords do not match.'
    return
  }

  loading.value = true
  resetMessages()

  const emailValue = email.value.trim().toLowerCase()
  const { data, error } = await $supabase.auth.signUp({
    email: emailValue,
    password: password.value,
    options: {
      data: {
        full_name: fullName.value.trim(),
      },
    },
  })

  if (error) {
    errorMessage.value = error.message || 'Unable to create your account.'
    loading.value = false
    return
  }

  if (data.user) await ensurePendingProfile(data.user.id, fullName.value, emailValue)

  successMessage.value = 'Account created and sent for owner approval.'
  mode.value = 'signin'
  fullName.value = ''
  email.value = ''
  password.value = ''
  confirmPassword.value = ''
  loading.value = false
}

const submitForm = async () => {
  if (loading.value) return

  if (mode.value === 'signup') {
    await signUp()
    return
  }

  await login()
}
</script>

<template>
  <div class="login-page">
    <div class="login-card">
      <div class="brand-block">
        <div class="brand-mark">V</div>
        <p class="eyebrow">VapeShop POS</p>
        <h1>{{ mode === 'signin' ? 'Welcome back' : 'Create your account' }}</h1>
        <p class="subtitle">
          {{ mode === 'signin' ? 'Sign in with your employee or owner account to open the store dashboard.' : 'Set up a staff account for the vape shop.' }}
        </p>
      </div>

      <div class="login-form-wrap">
        <div class="switch-row" role="tablist" aria-label="Authentication mode">
          <button type="button" class="switch-btn" :class="{ active: mode === 'signin' }" :disabled="loading" @click="mode = 'signin'">
            Sign in
          </button>
          <button type="button" class="switch-btn" :class="{ active: mode === 'signup' }" :disabled="loading" @click="mode = 'signup'">
            Sign up
          </button>
        </div>

        <form class="login-form" @submit.prevent="submitForm">
          <label v-if="mode === 'signup'">
            <span>Full name</span>
            <input v-model="fullName" type="text" placeholder="Your full name" autocomplete="name" required />
          </label>

          <label>
            <span>Email</span>
            <input v-model="email" type="email" placeholder="you@example.com" autocomplete="username" required />
          </label>

          <label>
            <span>Password</span>
            <input v-model="password" type="password" placeholder="Your password" autocomplete="current-password" required />
          </label>

          <label v-if="mode === 'signup'">
            <span>Confirm password</span>
            <input v-model="confirmPassword" type="password" placeholder="Confirm password" autocomplete="new-password" required />
          </label>

          <p v-if="!$supabase" class="form-message" role="status">Add your Supabase URL and public key to the project .env file to enable sign in.</p>
          <p v-else-if="errorMessage" class="form-message error" role="alert">{{ errorMessage }}</p>
          <p v-else-if="successMessage" class="form-message success" role="status">{{ successMessage }}</p>
          <p v-else class="role-note">
            {{ mode === 'signin' ? 'Your assigned role is applied automatically.' : 'Your account will be created as a staff member by default.' }}
          </p>

          <button type="submit" class="primary-btn" :disabled="loading || !$supabase">
            {{ loading ? (mode === 'signin' ? 'Signing in…' : 'Creating account…') : (mode === 'signin' ? 'Sign in' : 'Sign up') }}
          </button>
        </form>
      </div>
    </div>
  </div>
</template>

<style scoped>
.login-page {
  min-height: 100vh;
  display: grid;
  place-items: center;
  background: linear-gradient(135deg, #0d0d0d 0%, #1c1c1c 35%, #f4f4f4 35%, #f4f4f4 100%);
  padding: 24px;
}

.login-card {
  width: min(100%, 900px);
  background: rgba(255, 255, 255, 0.96);
  border: 1px solid rgba(17, 17, 17, 0.08);
  border-radius: 28px;
  box-shadow: 0 20px 50px rgba(17, 17, 17, 0.14);
  display: grid;
  grid-template-columns: 1.1fr 1fr;
  overflow: hidden;
}

.brand-block {
  background: #111111;
  color: #ffffff;
  padding: 48px 40px;
  display: flex;
  flex-direction: column;
  justify-content: center;
}

.brand-mark {
  width: 54px;
  height: 54px;
  border-radius: 16px;
  display: grid;
  place-items: center;
  background: #ffffff;
  color: #111111;
  font-weight: 800;
  font-size: 28px;
  margin-bottom: 18px;
}

.eyebrow {
  margin: 0 0 8px;
  font-size: 11px;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  color: #bdbdbd;
}

.brand-block h1 {
  margin: 0;
  font-size: 42px;
  line-height: 1.05;
}

.subtitle {
  margin-top: 14px;
  color: #d6d6d6;
  line-height: 1.6;
  max-width: 360px;
}

.login-form-wrap {
  padding: 48px 40px;
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 18px;
}

.switch-row {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
  background: #f2f2f2;
  border-radius: 12px;
  padding: 6px;
}

.switch-btn {
  border: none;
  border-radius: 10px;
  background: transparent;
  padding: 10px 12px;
  font-weight: 700;
  color: #555555;
  cursor: pointer;
}

.switch-btn.active {
  background: #111111;
  color: #ffffff;
}

.login-form {
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.login-form label {
  display: grid;
  gap: 8px;
  font-size: 13px;
  color: #333333;
}

.login-form input {
  width: 100%;
  border: 1px solid rgba(17, 17, 17, 0.1);
  background: #fafafa;
  border-radius: 12px;
  padding: 13px 14px;
  color: #111111;
}

.login-form input:focus {
  outline: 2px solid rgba(17, 17, 17, 0.12);
  border-color: rgba(17, 17, 17, 0.25);
}

.primary-btn {
  border: none;
  border-radius: 12px;
  background: #111111;
  color: #ffffff;
  font-weight: 600;
  padding: 14px 16px;
  cursor: pointer;
}

.primary-btn:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.form-message,
.role-note {
  margin: 0;
  font-size: 13px;
  line-height: 1.5;
  color: #626262;
}

.form-message.error {
  color: #a12b2b;
}

.form-message.success {
  color: #1a6a42;
}

@media (max-width: 760px) {
  .login-card {
    grid-template-columns: 1fr;
  }

  .brand-block,
  .login-form-wrap {
    padding: 30px 24px;
  }

  .brand-block h1 {
    font-size: 32px;
  }
}
</style>
