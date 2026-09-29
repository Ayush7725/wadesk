<script setup>
import { useAttrs } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const attrs = useAttrs();
const globalConfig = useMapGetter('globalConfig/get');
</script>

<template>
  <img
    v-if="globalConfig.logoThumbnail"
    v-bind="attrs"
    :src="globalConfig.logoThumbnail"
  />
  <svg
    v-else
    v-once
    v-bind="attrs"
    width="16"
    height="16"
    viewBox="0 0 512 512"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
  >
    <rect width="512" height="512" rx="112" fill="#2781F6" />
    <path
      d="M140 136H372A44 44 0 0 1 416 180V304A44 44 0 0 1 372 348H232L166 398C158 404 148 399 148 389V348H140A44 44 0 0 1 96 304V180A44 44 0 0 1 140 136Z"
      fill="white"
    />
    <rect x="150" y="204" width="212" height="28" rx="14" fill="#2781F6" />
    <rect x="150" y="256" width="140" height="28" rx="14" fill="#2781F6" />
  </svg>
</template>
