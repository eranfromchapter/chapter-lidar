// Removes secrets from values before they are logged or written to audit_log.
//
// Redacted: values under secret-looking keys (token, password, secret, signature, sas,
// authorization, cookie, api key, account key, connection string, credential), bearer
// strings, JWT-shaped strings, the query string of URLs carrying SAS or token parameters, and
// key/password parts of connection strings.

export const REDACTED = "[redacted]";

const SECRET_KEYS = new Set([
  "authorization",
  "cookie",
  "setcookie",
  "password",
  "passwd",
  "pwd",
  "secret",
  "token",
  "sig",
  "sas",
  "signature",
  "credential",
  "credentials",
  "privatekey",
]);
const SECRET_KEY_SUFFIXES = [
  "token",
  "secret",
  "password",
  "signature",
  "apikey",
  "accountkey",
  "connectionstring",
  "sastoken",
  "sasurl",
  "credential",
  "credentials",
  "privatekey",
];

// JWS compact tokens: the header is base64url JSON, so it starts with "eyJ".
const JWT_PATTERN = /eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*/g;
const BEARER_PATTERN = /\bBearer\s+\S+/gi;
const CONNECTION_SECRET_PATTERN =
  /\b(AccountKey|SharedAccessSignature|SharedAccessKey|Password|Pwd)=[^;]*/gi;
const SECRET_QUERY_PARAMS = new Set([
  "sig",
  "signature",
  "token",
  "access_token",
  "id_token",
  "refresh_token",
  "code",
  "client_secret",
  "password",
  "skoid",
]);
const MAX_DEPTH = 12;

export function isSecretKey(key: string): boolean {
  const normalized = key.toLowerCase().replace(/[^a-z0-9]/g, "");
  return (
    SECRET_KEYS.has(normalized) || SECRET_KEY_SUFFIXES.some((suffix) => normalized.endsWith(suffix))
  );
}

/** Strips the query string of URLs whose query carries a SAS signature or a token. */
function redactUrl(value: string): string {
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) {
    return value;
  }
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return value;
  }
  let secret = url.username !== "" || url.password !== "" || /token|code=/i.test(url.hash);
  for (const name of url.searchParams.keys()) {
    if (SECRET_QUERY_PARAMS.has(name.toLowerCase())) {
      secret = true;
    }
  }
  if (!secret) {
    return value;
  }
  url.username = "";
  url.password = "";
  const query = url.search === "" ? "" : `?${REDACTED}`;
  // Not url.origin: it is "null" for non-special schemes such as postgres:.
  return `${url.protocol}//${url.host}${url.pathname}${query}`;
}

export function redactString(value: string): string {
  return redactUrl(value)
    .replace(JWT_PATTERN, REDACTED)
    .replace(BEARER_PATTERN, `Bearer ${REDACTED}`)
    .replace(CONNECTION_SECRET_PATTERN, (_match, name: string) => `${name}=${REDACTED}`);
}

/** Deep copy of value with secrets replaced by "[redacted]". */
export function redactSecrets(value: unknown, depth = 0): unknown {
  if (typeof value === "string") {
    return redactString(value);
  }
  if (value === null || typeof value !== "object") {
    return value;
  }
  if (depth >= MAX_DEPTH) {
    return REDACTED;
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (Array.isArray(value)) {
    return value.map((item) => redactSecrets(item, depth + 1));
  }
  if (value instanceof Error) {
    return { name: value.name, message: redactString(value.message) };
  }
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) {
    out[key] = isSecretKey(key) ? REDACTED : redactSecrets(item, depth + 1);
  }
  return out;
}
