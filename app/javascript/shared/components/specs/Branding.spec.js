import { mount } from '@vue/test-utils';

// WaDesk: installations ship without a widget brand URL, so "Powered by" is shown without a link.
vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: text => text }),
}));

const mountBranding = async widgetBrandURL => {
  vi.resetModules();
  window.globalConfig = {
    BRAND_NAME: 'WaDesk',
    LOGO_THUMBNAIL: '/brand-assets/logo_thumbnail.svg',
    WIDGET_BRAND_URL: widgetBrandURL,
  };
  const { default: Branding } = await import('../Branding.vue');
  return mount(Branding, {
    global: {
      mocks: {
        $t: key => key,
        $store: { getters: { 'appConfig/getReferrerHost': 'shop.example' } },
      },
    },
  });
};

describe('Branding', () => {
  afterEach(() => {
    delete window.globalConfig;
  });

  it('shows "Powered by" without a link when no brand URL is set', async () => {
    const wrapper = await mountBranding('');

    expect(wrapper.text()).toContain('POWERED_BY');
    expect(wrapper.find('a').exists()).toBe(false);
  });

  it('links "Powered by" to the brand URL with tracking parameters', async () => {
    const wrapper = await mountBranding('https://wadesk.example');
    const link = wrapper.find('a');

    expect(link.attributes('href')).toBe(
      'https://wadesk.example/?utm_source=shop.example&utm_medium=widget&utm_campaign=branding'
    );
    expect(link.attributes('target')).toBe('_blank');
  });
});
