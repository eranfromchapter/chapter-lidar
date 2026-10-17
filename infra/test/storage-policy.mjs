#!/usr/bin/env node
// Checks that the compiled infrastructure template protects capture originals:
// blob versioning, soft delete, and a time-based immutability policy on the `originals`
// container, plus the storage account hardening (HTTPS only, TLS 1.2, no public blob access,
// no shared key access). It also checks the retention days set by both parameter files.
//
// Usage:
//   node infra/test/storage-policy.mjs
//       Compiles infra/main.bicep and both parameter files with the pinned azure-cli Docker
//       image (falls back to a local `az` when Docker is missing).
//   node infra/test/storage-policy.mjs <compiled-main.json> [<staging.parameters.json> <production.parameters.json>]
//       Checks already-built ARM JSON instead. Parameter checks run only when both parameter
//       JSON files are given.
//
// Compiling the parameter files reads CAPTURE_ADMIN_GROUP_OBJECT_ID and CAPTURE_ADMIN_GROUP_NAME.
// When they are not set, this script passes an all-zero object ID and the name "compile-check"
// for the compile only; nothing is deployed.
//
// Exits 0 when every check passes, 1 when a check fails, 2 when compiling fails.

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const AZ_IMAGE = "mcr.microsoft.com/azure-cli:2.67.0";
const ORIGINALS = "originals";
const SEVEN_YEARS_DAYS = 7 * 365;
const SPLIT = "@@@CAPTURE-SPLIT@@@";
const COMPILE_ONLY_OBJECT_ID = "00000000-0000-0000-0000-000000000000";
const COMPILE_ONLY_GROUP_NAME = "compile-check";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

function hasCommand(cmd) {
  const probe = spawnSync(cmd, ["--version"], { stdio: "ignore" });
  return probe.status === 0;
}

function compileEnv() {
  return {
    CAPTURE_ADMIN_GROUP_OBJECT_ID:
      process.env.CAPTURE_ADMIN_GROUP_OBJECT_ID || COMPILE_ONLY_OBJECT_ID,
    CAPTURE_ADMIN_GROUP_NAME: process.env.CAPTURE_ADMIN_GROUP_NAME || COMPILE_ONLY_GROUP_NAME,
  };
}

const COMPILE_SCRIPT = [
  "set -e",
  "az bicep build --file infra/main.bicep --stdout",
  `echo '${SPLIT}'`,
  "az bicep build-params --file infra/params/staging.bicepparam --stdout",
  `echo '${SPLIT}'`,
  "az bicep build-params --file infra/params/production.bicepparam --stdout",
].join("\n");

