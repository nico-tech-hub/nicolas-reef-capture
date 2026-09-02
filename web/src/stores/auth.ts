import { defineStore } from 'pinia';
import { computed, ref } from 'vue';
import { clearToken, getToken, login as loginRequest } from '../api';

export const useAuthStore = defineStore('auth', () => {
  const tokenPresent = ref(Boolean(getToken()));
  const isAuthenticated = computed(() => tokenPresent.value);

  async function login(email: string, password: string) {
    await loginRequest(email, password);
    tokenPresent.value = true;
  }

  function logout() {
    clearToken();
    tokenPresent.value = false;
  }

  return { isAuthenticated, login, logout };
});
