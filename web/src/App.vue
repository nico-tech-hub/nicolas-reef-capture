<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import {
  clearToken,
  getToken,
  listPhotos,
  login,
  photoFileUrl,
  retryPhoto,
  validatePhoto,
  type Photo,
} from './api';

const email = ref('scientist@example.com');
const password = ref('password');
const loggedIn = ref(Boolean(getToken()));
const loginError = ref('');
const loading = ref(false);

const photos = ref<Photo[]>([]);
const selectedId = ref<string | null>(null);
const imageUrl = ref<string | null>(null);
const conflictMessage = ref('');
const actionError = ref('');

const selected = computed(() => photos.value.find((photo) => photo.id === selectedId.value) ?? null);

async function submitLogin() {
  loginError.value = '';
  loading.value = true;
  try {
    await login(email.value, password.value);
    loggedIn.value = true;
    await refresh();
  } catch {
    loginError.value = 'Invalid credentials';
  } finally {
    loading.value = false;
  }
}

function logout() {
  clearToken();
  loggedIn.value = false;
  photos.value = [];
  selectedId.value = null;
}

async function refresh() {
  actionError.value = '';
  conflictMessage.value = '';
  photos.value = await listPhotos();
  if (!selectedId.value && photos.value[0]) {
    selectedId.value = photos.value[0].id;
  } else if (selectedId.value && !photos.value.some((photo) => photo.id === selectedId.value)) {
    selectedId.value = photos.value[0]?.id ?? null;
  }
}

function replacePhoto(updated: Photo) {
  photos.value = photos.value.map((photo) => (photo.id === updated.id ? updated : photo));
}

async function approve() {
  await runValidation(true);
}

async function reject() {
  await runValidation(false);
}

async function runValidation(approved: boolean) {
  if (!selected.value) {
    return;
  }
  actionError.value = '';
  conflictMessage.value = '';
  try {
    replacePhoto(await validatePhoto(selected.value.id, selected.value.version, approved));
  } catch (error) {
    const status = (error as Error & { status?: number }).status;
    if (status === 409) {
      conflictMessage.value = 'Conflict: this result has been modified by another user. Please refresh.';
    } else {
      actionError.value = (error as Error).message;
    }
  }
}

async function retry() {
  if (!selected.value) {
    return;
  }
  actionError.value = '';
  conflictMessage.value = '';
  try {
    replacePhoto(await retryPhoto(selected.value.id));
  } catch (error) {
    actionError.value = (error as Error).message;
  }
}

function percent(confidence: number | null): string {
  if (confidence == null) {
    return '—';
  }
  return `${Math.round(confidence * 100)}%`;
}

watch(selectedId, async (id, _, onCleanup) => {
  if (imageUrl.value) {
    URL.revokeObjectURL(imageUrl.value);
    imageUrl.value = null;
  }
  if (!id) {
    return;
  }
  const url = await photoFileUrl(id);
  imageUrl.value = url;
  onCleanup(() => {
    URL.revokeObjectURL(url);
  });
});

onMounted(async () => {
  if (loggedIn.value) {
    try {
      await refresh();
    } catch {
      logout();
    }
  }
});

onBeforeUnmount(() => {
  if (imageUrl.value) {
    URL.revokeObjectURL(imageUrl.value);
  }
});
</script>

