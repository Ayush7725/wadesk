import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// WaDesk: links to Chatwoot's sites must not reach clients. New ones usually arrive in monthly upstream syncs, so this
// fails until each is removed or hidden on branded installations and listed here with how it is hidden.
const ALLOWED = {
  // Replaced at runtime by TERMS_URL / PRIVACY_URL
  'v3/views/auth/signup/components/Signup/Form.vue': 'swapped for own links',
  // showOnCustomBrandedInstance: false
  'dashboard/components-next/sidebar/SidebarProfileMenu.vue': 'custom brand',
  // Rendered only when !isACustomBrandedInstance
  'dashboard/components-next/sidebar/SidebarChangelogCard.vue': 'custom brand',
  'dashboard/routes/dashboard/settings/inbox/settingsPage/ConfigurationPage.vue':
    'custom brand',
  'dashboard/routes/dashboard/settings/inbox/settingsPage/WhatsappBusinessManagementToken.vue':
    'custom brand',
  'dashboard/routes/dashboard/settings/inbox/components/WhatsappManualMigrationBanner.vue':
    'custom brand',
  'dashboard/routes/dashboard/settings/inbox/components/WhatsappManualMigrationDialog.vue':
    'custom brand',
  // BaseSettingsHeader wraps these in CustomBrandPolicyWrapper; QuickLinks renders only on Chatwoot Cloud
  'dashboard/helper/featureHelper.js': 'custom brand',
  // HELP_CENTER_DOCS_URL: Chatwoot Cloud only; TESTIMONIAL_URL: only when the name is Chatwoot
  'dashboard/constants/globals.js': 'cloud only',
  // SidebarChangelogCard only
  'shared/constants/links.js': 'custom brand',
  // learn-more-url: FeatureSpotlight hides the link on custom brands
  'dashboard/components-next/captain/pageComponents/emptyStates/AssistantPageEmptyState.vue':
    'custom brand',
  'dashboard/components-next/captain/pageComponents/emptyStates/DocumentPageEmptyState.vue':
    'custom brand',
  'dashboard/components-next/captain/pageComponents/emptyStates/CustomToolsPageEmptyState.vue':
    'custom brand',
  'dashboard/components-next/captain/pageComponents/emptyStates/ResponsePageEmptyState.vue':
    'custom brand',
  'dashboard/routes/dashboard/captain/assistants/Index.vue': 'custom brand',
  'dashboard/routes/dashboard/captain/documents/Index.vue': 'custom brand',
  'dashboard/routes/dashboard/captain/responses/Index.vue': 'custom brand',
};

const ROOT = join(process.cwd(), 'app/javascript');
const NOT_SHIPPED =
  /(\.spec\.|\.story\.|\/specs?\/|\/stor(y|ies)\/|\/fixtures)/;
const TEMPLATES_ONLY_IN_STORIES =
  'dashboard/components-next/template-preview/templates/twilio-templates.js';

const sourceFiles = () =>
  readdirSync(ROOT, { recursive: true })
    .filter(file => /\.(vue|js|ts)$/.test(file))
    .filter(file => !NOT_SHIPPED.test(`/${file}`))
    .filter(file => file !== TEMPLATES_ONLY_IN_STORIES);

describe('links to Chatwoot sites in shipped code', () => {
  it('are all removed or hidden on branded installations', () => {
    const found = sourceFiles().filter(file =>
      /(www|status|docs)\.chatwoot\.com|chwt\.app/.test(
        readFileSync(join(ROOT, file), 'utf8')
      )
    );

    expect(found.filter(file => !ALLOWED[file])).toEqual([]);
  });

  it('has no stale entries in the allow-list', () => {
    const stale = Object.keys(ALLOWED).filter(
      file =>
        !/chatwoot\.com|chwt\.app/.test(readFileSync(join(ROOT, file), 'utf8'))
    );

    expect(stale).toEqual([]);
  });
});
