<script setup lang="ts">
import { useAuthStore } from './stores/auth';
import { usePhotosStore } from './stores/photos';
import { useRouter } from 'vue-router';

const auth = useAuthStore();
const photos = usePhotosStore();
const router = useRouter();

function logout() {
  photos.reset();
  auth.logout();
  void router.push('/login');
}
</script>

<template>
  <div class="page">
    <header class="top">
      <div>
        <p class="eyebrow">Coral Gardeners · interview prototype</p>
        <h1>ReefCapture — Scientist Dashboard</h1>
      </div>
      <button v-if="auth.isAuthenticated" class="ghost" type="button" @click="logout">Log out</button>
    </header>
    <router-view />
  </div>
</template>
