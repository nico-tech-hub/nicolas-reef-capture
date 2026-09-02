import { defineStore } from 'pinia';
import { computed, ref } from 'vue';
import { clearToken, getToken, login as loginRequest } from '../api';

/// create a store for the auth
export const useAuthStore = defineStore('auth', () => {
  const tokenPresent = ref(Boolean(getToken()));
  const isAuthenticated = computed(() => tokenPresent.value);

  /// create a function to login the user
  async function login(email: string, password: string) {
    await loginRequest(email, password);
    tokenPresent.value = true;
  }

  /// create a function to logout the user
  function logout() {
    clearToken();
    tokenPresent.value = false;
  }

  return { isAuthenticated, login, logout };
});
