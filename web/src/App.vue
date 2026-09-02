<script setup lang="ts">
import { useAuthStore } from './stores/auth';
import { usePhotosStore } from './stores/photos';
import { useRouter } from 'vue-router';

/// create a store for the auth and photos
const auth = useAuthStore();
const photos = usePhotosStore();
const router = useRouter();

/// create a function to logout the user
function logout() {
  photos.reset(); // reset the photos store
  auth.logout(); // logout the user
  void router.push('/login'); // redirect to the login page
}
</script>

<!-- create a template for the app -->
<template>
  <div class="page">
    <header class="top">
      <div>
        <p class="eyebrow">Coral Gardeners · interview prototype</p>
        <h1>ReefCapture — Scientist Dashboard</h1>
      </div>
      <button v-if="auth.isAuthenticated" 
          class="ghost" 
          type="button" 
          @click="logout">
          Log out
        </button>
    </header>
    <!-- create a router view for the app -->
    <router-view />
  </div>
</template>
