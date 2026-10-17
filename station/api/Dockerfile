# Station API image. Build context: the repository root (the API is an npm workspace and
# depends on the @chapter/capture-contract workspace):
#
#   docker build -f station/api/Dockerfile -t chapter/station-api .
#
# Only the files named in COPY are sent to the builder; the host's node_modules and build
# output are never copied.
#
# Behind a TLS-intercepting proxy, pass its CA certificate as the optional build secret
# "build_ca" (--secret id=build_ca,src=<ca.pem>); it is used by npm ci only and is not stored
# in the image. local-up.sh does this from STATION_BUILD_CA_FILE or NODE_EXTRA_CA_CERTS.

ARG NODE_IMAGE=node:22.23.3-bookworm-slim

# ---- build: compile the contract package and the API -----------------------------------
FROM ${NODE_IMAGE} AS build
WORKDIR /repo
ENV npm_config_audit=false npm_config_fund=false npm_config_update_notifier=false
COPY package.json package-lock.json ./
COPY contract/ts/package.json contract/ts/
COPY station/api/package.json station/api/
# npm runs a linked workspace's "prepare" even with --ignore-scripts; the contract package is
# built explicitly below instead.
RUN npm pkg delete scripts.prepare --workspace @chapter/capture-contract
RUN --mount=type=secret,id=build_ca,required=false \
    if [ -s /run/secrets/build_ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/build_ca; fi; \
    npm ci --ignore-scripts --include-workspace-root=false \
      --workspace @chapter/capture-contract --workspace @chapter/station-api
COPY tsconfig.base.json ./
COPY contract/schema contract/schema
COPY contract/ts/tsconfig.json contract/ts/tsconfig.build.json contract/ts/
COPY contract/ts/src contract/ts/src
RUN npm run build --workspace @chapter/capture-contract
COPY station/api/tsconfig.json station/api/
COPY station/api/scripts/tsconfig.build.json station/api/scripts/
COPY station/api/src station/api/src
RUN npm run build --workspace @chapter/station-api

# ---- deps: production dependencies only -------------------------------------------------
FROM ${NODE_IMAGE} AS deps
WORKDIR /repo
ENV npm_config_audit=false npm_config_fund=false npm_config_update_notifier=false
COPY package.json package-lock.json ./
COPY contract/ts/package.json contract/ts/
COPY station/api/package.json station/api/
RUN npm pkg delete scripts.prepare --workspace @chapter/capture-contract
RUN --mount=type=secret,id=build_ca,required=false \
    if [ -s /run/secrets/build_ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/build_ca; fi; \
    npm ci --omit=dev --ignore-scripts --include-workspace-root=false \
      --workspace @chapter/capture-contract --workspace @chapter/station-api \
  && npm cache clean --force

# ---- runtime ------------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS runtime
ARG STATION_VERSION
ENV NODE_ENV=production \
    PORT=8080 \
    STATION_VERSION=${STATION_VERSION}
WORKDIR /app
# Application files stay owned by root and read-only for the service user.
COPY --from=deps /repo /app
COPY --from=build /repo/contract/ts/dist contract/ts/dist
COPY contract/schema contract/schema
COPY --from=build /repo/station/api/dist station/api/dist
COPY station/db/migrations station/db/migrations
USER node
WORKDIR /app/station/api
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/health').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"]
CMD ["node", "dist/server.js"]
