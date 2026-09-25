import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globalSetup: ['test/support/globalSetup.ts'],
    // Files share one test database; the migration round-trip must not overlap other files.
    fileParallelism: false,
  },
});
