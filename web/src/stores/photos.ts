import { defineStore } from 'pinia';
import { ref } from 'vue';
import { listPhotos, retryPhoto, validatePhoto, type Photo } from '../api';

export const usePhotosStore = defineStore('photos', () => {
  const photos = ref<Photo[]>([]);
  const conflictMessage = ref('');
  const actionError = ref('');

  let pollTimer: ReturnType<typeof setInterval> | undefined;

  function photoById(id: string | undefined): Photo | undefined {
    if (!id) {
      return undefined;
    }
    return photos.value.find((photo) => photo.id === id);
  }

  function replacePhoto(updated: Photo) {
    photos.value = photos.value.map((photo) => (photo.id === updated.id ? updated : photo));
  }

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = undefined;
    }
  }

  function syncPolling() {
    const busy = photos.value.some((photo) => photo.processingStatus === 'PROCESSING');
    if (busy && !pollTimer) {
      pollTimer = setInterval(() => {
        void refresh({ silent: true });
      }, 1500);
    }
    if (!busy) {
      stopPolling();
    }
  }

  async function refresh(options?: { silent?: boolean }) {
    if (!options?.silent) {
      actionError.value = '';
      conflictMessage.value = '';
    }
    photos.value = await listPhotos();
    syncPolling();
  }

  async function validate(photo: Photo, approved: boolean) {
    actionError.value = '';
    conflictMessage.value = '';
    try {
      replacePhoto(await validatePhoto(photo.id, photo.version, approved));
    } catch (error) {
      const status = (error as Error & { status?: number }).status;
      if (status === 409) {
        conflictMessage.value = 'Conflict: this result has been modified by another user. Please refresh.';
      } else {
        actionError.value = (error as Error).message;
      }
    }
  }

  async function retry(photo: Photo) {
    actionError.value = '';
    conflictMessage.value = '';
    try {
      replacePhoto(await retryPhoto(photo.id));
      syncPolling();
    } catch (error) {
      actionError.value = (error as Error).message;
    }
  }

  function reset() {
    stopPolling();
    photos.value = [];
    conflictMessage.value = '';
    actionError.value = '';
  }

  return {
    photos,
    conflictMessage,
    actionError,
    photoById,
    refresh,
    validate,
    retry,
    reset,
    stopPolling,
  };
});
