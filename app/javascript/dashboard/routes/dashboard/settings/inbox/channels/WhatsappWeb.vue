<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { isPhoneE164OrEmpty } from 'shared/helpers/Validators';
import Input from 'dashboard/components-next/input/Input.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import WhatsappWebConnect from '../components/WhatsappWebConnect.vue';

// WaDesk: create a WhatsApp Web inbox, then link the phone (WW-FR-01/02/03, WW-NFR-10, ADR-0007).
const LINK_METHODS = { QR: 'qr', CODE: 'code' };

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const inboxName = ref('');
const phoneNumber = ref('');
const linkMethod = ref(LINK_METHODS.QR);
const acknowledged = ref(false);
const submitted = ref(false);
const isCreating = ref(false);
const createdInboxId = ref(null);
const isConnected = ref(false);

const nameError = computed(() =>
  submitted.value && !inboxName.value.trim()
    ? t('INBOX_MGMT.WHATSAPP_WEB.FORM.INBOX_NAME.ERROR')
    : ''
);
const phoneError = computed(() =>
  submitted.value &&
  (!phoneNumber.value || !isPhoneE164OrEmpty(phoneNumber.value))
    ? t('INBOX_MGMT.WHATSAPP_WEB.FORM.PHONE_NUMBER.ERROR')
    : ''
);
const showAcknowledgeError = computed(
  () => submitted.value && !acknowledged.value
);

const createInbox = async () => {
  submitted.value = true;
  if (nameError.value || phoneError.value || !acknowledged.value) return;

  isCreating.value = true;
  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: inboxName.value.trim(),
      channel: {
        type: 'whatsapp',
        phone_number: phoneNumber.value,
        provider: 'baileys',
        provider_config: { link_method: linkMethod.value },
      },
    });
    createdInboxId.value = inbox.id;
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.WHATSAPP_WEB.FORM.ERROR'));
  } finally {
    isCreating.value = false;
  }
};

const continueToAgents = () => {
  router.replace({
    name: 'settings_inboxes_add_agents',
    params: { page: 'new', inbox_id: createdInboxId.value },
  });
};
</script>

<template>
  <div v-if="createdInboxId" class="flex flex-col gap-6">
    <h2 class="text-heading-2 text-n-slate-12">
      {{ $t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.TITLE') }}
    </h2>
    <WhatsappWebConnect
      :inbox-id="createdInboxId"
      @connected="isConnected = true"
    />
    <div v-if="isConnected">
      <Button
        :label="$t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.CONTINUE')"
        data-test="continue"
        @click="continueToAgents"
      />
    </div>
  </div>

  <form v-else class="flex flex-col gap-5" @submit.prevent="createInbox">
    <div>
      <h2 class="text-heading-2 text-n-slate-12">
        {{ $t('INBOX_MGMT.WHATSAPP_WEB.FORM.TITLE') }}
      </h2>
      <p class="mt-1 text-body-main text-n-slate-11">
        {{ $t('INBOX_MGMT.WHATSAPP_WEB.FORM.DESCRIPTION') }}
      </p>
    </div>

    <Input
      v-model="inboxName"
      :label="$t('INBOX_MGMT.WHATSAPP_WEB.FORM.INBOX_NAME.LABEL')"
      :placeholder="$t('INBOX_MGMT.WHATSAPP_WEB.FORM.INBOX_NAME.PLACEHOLDER')"
      :message="nameError"
      :message-type="nameError ? 'error' : 'info'"
    />
    <Input
      v-model="phoneNumber"
      :label="$t('INBOX_MGMT.WHATSAPP_WEB.FORM.PHONE_NUMBER.LABEL')"
      :placeholder="$t('INBOX_MGMT.WHATSAPP_WEB.FORM.PHONE_NUMBER.PLACEHOLDER')"
      :message="phoneError"
      :message-type="phoneError ? 'error' : 'info'"
    />

    <div class="flex flex-col gap-2">
      <span class="text-body-main text-n-slate-12">
        {{ $t('INBOX_MGMT.WHATSAPP_WEB.FORM.LINK_METHOD.LABEL') }}
      </span>
      <RadioCard
        :id="LINK_METHODS.QR"
        name="link_method"
        :label="$t('INBOX_MGMT.WHATSAPP_WEB.FORM.LINK_METHOD.QR')"
        :description="$t('INBOX_MGMT.WHATSAPP_WEB.FORM.LINK_METHOD.QR_DESC')"
        :is-active="linkMethod === LINK_METHODS.QR"
        @select="linkMethod = $event"
      />
      <RadioCard
        :id="LINK_METHODS.CODE"
        name="link_method"
        :label="$t('INBOX_MGMT.WHATSAPP_WEB.FORM.LINK_METHOD.CODE')"
        :description="$t('INBOX_MGMT.WHATSAPP_WEB.FORM.LINK_METHOD.CODE_DESC')"
        :is-active="linkMethod === LINK_METHODS.CODE"
        @select="linkMethod = $event"
      />
    </div>

    <Banner color="amber" data-test="warning">
      {{ $t('INBOX_MGMT.WHATSAPP_WEB.FORM.WARNING') }}
    </Banner>
    <label class="flex items-start gap-2 text-body-main text-n-slate-12">
      <Checkbox v-model="acknowledged" data-test="acknowledge" />
      <span>{{ $t('INBOX_MGMT.WHATSAPP_WEB.FORM.ACKNOWLEDGE') }}</span>
    </label>
    <p
      v-if="showAcknowledgeError"
      class="text-body-main text-n-ruby-11"
      data-test="acknowledge-error"
    >
      {{ $t('INBOX_MGMT.WHATSAPP_WEB.FORM.ACKNOWLEDGE_ERROR') }}
    </p>

    <div>
      <Button
        type="submit"
        :label="$t('INBOX_MGMT.WHATSAPP_WEB.FORM.SUBMIT')"
        :is-loading="isCreating"
        data-test="submit"
      />
    </div>
  </form>
</template>
