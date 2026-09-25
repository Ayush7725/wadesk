FROM node:24.13.0-bookworm-slim AS build
WORKDIR /engine
RUN npm install -g pnpm@10.2.0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN pnpm build && pnpm prune --prod

FROM node:24.13.0-bookworm-slim
ENV NODE_ENV=production
WORKDIR /engine
COPY --from=build /engine/node_modules ./node_modules
COPY --from=build /engine/dist ./dist
COPY package.json ./
USER node
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=3s CMD node -e "fetch('http://127.0.0.1:4000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/server.js"]