/** Compiles with Docker (pinned image) or a local az. Returns the three raw outputs. */
function compileAll() {
  const env = compileEnv();
  let result;
  if (hasCommand("docker")) {
    const args = ["run", "--rm", "-v", `${repoRoot}:/w:ro`, "-w", "/w"];
    for (const [key, value] of Object.entries(env)) {
      args.push("-e", `${key}=${value}`);
    }
    // Hosts behind a TLS-inspecting proxy expose their CA bundle through one of these variables.
    // Pass it through so the container can download the Bicep CLI. Unset on normal CI runners.
    const caFile = [process.env.SSL_CERT_FILE, process.env.REQUESTS_CA_BUNDLE].find(
      (path) => path && existsSync(path),
    );
    if (caFile) {
      args.push("-v", `${caFile}:/etc/capture-host-ca.pem:ro`);
      args.push("-e", "SSL_CERT_FILE=/etc/capture-host-ca.pem");
      args.push("-e", "REQUESTS_CA_BUNDLE=/etc/capture-host-ca.pem");
    }
    args.push(AZ_IMAGE, "sh", "-c", COMPILE_SCRIPT);
    console.log(`compile: docker ${AZ_IMAGE} (az bicep build, build-params x2)`);
    result = spawnSync("docker", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  } else if (hasCommand("az")) {
    console.log("compile: local az (docker not found)");
    result = spawnSync("sh", ["-c", COMPILE_SCRIPT], {
      cwd: repoRoot,
      env: { ...process.env, ...env },
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
  } else {
    console.error("FAIL compile: neither docker nor az is available");
    process.exit(2);
  }
  if (result.status !== 0) {
    console.error(result.stdout ?? "");
    console.error(result.stderr ?? "");
    console.error(`FAIL compile: exit code ${result.status}`);
    process.exit(2);
  }
  const parts = result.stdout.split(SPLIT);
  if (parts.length !== 3) {
    console.error("FAIL compile: unexpected output shape");
    process.exit(2);
  }
  return parts;
}

/** `az bicep build-params --stdout` prints {parametersJson: "<json string>", ...}. */
function parseParams(raw) {
  const outer = JSON.parse(raw);
  return typeof outer.parametersJson === "string" ? JSON.parse(outer.parametersJson) : outer;
}

function readJson(path) {
  return JSON.parse(readFileSync(resolve(path), "utf8"));
}

let template;
let stagingParams = null;
let productionParams = null;

const cliArgs = process.argv.slice(2);
if (cliArgs.length > 0) {
  template = readJson(cliArgs[0]);
  console.log(`template: ${cliArgs[0]}`);
  if (cliArgs.length >= 3) {
    stagingParams = parseParams(readFileSync(resolve(cliArgs[1]), "utf8"));
    productionParams = parseParams(readFileSync(resolve(cliArgs[2]), "utf8"));
  }
} else {
  const [main, staging, production] = compileAll();
  template = JSON.parse(main);
  stagingParams = parseParams(staging);
  productionParams = parseParams(production);
  console.log(`template: ${join("infra", "main.bicep")} (compiled)`);
}

/** Yields every resource in the template, including nested module deployments. */
function* allResources(tpl, path = "main") {
  const list = Array.isArray(tpl.resources) ? tpl.resources : Object.values(tpl.resources ?? {});
  for (const resource of list) {
    yield { resource, path, template: tpl };
    if (resource.type === "Microsoft.Resources/deployments" && resource.properties?.template) {
      yield* allResources(resource.properties.template, `${path}/${resource.name}`);
    }
    if (Array.isArray(resource.resources)) {
      yield* allResources({ resources: resource.resources }, path);
    }
  }
}

const resources = [...allResources(template)];
const ofType = (type) => resources.filter((entry) => entry.resource.type === type);

/** True when a compiled resource name (literal or ARM expression) ends in the given segments. */
function nameEndsWith(name, ...segments) {
  if (typeof name !== "string") return false;
  const literal = segments.join("/");
  if (name === literal || name.endsWith(`/${literal}`)) return true;
  // Bicep parent syntax compiles to [format('{0}/{1}/...', parameters(...), 'default', 'originals')].
  const quoted = segments.map((segment) => `'${segment}'`).join(", ");
  return name.includes(quoted);
}

let failures = 0;
function check(label, ok, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${detail ? ` (${detail})` : ""}`);
  if (!ok) failures += 1;
}

// Storage account hardening.
const accounts = ofType("Microsoft.Storage/storageAccounts");
check("one storage account is defined", accounts.length === 1, `found ${accounts.length}`);
const account = accounts[0]?.resource;
const accountProps = account?.properties ?? {};
check("storage account kind is StorageV2", account?.kind === "StorageV2", String(account?.kind));
check("HTTPS only", accountProps.supportsHttpsTrafficOnly === true);
check("minimum TLS version is TLS1_2", accountProps.minimumTlsVersion === "TLS1_2");
check("public blob access disabled", accountProps.allowBlobPublicAccess === false);
check("shared key access disabled", accountProps.allowSharedKeyAccess === false);

// Blob service: versioning and soft delete.
const blobServices = ofType("Microsoft.Storage/storageAccounts/blobServices");
check("one blob service is defined", blobServices.length === 1, `found ${blobServices.length}`);
const blobProps = blobServices[0]?.resource.properties ?? {};
check("blob versioning enabled", blobProps.isVersioningEnabled === true);
check("blob soft delete enabled", blobProps.deleteRetentionPolicy?.enabled === true);
check(
  "permanent delete of soft-deleted blobs not allowed",
  blobProps.deleteRetentionPolicy?.allowPermanentDelete !== true,
);
check("container soft delete enabled", blobProps.containerDeleteRetentionPolicy?.enabled === true);

// The originals container and its immutability policy.
const originals = ofType("Microsoft.Storage/storageAccounts/blobServices/containers").filter(
  (entry) => nameEndsWith(entry.resource.name, "default", ORIGINALS),
);
check(`container "${ORIGINALS}" is defined`, originals.length === 1, `found ${originals.length}`);
const containerProps = originals[0]?.resource.properties ?? {};
check(`"${ORIGINALS}" is private`, containerProps.publicAccess === "None");
check(
  `"${ORIGINALS}" has version-level immutability support`,
  containerProps.immutableStorageWithVersioning?.enabled === true,
);

const policies = ofType(
  "Microsoft.Storage/storageAccounts/blobServices/containers/immutabilityPolicies",
).filter((entry) => nameEndsWith(entry.resource.name, ORIGINALS, "default"));
check(
  `"${ORIGINALS}" has a time-based immutability policy`,
  policies.length === 1,
  `found ${policies.length}`,
);
const policy = policies[0];
const period = policy?.resource.properties?.immutabilityPeriodSinceCreationInDays;
if (typeof period === "number") {
  check("retention period is at least 1 day", period >= 1, `${period} days`);
} else {
  const match = typeof period === "string" ? /^\[parameters\('([^']+)'\)\]$/.exec(period) : null;
  const retentionParamName = match?.[1] ?? null;
  const definition = retentionParamName ? policy.template.parameters?.[retentionParamName] : null;
  check(
    "retention period comes from an int parameter with minValue >= 1",
    definition?.type === "int" && Number(definition.minValue) >= 1,
    retentionParamName ?? String(period),
  );
}
check(
  "protected append writes disabled",
  policy?.resource.properties?.allowProtectedAppendWrites === false,
);

// Retention set by the parameter files.
if (stagingParams && productionParams) {
  const days = (params) => params.parameters?.originalsRetentionDays?.value;
  const staging = days(stagingParams);
  const production = days(productionParams);
  check(
    "staging originalsRetentionDays is a positive integer",
    Number.isInteger(staging) && staging >= 1,
    String(staging),
  );
  check(
    `production originalsRetentionDays is at least 7 years (${SEVEN_YEARS_DAYS} days)`,
    Number.isInteger(production) && production >= SEVEN_YEARS_DAYS,
    String(production),
  );
} else {
  console.log("SKIP parameter file checks (no parameter JSON given)");
}

if (failures > 0) {
  console.error(`${failures} check(s) failed`);
  process.exit(1);
}
console.log("all storage policy checks passed");
