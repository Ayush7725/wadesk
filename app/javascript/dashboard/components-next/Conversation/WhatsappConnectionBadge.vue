<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

// WaDesk SAFE-FR-04: shows whether a WhatsApp inbox uses the Official platform or WhatsApp Web.
const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const { t } = useI18n();

const badge = computed(() => {
  const { channel_type: channelType, provider, medium } = props.inbox || {};
  if (channelType === INBOX_TYPES.WHATSAPP && provider === 'baileys') {
    return {
      label: t('INBOX_MGMT.WHATSAPP_WEB.BADGE.WEB'),
      tooltip: t('INBOX_MGMT.WHATSAPP_WEB.BADGE.WEB_TOOLTIP'),
      classes: 'bg-n-amber-3 text-n-amber-11',
    };
  }
  if (
    channelType === INBOX_TYPES.WHATSAPP ||
    (channelType === INBOX_TYPES.TWILIO && medium === 'whatsapp')
  ) {
    return {
      label: t('INBOX_MGMT.WHATSAPP_WEB.BADGE.OFFICIAL'),
      tooltip: t('INBOX_MGMT.WHATSAPP_WEB.BADGE.OFFICIAL_TOOLTIP'),
      classes: 'bg-n-teal-3 text-n-teal-11',
    };
  }
  return null;
});
</script>

<template>
  <span class="contents">
    <span
      v-if="badge"
      :title="badge.tooltip"
      class="flex-shrink-0 px-1.5 rounded text-label-small"
      :class="badge.classes"
      data-test="whatsapp-connection-badge"
    >
      {{ badge.label }}
    </span>
  </span>
</template>
