// Microsoft Entra ID sign-in and role checks for every station route.
//
// - Bearer tokens are Entra v2.0 access tokens, RS256, verified against the tenant JWKS, with
//   the configured issuer, audience and tenant id (`tid`).
// - Roles come from the `roles` claim (app roles capture, bim, admin).
// - Every route must declare its roles in `config.roles`; only /health may set
//   `config.public: true`. A route that declares neither (or declares unknown roles) makes the
//   server fail at startup, so no route can be added without an access rule.
// - The check runs in a root onRequest hook, before body parsing and before any hook of a
//   route plugin: no token -> 401, valid token without a listed role -> 403.
// - Tokens are never logged; only the failure reason is.

import type { FastifyInstance, FastifyReply, FastifyRequest, RouteOptions } from "fastify";
import fp from "fastify-plugin";
import {
  createRemoteJWKSet,
  errors as joseErrors,
  jwtVerify,
  type JWTPayload,
  type JWTVerifyGetKey,
} from "jose";
import type { StationConfig } from "./config.js";
import "./fastify-types.js";
import { sendProblem } from "./problem.js";

/** Station app roles, as defined on the Entra app registration. */
export const ROLES = ["capture", "bim", "admin"] as const;
export type Role = (typeof ROLES)[number];

/** Paths that may be public (no token). Everything else needs a role. */
export const PUBLIC_PATHS: ReadonlySet<string> = new Set(["/health", "/v1/health"]);

/** The signed-in caller. */
export interface Principal {
  /** "user" for delegated tokens, "service" for app-only tokens (idtyp app). */
  readonly kind: "user" | "service";
  /** Entra object id (`oid`). */
  readonly userId: string;
  /** Display name: `name`, else `preferred_username`, else the object id. */
  readonly name: string;
  readonly tenantId: string;
  /** Known station roles from the `roles` claim. */
  readonly roles: readonly Role[];
}

/** One route's access rule, as recorded at startup. */
export interface RouteAccess {
  readonly method: string;
  readonly url: string;
  readonly public: boolean;
  readonly roles: readonly Role[];
}

export class AuthError extends Error {
  constructor(
    /** Safe, token-free reason for logs. */
    readonly reason: string,
    /** True when the token was present but rejected (adds error="invalid_token"). */
    readonly invalidToken: boolean,
  ) {
    super(reason);
    this.name = "AuthError";
  }
}

export interface TokenVerifierOptions {
  readonly issuer: string;
  readonly audiences: readonly string[];
  readonly tenantId: string;
  readonly clockToleranceSeconds: number;
  readonly getKey: JWTVerifyGetKey;
}

export type TokenVerifier = (token: string) => Promise<Principal>;

const TOKEN_PATTERN = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;

function isRole(value: unknown): value is Role {
  return typeof value === "string" && (ROLES as readonly string[]).includes(value);
}

