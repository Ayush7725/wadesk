import { mount } from '@vue/test-utils';
import { computed } from 'vue';
import FeatureSpotlight from 'dashboard/components-next/feature-spotlight/FeatureSpotlight.vue';
import WhatsappManualMigrationBanner from 'dashboard/routes/dashboard/settings/inbox/components/WhatsappManualMigrationBanner.vue';

// WaDesk: guide links lead to Chatwoot's site, so branded installations do not show them.
const brand = vi.hoisted(() => ({ custom: true }));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => computed(() => brand.custom),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const spotlightHasLearnMore = () =>
  mount(FeatureSpotlight, {
    props: { title: 'Title', learnMoreUrl: 'https://chwt.app/guide' },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Button: {
          props: ['label'],
          template: '<button>{{ label }}</button>',
        },
      },
    },
  }).findAll('button').length > 0;

const migrationBannerHasGuide = () =>
  mount(WhatsappManualMigrationBanner, {
    global: {
      stubs: { Banner: { template: '<div><slot /></div>' }, Icon: true },
    },
  })
    .find('a')
    .exists();

describe('guide links', () => {
  it.each([
    ['the feature spotlight', spotlightHasLearnMore],
    ['the WhatsApp migration banner', migrationBannerHasGuide],
  ])('are hidden in %s on a branded installation', (_, hasLink) => {
    brand.custom = true;
    expect(hasLink()).toBe(false);

    brand.custom = false;
    expect(hasLink()).toBe(true);
  });
});
