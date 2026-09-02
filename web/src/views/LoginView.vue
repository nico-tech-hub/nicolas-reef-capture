<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '../stores/auth';

const auth = useAuthStore();
const router = useRouter();

const email = ref('scientist@example.com');
const password = ref('password');
const loginError = ref('');
const loading = ref(false);

/// create a function to submit the login form
async function submitLogin() {
  loginError.value = '';
  loading.value = true;
  try {
    await auth.login(email.value, password.value);
    await router.push('/photos');
  } catch {
    loginError.value = 'Invalid credentials';
  } finally {
    loading.value = false;
  }
}
</script>

<!-- create a template for the login view -->
<template>
  <section class="card login">
    <h2>Scientist login</h2>
    <form @submit.prevent="submitLogin">
      <label>
        Email
        <input v-model="email" type="email" autocomplete="username" />
      </label>
      <label>
        Password
        <input v-model="password" type="password" autocomplete="current-password" />
      </label>
      <p v-if="loginError" class="error">{{ loginError }}</p>
      <button type="submit" 
            :disabled="loading">
            {{ loading ? 'Signing in…' : 'Sign in' }}
      </button>
    </form>
  </section>
</template>
