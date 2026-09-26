<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WhatsappWebSessionAPI from 'dashboard/api/whatsappWebSession';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import WhatsappWebConnect from '../components/WhatsappWebConnect.vue';

// WaDesk: connection settings for a WhatsApp Web inbox (WW-FR-05/06/07).
const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();
const connect = ref(null);
const linkMethod = ref(props.inbox.provider_config?.link_method || 'qr');
const isSwitching = ref(false);
const confirmingLogout = ref(false);
const isLoggingOut = ref(false);

const switchLinkMethod = async method => {
  isSwitching.value = true;
  try {
    const { data } = await WhatsappWebSessionAPI.reconnect(
      props.inbox.id,
      method
    );
    linkMethod.value = data.link_method;
    await connect.value?.refresh();
  } catch {
    useAlert(t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.ERROR'));
  } finally {
    isSwitching.value = false;
  }
};

const logout = async () => {
  isLoggingOut.value = true;
  try {
    await WhatsappWebSessionAPI.logout(props.inbox.id);
    confirmingLogout.value = false;
    await connect.value?.refresh();
  } catch {
    useAlert(t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.ERROR'));
  } finally {
    isLoggingOut.value = false;
  }
};
</script>

<template>
  <div>
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.CONNECTION_TITLE')"
      :help-text="$t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.CONNECTION_DESC')"
    >
      <WhatsappWebConnect ref="connect" :inbox-id="inbox.id" />
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.LINK_METHOD_TITLE')"
      :help-text="$t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.LINK_METHOD_DESC')"
    >
      <div class="flex gap-2">
        <Button
          :label="$t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.USE_QR')"
          :variant="linkMethod === 'qr' ? 'solid' : 'outline'"
          :is-loading="isSwitching"
          data-test="use-qr"
          @click="switchLinkMethod('qr')"
        />
        <Button
          :label="$t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.USE_CODE')"
          :variant="linkMethod === 'code' ? 'solid' : 'outline'"
          :is-loading="isSwitching"
          data-test="use-code"
          @click="switchLinkMethod('code')"
        />
      </div>
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.LOGOUT_TITLE')"
      :help-text="$t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.LOGOUT_DESC')"
    >
      <div v-if="confirmingLogout" class="flex flex-col gap-2">
        <p class="text-body-main text-n-slate-12">
          {{ $t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.LOGOUT_CONFIRM') }}
        </p>
        <div class="flex gap-2">
          <Button
            ruby
            :label="
              $t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.LOGOUT_CONFIRM_BUTTON')
            "
            :is-loading="isLoggingOut"
            data-test="confirm-logout"
            @click="logout"
          />
          <Button
            variant="outline"
            :label="$t('INBOX_MGMT.WHATSAPP_WEB.SETTINGS.CANCEL')"
            @click="confirmingLogout = false"
          />
        </div>
      </div>
      <Button
        v-else
        ruby
        variant="outline"
        :label="$t('INBOX_MGMT.WHATSAPP_WEB.CONNECT.LOGOUT')"
        data-test="logout"
        @click="confirmingLogout = true"
      />
    </SettingsFieldSection>
  </div>
</template>