function stringClaim(payload: JWTPayload, name: string): string | undefined {
  const value = payload[name];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

/** Builds a verifier for Entra v2.0 access tokens. */
export function createTokenVerifier(options: TokenVerifierOptions): TokenVerifier {
  const tenantId = options.tenantId.toLowerCase();
  return async (token) => {
    if (!TOKEN_PATTERN.test(token)) {
      throw new AuthError("malformed token", true);
    }
    let payload: JWTPayload;
    try {
      ({ payload } = await jwtVerify(token, options.getKey, {
        algorithms: ["RS256"],
        issuer: options.issuer,
        audience: [...options.audiences],
        clockTolerance: options.clockToleranceSeconds,
        requiredClaims: ["exp", "iat", "tid", "oid"],
      }));
    } catch (error) {
      throw new AuthError(verifyFailureReason(error), true);
    }
    if (stringClaim(payload, "tid")?.toLowerCase() !== tenantId) {
      throw new AuthError("token tenant does not match", true);
    }
    const userId = stringClaim(payload, "oid");
    if (userId === undefined || userId.length > 128) {
      throw new AuthError("token has no usable oid claim", true);
    }
    const rawRoles = Array.isArray(payload.roles) ? payload.roles : [];
    const roles = ROLES.filter((role) => rawRoles.includes(role));
    const name = (
      stringClaim(payload, "name") ??
      stringClaim(payload, "preferred_username") ??
      userId
    ).slice(0, 200);
    return {
      kind: payload.idtyp === "app" ? "service" : "user",
      userId,
      name,
      tenantId,
      roles,
    };
  };
}

function verifyFailureReason(error: unknown): string {
  if (error instanceof joseErrors.JWTExpired) {
    return "token expired";
  }
  if (error instanceof joseErrors.JWTClaimValidationFailed) {
    return `claim check failed: ${error.claim}`;
  }
  if (error instanceof joseErrors.JWKSNoMatchingKey) {
    return "no matching signing key";
  }
  if (error instanceof joseErrors.JWSSignatureVerificationFailed) {
    return "signature verification failed";
  }
  if (error instanceof joseErrors.JOSEAlgNotAllowed) {
    return "algorithm not allowed";
  }
  if (error instanceof joseErrors.JWKSTimeout || error instanceof joseErrors.JWKSInvalid) {
    return "signing keys unavailable";
  }
  if (error instanceof joseErrors.JOSEError) {
    return `token rejected (${error.code})`;
  }
  return "signing keys unavailable";
}

/** Reads a single `Authorization: Bearer <token>` header. */
export function bearerToken(request: FastifyRequest): string | undefined {
  const header = request.headers.authorization;
  if (typeof header !== "string") {
    return undefined;
  }
  const match = /^Bearer[ ]+(\S+)[ ]*$/i.exec(header);
  return match?.[1];
}

/** Validates a route's access rule. Throws (and so stops startup) when it is missing or wrong. */
export function routeAccess(route: Pick<RouteOptions, "method" | "url" | "config">): RouteAccess {
  const methods = Array.isArray(route.method) ? route.method.join(",") : String(route.method);
  const where = `${methods} ${route.url}`;
  const config = (route.config ?? {}) as { roles?: unknown; public?: unknown };

  if (config.public !== undefined && config.public !== true) {
    throw new Error(`Route ${where}: config.public must be true or omitted.`);
  }
  if (config.public === true) {
    if (config.roles !== undefined) {
      throw new Error(`Route ${where}: a public route cannot also declare roles.`);
    }
    if (!PUBLIC_PATHS.has(route.url ?? "")) {
      throw new Error(
        `Route ${where}: only ${[...PUBLIC_PATHS].join(", ")} may be public; declare config.roles.`,
      );
    }
    return { method: methods, url: route.url ?? "", public: true, roles: [] };
  }

  const roles = config.roles;
  if (!Array.isArray(roles) || roles.length === 0) {
    throw new Error(
      `Route ${where} has no access rule: set config.roles to one or more of ${ROLES.join(", ")}.`,
    );
  }
  const unknown = roles.filter((role) => !isRole(role));
  if (unknown.length > 0) {
    throw new Error(`Route ${where}: unknown roles ${JSON.stringify(unknown)}.`);
  }
  if (new Set(roles).size !== roles.length) {
    throw new Error(`Route ${where}: duplicate roles.`);
  }
  return { method: methods, url: route.url ?? "", public: false, roles: roles as Role[] };
}

/** The signed-in caller of a protected route. Throws if called on a public route. */
export function requirePrincipal(request: FastifyRequest): Principal {
  if (request.principal === null) {
    throw new Error("requirePrincipal called on a request without a verified principal");
  }
  return request.principal;
}

export interface AuthPluginOptions {
  readonly config: StationConfig["auth"];
  /** Signing key source; defaults to the remote JWKS at config.jwksUrl. */
  readonly getKey?: JWTVerifyGetKey;
}

const REALM = 'Bearer realm="chapter-station"';

function unauthorized(reply: FastifyReply, invalidToken: boolean): FastifyReply {
  return sendProblem(reply, 401, "unauthorized", {
    detail: invalidToken
      ? "The bearer token is invalid or expired."
      : "Sign in with Microsoft Entra ID and send the access token as a bearer token.",
    headers: { "WWW-Authenticate": invalidToken ? `${REALM}, error="invalid_token"` : REALM },
  });
}

async function authPlugin(app: FastifyInstance, options: AuthPluginOptions): Promise<void> {
  const verify = createTokenVerifier({
    issuer: options.config.issuer,
    audiences: options.config.audiences,
    tenantId: options.config.tenantId,
    clockToleranceSeconds: options.config.clockToleranceSeconds,
    getKey: options.getKey ?? createRemoteJWKSet(new URL(options.config.jwksUrl)),
  });

  const registry: RouteAccess[] = [];
  app.decorate("routeAccess", registry);
  app.decorateRequest("principal", null);

  app.addHook("onRoute", (route) => {
    registry.push(routeAccess(route));
  });

  app.addHook("onRequest", async (request, reply) => {
    if (request.is404) {
      return;
    }
    const config = request.routeOptions.config as { roles?: readonly Role[]; public?: boolean };
    if (config.public === true) {
      return;
    }
    const required = config.roles ?? [];
    if (required.length === 0) {
      // Unreachable: routeAccess rejects such routes at startup. Fail closed anyway.
      request.log.error("route without access rule reached the auth hook");
      return sendProblem(reply, 500, "internal_error", {
        detail: "The station could not complete the request.",
      });
    }

    const token = bearerToken(request);
    if (token === undefined) {
      request.log.info({ auth: "missing bearer token" }, "unauthorized");
      return unauthorized(reply, request.headers.authorization !== undefined);
    }

    let principal: Principal;
    try {
      principal = await verify(token);
    } catch (error) {
      const reason = error instanceof AuthError ? error.reason : "token verification failed";
      if (reason === "signing keys unavailable") {
        request.log.error({ auth: reason }, "unauthorized: cannot load Entra signing keys");
      } else {
        request.log.info({ auth: reason }, "unauthorized");
      }
      return unauthorized(reply, true);
    }

    if (!principal.roles.some((role) => required.includes(role))) {
      request.log.info({ auth: "missing role", userId: principal.userId, required }, "forbidden");
      return sendProblem(reply, 403, "forbidden", {
        detail: `This operation requires one of the roles: ${required.join(", ")}.`,
      });
    }
    request.principal = principal;
  });
}

/** Entra sign-in, route access rules and the route registry (app.routeAccess). */
export const auth = fp(authPlugin, { name: "station-auth", fastify: "5.x" });
