<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import QRCode from 'qrcode';
import WhatsappWebSessionAPI from 'dashboard/api/whatsappWebSession';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// WaDesk: live linking panel for a WhatsApp Web inbox (QR code or pairing code, state, re-link).
const props = defineProps({
  inboxId: { type: Number, required: true },
});

const emit = defineEmits(['connected']);

const WAITING_STATES = ['connecting', 'qr_pending'];
const RELINKABLE_STATES = [
  'disconnected',
  'logged_out',
  'failed',
  'not_linked',
];
const WAITING_POLL_MS = 2000;
const IDLE_POLL_MS = 15000;

const { t } = useI18n();
const session = ref(null);
const qrImage = ref('');
const isUnavailable = ref(false);
const isReconnecting = ref(false);
let pollTimer;
let isUnmounted = false;

const state = computed(() => session.value?.state);
const isWaiting = computed(() => WAITING_STATES.includes(state.value));
const canRelink = computed(() => RELINKABLE_STATES.includes(state.value));
const stateLabels = computed(() => ({
  connecting: t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.STATE.connecting'),
  qr_pending: t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.STATE.qr_pending'),
  connected: t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.STATE.connected'),
  disconnected: t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.STATE.disconnected'),
  logged_out: t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.STATE.logged_out'),
  failed: t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.STATE.failed'),
  not_linked: t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.STATE.not_linked'),
}));
const errorMessages = computed(() => ({
  number_mismatch: t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.ERRORS.number_mismatch'),
  forbidden: t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.ERRORS.forbidden'),
  unlinked_from_phone: t(
    'INBOX_MGMT.WHATSAPP_WEB.CONNECT.ERRORS.unlinked_from_phone'
  ),
  qr_expired: t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.ERRORS.qr_expired'),
  logged_out_by_admin: t(
    'INBOX_MGMT.WHATSAPP_WEB.CONNECT.ERRORS.logged_out_by_admin'
  ),
}));

const stateLabel = computed(() => stateLabels.value[state.value] ?? '');
const errorMessage = computed(() => {
  if (isUnavailable.value) {
    return t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.ERRORS.unavailable');
  }
  return errorMessages.value[session.value?.last_error] ?? '';
});

const fetchSession = async () => {
  try {
    const { data } = await WhatsappWebSessionAPI.get(props.inboxId);
    session.value = data;
    isUnavailable.value = false;
  } catch {
    isUnavailable.value = true;
  }
};

// Poll often while waiting for the phone, rarely otherwise.
const poll = async () => {
  await fetchSession();
  if (isUnmounted) return;
  pollTimer = setTimeout(
    poll,
    isWaiting.value ? WAITING_POLL_MS : IDLE_POLL_MS
  );
};

const relink = async () => {
  isReconnecting.value = true;
  try {
    const { data } = await WhatsappWebSessionAPI.reconnect(props.inboxId);
    session.value = data;
  } catch {
    isUnavailable.value = true;
  } finally {
    isReconnecting.value = false;
  }
  clearTimeout(pollTimer);
  poll();
};

watch(
  () => session.value?.qr,
  async qr => {
    qrImage.value = qr
      ? await QRCode.toDataURL(qr, { width: 256, margin: 1 })
      : '';
  }
);

watch(state, value => {
  if (value === 'connected') emit('connected', session.value.me);
});

onMounted(poll);
onBeforeUnmount(() => {
  isUnmounted = true;
  clearTimeout(pollTimer);
});

defineExpose({ refresh: fetchSession });
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex items-center gap-2">
      <Spinner v-if="!session || isWaiting" class="size-4" />
      <span class="text-body-main text-n-slate-12" data-test="state">
        {{ stateLabel }}
      </span>
    </div>

    <div v-if="session?.pairing_code" class="flex flex-col gap-2">
      <p class="text-body-main text-n-slate-11">
        {{ $t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.CODE_STEPS') }}
      </p>
      <span
        class="font-mono text-heading-1 tracking-[0.3em] text-n-slate-12"
        data-test="pairing-code"
      >
        {{ session.pairing_code }}
      </span>
    </div>

    <div v-else-if="qrImage" class="flex flex-col gap-2">
      <p class="text-body-main text-n-slate-11">
        {{ $t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.QR_STEPS') }}
      </p>
      <img
        :src="qrImage"
        :alt="stateLabel"
        class="size-64 rounded-lg bg-white"
        data-test="qr-code"
      />
    </div>

    <p
      v-if="state === 'connected'"
      class="text-body-main text-n-teal-11"
      data-test="connected"
    >
      {{
        $t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.CONNECTED', {
          phone: session.me?.phone ? `+${session.me.phone}` : '',
        })
      }}
    </p>

    <p
      v-if="errorMessage"
      class="text-body-main text-n-ruby-11"
      data-test="error"
    >
      {{ errorMessage }}
    </p>

    <div v-if="canRelink || isUnavailable">
      <Button
        :label="$t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.RECONNECT')"
        :is-loading="isReconnecting"
        data-test="relink"
        @click="relink"
      />
    </div>
  </div>
</template>
