// Request-time configuration of the review screen.
//
// Nothing here runs at build time: every value is read when a request needs it, so
// `next build` succeeds without secrets. A missing or invalid value fails closed with a
// ConfigError that names the variables (never their values). There is no fallback station,
// user or demo data.

export type Env = Readonly<Record<string, string | undefined>>;

/** Variables the review screen needs at request time. */
export const REQUIRED_ENV = [
  "AUTH_SECRET",
  "AUTH_MICROSOFT_ENTRA_ID_ID",
  "AUTH_MICROSOFT_ENTRA_ID_SECRET",
  "AUTH_MICROSOFT_ENTRA_ID_ISSUER",
  "STATION_API_URL",
  "STATION_API_SCOPE",
] as const;

export type RequiredEnvName = (typeof REQUIRED_ENV)[number];

export class ConfigError extends Error {
  constructor(
    /** Names of the missing or invalid variables. Never their values. */
    readonly problems: readonly string[],
  ) {
    super(`Review screen configuration is incomplete: ${problems.join(", ")}`);
    this.name = "ConfigError";
  }
}

export interface AuthConfig {
  readonly secret: string;
  readonly clientId: string;
  readonly clientSecret: string;
  /** Tenant-specific Entra v2.0 issuer, for example https://login.microsoftonline.com/<tenant>/v2.0 */
  readonly issuer: string;
  /** Scope of the station API, for example api://<station-app-id>/access_as_user */
  readonly stationScope: string;
}

export interface StationConfig {
  /** Station host, without the /v1 base path. */
  readonly apiUrl: string;
}

const MULTI_TENANT_SEGMENTS = new Set(["common", "organizations", "consumers"]);

function value(env: Env, name: RequiredEnvName): string | undefined {
  const raw = env[name];
  if (raw === undefined) {
    return undefined;
  }
  const trimmed = raw.trim();
  return trimmed.length === 0 ? undefined : trimmed;
}

function isLocalHost(hostname: string): boolean {
  return hostname === "localhost" || hostname === "127.0.0.1" || hostname === "[::1]";
}

function issuerProblem(issuer: string): string | undefined {
  let url: URL;
  try {
    url = new URL(issuer);
  } catch {
    return "AUTH_MICROSOFT_ENTRA_ID_ISSUER (not a URL)";
  }
  if (url.protocol !== "https:") {
    return "AUTH_MICROSOFT_ENTRA_ID_ISSUER (must be https)";
  }
  const tenant = url.pathname.split("/").filter((part) => part.length > 0)[0];
  if (tenant === undefined || MULTI_TENANT_SEGMENTS.has(tenant.toLowerCase())) {
    return "AUTH_MICROSOFT_ENTRA_ID_ISSUER (must name the Chapter tenant, not a multi-tenant endpoint)";
  }
  return undefined;
}

function stationUrlProblem(apiUrl: string): string | undefined {
  let url: URL;
  try {
    url = new URL(apiUrl);
  } catch {
    return "STATION_API_URL (not a URL)";
  }
  if (url.protocol === "https:") {
    return undefined;
  }
  if (url.protocol === "http:" && isLocalHost(url.hostname)) {
    return undefined;
  }
  return "STATION_API_URL (must be https, or http on localhost)";
}

/** Names of missing or invalid variables; empty when the configuration is complete. */
export function configProblems(env: Env = process.env): string[] {
  const problems: string[] = [];
  for (const name of REQUIRED_ENV) {
    if (value(env, name) === undefined) {
      problems.push(name);
    }
  }
  const issuer = value(env, "AUTH_MICROSOFT_ENTRA_ID_ISSUER");
  if (issuer !== undefined) {
    const problem = issuerProblem(issuer);
    if (problem !== undefined) {
      problems.push(problem);
    }
  }
  const apiUrl = value(env, "STATION_API_URL");
  if (apiUrl !== undefined) {
    const problem = stationUrlProblem(apiUrl);
    if (problem !== undefined) {
      problems.push(problem);
    }
  }
  return problems;
}

function required(env: Env, name: RequiredEnvName): string {
  const found = value(env, name);
  if (found === undefined) {
    throw new ConfigError([name]);
  }
  return found;
}

/** Sign-in configuration. Throws ConfigError when anything is missing or invalid. */
export function readAuthConfig(env: Env = process.env): AuthConfig {
  const problems = configProblems(env);
  if (problems.length > 0) {
    throw new ConfigError(problems);
  }
  return {
    secret: required(env, "AUTH_SECRET"),
    clientId: required(env, "AUTH_MICROSOFT_ENTRA_ID_ID"),
    clientSecret: required(env, "AUTH_MICROSOFT_ENTRA_ID_SECRET"),
    issuer: required(env, "AUTH_MICROSOFT_ENTRA_ID_ISSUER"),
    stationScope: required(env, "STATION_API_SCOPE"),
  };
}

/** Station API configuration. Throws ConfigError when anything is missing or invalid. */
export function readStationConfig(env: Env = process.env): StationConfig {
  const problems = configProblems(env);
  if (problems.length > 0) {
    throw new ConfigError(problems);
  }
  return { apiUrl: required(env, "STATION_API_URL").replace(/\/+$/, "") };
}

/**
 * Plain page shown when the configuration is incomplete. Names no variable and no value. Shows
 * the Chapter logo and Inter from public/brand, which the proxy serves in every state.
 */
export function configErrorResponse(): Response {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Capture review is not configured</title>
<style>@font-face{font-family:Inter;font-weight:400;font-display:swap;src:url("/brand/inter-400.woff2") format("woff2")}</style></head>
<body style="margin:0;padding:48px;background:#F5EFE6;color:#1F2429;font-family:Inter,'Helvetica Neue',Helvetica,Arial,sans-serif">
<img src="/brand/chapter-logo.svg" width="94" height="34" alt="Chapter Renovation" style="display:block;margin:0 0 32px">
<h1 style="margin:0 0 12px;font-family:Times,'Times New Roman',serif;font-size:34px;font-weight:400">Capture review is not configured</h1>
<p style="margin:0;font-size:17px">Sign-in or the station connection is not set up for this deployment, so no data is shown. Ask a Chapter admin to complete the review screen settings.</p>
</body></html>`;
  return new Response(html, {
    status: 503,
    headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
  });
}

/** Logs which variables are missing (names only) and returns the configuration error page. */
export function failClosed(problems: readonly string[]): Response {
  console.error(`[config] review screen configuration incomplete: ${problems.join(", ")}`);
  return configErrorResponse();
}
