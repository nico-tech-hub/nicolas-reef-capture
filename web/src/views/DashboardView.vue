<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import PhotoDetail from '../components/PhotoDetail.vue';
import PhotoTable from '../components/PhotoTable.vue';
import { useAuthStore } from '../stores/auth';
import { usePhotosStore } from '../stores/photos';

/// create a route for the dashboard
const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const photos = usePhotosStore();

/// create a computed property for the selected id
const selectedId = computed(() => {
  const id = route.params.id;
  return typeof id === 'string' ? id : undefined;
});

/// create a computed property for the selected photo
const selected = computed(() => photos.photoById(selectedId.value));

/// create a function to select the photo
function selectPhoto(id: string) {
  if (id === selectedId.value) {
    return;
  }
  void router.push(`/photos/${id}`);
}

/// create a function to approve the photo
function approve() {
  if (selected.value) {
    void photos.validate(selected.value, true);
  }
}

/// create a function to reject the photo
function reject() {
  if (selected.value) {
    void photos.validate(selected.value, false);
  }
}

/// create a function to retry the photo
function retry() {
  if (selected.value) {
    void photos.retry(selected.value);
  }
}

/// create a function to ensure the selection
function ensureSelection() {
  const current = selectedId.value;
  const list = photos.photos;
  if (list.length === 0) {
    if (current) {
      void router.replace('/photos');
    }
    return;
  }
  const exists = current && list.some((photo) => photo.id === current);
  if (!exists) {
    void router.replace(`/photos/${list[0].id}`);
  }
}

/// create a function to refresh the photos
onMounted(async () => {
  try {
    await photos.refresh();
    ensureSelection();
  } catch {
    photos.reset();
    auth.logout();
    await router.push('/login');
  }
});

/// create a watch to ensure the selection
watch(
  () => photos.photos,
  () => {
    ensureSelection();
  },
);

onBeforeUnmount(() => {
  photos.stopPolling();
});
</script>

<template>
  <section class="card">
    <div class="card-head">
      <h2>Photos</h2>
      <button class="ghost" type="button" @click="photos.refresh()">Refresh</button>
    </div>
    <p v-if="photos.photos.length === 0" class="muted">No photos yet. Upload one from the iOS app.</p>
    <PhotoTable v-else :photos="photos.photos" :selected-id="selectedId" @select="selectPhoto" />
  </section>

  <PhotoDetail
    v-if="selected"
    :photo="selected"
    :conflict-message="photos.conflictMessage"
    :action-error="photos.actionError"
    @approve="approve"
    @reject="reject"
    @retry="retry"
  />
</template>
