<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { photoFileUrl, type Photo } from '../api';

/// create a component for the photo detail
const props = defineProps<{
  photo: Photo;
  conflictMessage: string;
  actionError: string;
}>();

/// create a function to emit the approve event
defineEmits<{
  approve: [];
  reject: [];
  retry: [];
}>();

/// create a variable to store the image URL
const imageUrl = ref<string | null>(null);
/// create a computed property for the processing status
const isProcessing = computed(() => props.photo.processingStatus === 'PROCESSING');

/// create a function to format the confidence
function percent(confidence: number | null): string {
  if (confidence == null) {
    return '—';
  }
  return `${Math.round(confidence * 100)}%`;
}

/// create a watch to update the image URL
watch(
  () => props.photo.id,
  async (id, _, onCleanup) => {
    if (imageUrl.value) {
      URL.revokeObjectURL(imageUrl.value);
      imageUrl.value = null;
    }
    try {
      const url = await photoFileUrl(id);
      imageUrl.value = url;
      onCleanup(() => {
        URL.revokeObjectURL(url);
      });
    } catch {
      imageUrl.value = null;
    }
  },
  { immediate: true },
);

/// create a function to revoke the image URL
onBeforeUnmount(() => {
  if (imageUrl.value) {
    URL.revokeObjectURL(imageUrl.value);
  }
});
</script>

<!-- create a template for the photo detail -->
<template>
  <section class="card detail">
    <h2>Selected photo</h2>
    <div class="detail-grid">
      <img v-if="imageUrl" :src="imageUrl" :alt="photo.originalName" />
      <div v-else class="photo-fallback">No preview</div>
      <dl>
        <div>
          <dt>Processing</dt>
          <dd>{{ photo.processingStatus }}</dd>
        </div>
        <div>
          <dt>Classification</dt>
          <dd>{{ photo.classification ?? (isProcessing ? 'waiting for job…' : '—') }}</dd>
        </div>
        <div>
          <dt>Confidence</dt>
          <dd>{{ percent(photo.confidence) }}</dd>
        </div>
        <div>
          <dt>Version</dt>
          <dd>{{ photo.version }}</dd>
        </div>
        <div>
          <dt>Status</dt>
          <dd>{{ photo.validationStatus === 'PENDING' ? 'PENDING VALIDATION' : photo.validationStatus }}</dd>
        </div>
      </dl>
    </div>

    <p v-if="conflictMessage" class="error">{{ conflictMessage }}</p>
    <p v-if="actionError" class="error">{{ actionError }}</p>

    <div class="actions">
      <button type="button" :disabled="isProcessing" @click="$emit('approve')">Approve</button>
      <button type="button" class="danger" :disabled="isProcessing" @click="$emit('reject')">Reject</button>
      <button type="button" class="ghost" :disabled="isProcessing" @click="$emit('retry')">Retry</button>
    </div>
  </section>
</template>
