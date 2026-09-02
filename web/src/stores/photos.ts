import { defineStore } from 'pinia';
import { ref } from 'vue';
import { listPhotos, retryPhoto, validatePhoto, type Photo } from '../api';

/// create a store for the photos
export const usePhotosStore = defineStore('photos', () => {
  const photos = ref<Photo[]>([]);
  const conflictMessage = ref('');
  const actionError = ref('');

  /// create a variable to store the poll timer
  let pollTimer: ReturnType<typeof setInterval> | undefined;

  /// create a function to get the photo by id
  function photoById(id: string | undefined): Photo | undefined {
    if (!id) {
      return undefined;
    }
    return photos.value.find((photo) => photo.id === id);
  }

  /// create a function to replace the photo
  function replacePhoto(updated: Photo) {
    photos.value = photos.value.map((photo) => (photo.id === updated.id ? updated : photo));
  }

  /// create a function to stop the polling
  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = undefined;
    }
  }

  /// create a function to sync the polling
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

  /// create a function to refresh the photos
  async function refresh(options?: { silent?: boolean }) {
    if (!options?.silent) {
      actionError.value = '';
      conflictMessage.value = '';
    }
    photos.value = await listPhotos();
    syncPolling();
  }

  /// create a function to validate the photo
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

  /// create a function to retry the photo
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

  /// create a function to reset the photos
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
