# WaDesk development toolbox: Ruby + Node + pnpm with the repo mounted at /app.
# Gems and node_modules live in named volumes, so the image stays small and rebuilds are rare.
FROM node:24.13.0-bookworm-slim AS node

FROM ruby:3.4.4-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git curl pkg-config libpq-dev libyaml-dev libvips42 postgresql-client tzdata \
  && rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
  && npm install -g pnpm@10.2.0 \
  && gem install bundler -v 2.5.16

ENV BUNDLE_PATH=/usr/local/bundle \
    NODE_OPTIONS=--openssl-legacy-provider \
    PNPM_HOME=/usr/local/pnpm
WORKDIR /app
