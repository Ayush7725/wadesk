<script setup>
// WaDesk: shown when a page belongs to a feature that is off for the account.
import { useRoute, useRouter } from 'vue-router';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const route = useRoute();
const router = useRouter();

const goToConversations = () => {
  router.push({ name: 'home', params: { accountId: route.params.accountId } });
};
</script>

<template>
  <div
    class="flex items-center justify-center w-full h-full bg-n-background"
    data-test-id="feature-not-on-plan"
  >
    <EmptyState
      class="max-w-lg"
      :title="$t('APP_GLOBAL.FEATURE_NOT_ON_PLAN.TITLE')"
      :message="$t('APP_GLOBAL.FEATURE_NOT_ON_PLAN.MESSAGE')"
    >
      <div class="flex justify-center mt-4">
        <NextButton
          icon="i-lucide-message-circle"
          :label="$t('APP_GLOBAL.FEATURE_NOT_ON_PLAN.BACK_TO_CONVERSATIONS')"
          @click="goToConversations"
        />
      </div>
    </EmptyState>
  </div>
</template>