<template>
  <div class="page">
    <header class="top">
      <div>
        <p class="eyebrow">Coral Gardeners · interview prototype</p>
        <h1>ReefCapture — Scientist Dashboard</h1>
      </div>
      <button v-if="loggedIn" class="ghost" type="button" @click="logout">Log out</button>
    </header>

    <section v-if="!loggedIn" class="card login">
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
        <button type="submit" :disabled="loading">{{ loading ? 'Signing in…' : 'Sign in' }}</button>
      </form>
    </section>

    <template v-else>
      <section class="card">
        <div class="card-head">
          <h2>Photos</h2>
          <button class="ghost" type="button" @click="refresh">Refresh</button>
        </div>
        <p v-if="photos.length === 0" class="muted">No photos yet. Upload one from the iOS app.</p>
        <table v-else>
          <thead>
            <tr>
              <th>Photo</th>
              <th>User</th>
              <th>Processing</th>
              <th>Validation</th>
              <th>Retries</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="photo in photos"
              :key="photo.id"
              :class="{ selected: photo.id === selectedId }"
              @click="selectedId = photo.id"
            >
              <td>{{ photo.originalName }}</td>
              <td>{{ photo.userEmail }}</td>
              <td>{{ photo.processingStatus }}</td>
              <td>{{ photo.validationStatus }}</td>
              <td>{{ photo.retryCount }}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section v-if="selected" class="card detail">
        <h2>Selected photo</h2>
        <div class="detail-grid">
          <img v-if="imageUrl" :src="imageUrl" :alt="selected.originalName" />
          <div v-else class="photo-fallback">No preview</div>
          <dl>
            <div>
              <dt>Classification</dt>
              <dd>{{ selected.classification ?? '—' }}</dd>
            </div>
            <div>
              <dt>Confidence</dt>
              <dd>{{ percent(selected.confidence) }}</dd>
            </div>
            <div>
              <dt>Version</dt>
              <dd>{{ selected.version }}</dd>
            </div>
            <div>
              <dt>Status</dt>
              <dd>{{ selected.validationStatus === 'PENDING' ? 'PENDING VALIDATION' : selected.validationStatus }}</dd>
            </div>
          </dl>
        </div>

        <p v-if="conflictMessage" class="error">{{ conflictMessage }}</p>
        <p v-if="actionError" class="error">{{ actionError }}</p>

        <div class="actions">
          <button type="button" @click="approve">Approve</button>
          <button type="button" class="danger" @click="reject">Reject</button>
          <button type="button" class="ghost" @click="retry">Retry</button>
        </div>
      </section>
    </template>
  </div>
</template>

<style scoped>
.page {
  max-width: 960px;
  margin: 0 auto;
  padding: 32px 20px 64px;
}

.top {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
  margin-bottom: 24px;
}

.eyebrow {
  margin: 0 0 4px;
  color: #3d7a86;
  font-size: 12px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

h1 {
  margin: 0;
  font-size: 28px;
  font-weight: 650;
}

h2 {
  margin: 0;
  font-size: 18px;
}

.card {
  background: #fff;
  border: 1px solid #d5e3e7;
  border-radius: 12px;
  padding: 20px;
  margin-bottom: 16px;
}

.card-head,
.actions {
  display: flex;
  gap: 8px;
  align-items: center;
}

.card-head {
  justify-content: space-between;
  margin-bottom: 16px;
}

.login form {
  display: grid;
  gap: 12px;
  max-width: 360px;
  margin-top: 16px;
}

label {
  display: grid;
  gap: 6px;
  font-size: 14px;
}

input {
  padding: 10px 12px;
  border: 1px solid #c5d5da;
  border-radius: 8px;
  font: inherit;
}

button {
  border: 0;
  border-radius: 8px;
  padding: 10px 14px;
  background: #0f6e7a;
  color: #fff;
  font: inherit;
  cursor: pointer;
}

button:disabled {
  opacity: 0.6;
}

button.ghost {
  background: #e7f1f3;
  color: #0f6e7a;
}

button.danger {
  background: #9b3a3a;
}

table {
  width: 100%;
  border-collapse: collapse;
}

th,
td {
  text-align: left;
  padding: 10px 8px;
  border-bottom: 1px solid #e6eef0;
  font-size: 14px;
}

tbody tr {
  cursor: pointer;
}

tbody tr.selected {
  background: #e8f5f7;
}

.detail-grid {
  display: grid;
  grid-template-columns: 220px 1fr;
  gap: 20px;
  margin: 16px 0;
}

img,
.photo-fallback {
  width: 220px;
  height: 160px;
  object-fit: cover;
  border-radius: 8px;
  background: #d9e6ea;
}

.photo-fallback {
  display: grid;
  place-items: center;
  color: #5b737a;
}

dl {
  margin: 0;
  display: grid;
  gap: 12px;
}

dt {
  font-size: 12px;
  color: #5b737a;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

dd {
  margin: 4px 0 0;
  font-size: 18px;
}

.muted,
.error {
  font-size: 14px;
}

.muted {
  color: #5b737a;
}

.error {
  color: #9b3a3a;
}

@media (max-width: 700px) {
  .detail-grid {
    grid-template-columns: 1fr;
  }
}
</style>
