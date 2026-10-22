# Station worker image. Build context: the repository root (the worker is an npm workspace and
# depends on the @chapter/capture-contract, @chapter/station-checks and @chapter/station-hub
# workspaces):
#
#   docker build -f station/worker/Dockerfile -t chapter/station-worker .
#
# Only the files named in COPY are sent to the builder; the host's node_modules and build
# output are never copied.
#
# Behind a TLS-intercepting proxy, pass its CA certificate as the optional build secret
# "build_ca" (--secret id=build_ca,src=<ca.pem>); it is used by npm ci only and is not stored
# in the image.

ARG NODE_IMAGE=node:22.23.3-bookworm-slim

# ---- build: compile contract -> checks -> hub -> worker -----------------------------------
FROM ${NODE_IMAGE} AS build
WORKDIR /repo
ENV npm_config_audit=false npm_config_fund=false npm_config_update_notifier=false
COPY package.json package-lock.json ./
COPY contract/ts/package.json contract/ts/
COPY station/checks/package.json station/checks/
COPY station/hub/package.json station/hub/
COPY station/worker/package.json station/worker/
# npm runs a linked workspace's "prepare" even with --ignore-scripts; the contract package is
# built explicitly below instead.
RUN npm pkg delete scripts.prepare --workspace @chapter/capture-contract
RUN --mount=type=secret,id=build_ca,required=false \
    if [ -s /run/secrets/build_ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/build_ca; fi; \
    npm ci --ignore-scripts --include-workspace-root=false \
      --workspace @chapter/capture-contract --workspace @chapter/station-checks \
      --workspace @chapter/station-hub --workspace @chapter/station-worker
COPY tsconfig.base.json ./
COPY contract/schema contract/schema
COPY contract/ts/tsconfig.json contract/ts/tsconfig.build.json contract/ts/
COPY contract/ts/src contract/ts/src
RUN npm run build --workspace @chapter/capture-contract
COPY station/checks/tsconfig.json station/checks/tsconfig.build.json station/checks/
COPY station/checks/src station/checks/src
RUN npm run build --workspace @chapter/station-checks
COPY station/hub/tsconfig.json station/hub/tsconfig.build.json station/hub/
COPY station/hub/src station/hub/src
RUN npm run build --workspace @chapter/station-hub
# The spatial report reduces photos with sharp: its prebuilt linux binaries come from the
# optional @img/* packages in package-lock.json (no install script). Fail the build early when
# they are missing.
RUN node -e "require('sharp'); require('heic-decode')"
COPY station/worker/tsconfig.json station/worker/tsconfig.build.json station/worker/
COPY station/worker/src station/worker/src
RUN npm run build --workspace @chapter/station-worker

# ---- deps: production dependencies only -------------------------------------------------
FROM ${NODE_IMAGE} AS deps
WORKDIR /repo
ENV npm_config_audit=false npm_config_fund=false npm_config_update_notifier=false
COPY package.json package-lock.json ./
COPY contract/ts/package.json contract/ts/
COPY station/checks/package.json station/checks/
COPY station/hub/package.json station/hub/
COPY station/worker/package.json station/worker/
RUN npm pkg delete scripts.prepare --workspace @chapter/capture-contract
RUN --mount=type=secret,id=build_ca,required=false \
    if [ -s /run/secrets/build_ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/build_ca; fi; \
    npm ci --omit=dev --ignore-scripts --include-workspace-root=false \
      --workspace @chapter/capture-contract --workspace @chapter/station-checks \
      --workspace @chapter/station-hub --workspace @chapter/station-worker \
  && npm cache clean --force \
  && node -e "require('sharp')"

# ---- runtime ------------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS runtime
ARG STATION_VERSION
ENV NODE_ENV=production \
    STATION_VERSION=${STATION_VERSION}
WORKDIR /app
# Application files stay owned by root and read-only for the service user.
COPY --from=deps /repo /app
COPY --from=build /repo/contract/ts/dist contract/ts/dist
COPY contract/schema contract/schema
COPY --from=build /repo/station/checks/dist station/checks/dist
COPY --from=build /repo/station/hub/dist station/hub/dist
COPY --from=build /repo/station/worker/dist station/worker/dist
USER node
WORKDIR /app/station/worker
# No ingress and no health endpoint: the worker only polls the Postgres job queue.
CMD ["node", "dist/main.js"]
