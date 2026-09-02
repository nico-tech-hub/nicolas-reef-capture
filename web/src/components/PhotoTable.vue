<script setup lang="ts">
import type { Photo } from '../api';

/// create a component for the photo table
defineProps<{
  photos: Photo[];
  selectedId?: string;
}>();

/// create a function to select the photo
defineEmits<{
  select: [id: string];
}>();
</script>

<!-- create a template for the photo table -->
<template>
  <table>
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
        @click="$emit('select', photo.id)"
      >
        <td>{{ photo.originalName }}</td>
        <td>{{ photo.userEmail }}</td>
        <td>{{ photo.processingStatus }}</td>
        <td>{{ photo.validationStatus }}</td>
        <td>{{ photo.retryCount }}</td>
      </tr>
    </tbody>
  </table>
</template>
