const url = process.env.WADESK_ENGINE_DATABASE_URL;
if (!url) throw new Error('Tests need WADESK_ENGINE_DATABASE_URL (use `bin/wadesk-dev engine test`)');

export const databaseUrl: string = url;
export const silent = (): void => undefined;
