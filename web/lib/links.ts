// Optional links to the HUB and the intake guide (web-review §9.3, addendum D6). Read from the
// server environment at request time; never required: an unset or invalid value hides the link
// (the review screen must not fail closed over a link). An invalid value is reported once per
// variable with console.warn, naming the variable, never the value.
//
//   HUB_APP_URL             https://hub.hellochapter.com                     topbar "Open the HUB"
//   HUB_FILES_URL_TEMPLATE  https://…/deals/{dealId}/files?folder={folder}    Station card HUB link
//   INTAKE_GUIDE_URL        https://… (the File Intake Guide)                 sidebar "Intake guide"
//
// The project page's "Open in the HUB" uses the station's links.hub (HUB_WEB_DEAL_URL_TEMPLATE
// at the station), not a web variable.

import type { Env } from "./config";

export const LINK_ENV = ["HUB_APP_URL", "HUB_FILES_URL_TEMPLATE", "INTAKE_GUIDE_URL"] as const;
export type LinkEnvName = (typeof LINK_ENV)[number];

const warned = new Set<LinkEnvName>();

function warnOnce(name: LinkEnvName, why: string): void {
  if (!warned.has(name)) {
    warned.add(name);
    console.warn(`[links] ${name} ignored: ${why}`);
  }
}

/** Forgets which variables were reported (tests). */
export function resetLinkWarnings(): void {
  warned.clear();
}

function raw(env: Env, name: LinkEnvName): string | undefined {
  const value = env[name]?.trim();
  return value === undefined || value.length === 0 ? undefined : value;
}

function httpsUrl(value: string): URL | undefined {
  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url : undefined;
  } catch {
    return undefined;
  }
}

function plainLink(env: Env, name: LinkEnvName): string | null {
  const value = raw(env, name);
  if (value === undefined) {
    return null;
  }
  const url = httpsUrl(value);
  if (url === undefined) {
    warnOnce(name, "not an https URL");
    return null;
  }
  return url.toString();
}

/** "Open the HUB" in the topbar; null hides the button. */
export function hubAppUrl(env: Env = process.env): string | null {
  return plainLink(env, "HUB_APP_URL");
}

/** "Intake guide" in the sidebar; null hides the item. */
export function intakeGuideUrl(env: Env = process.env): string | null {
  return plainLink(env, "INTAKE_GUIDE_URL");
}

/**
 * The HUB Files folder of a published revision ("HUB › Files › Capture › r1 →"): the template
 * with {dealId} and {folder} (publication.hubFolder) URL-encoded; null hides the link.
 */
export function hubFilesUrl(dealId: string, folder: string, env: Env = process.env): string | null {
  const template = raw(env, "HUB_FILES_URL_TEMPLATE");
  if (template === undefined) {
    return null;
  }
  if (!template.includes("{dealId}") || !template.includes("{folder}")) {
    warnOnce("HUB_FILES_URL_TEMPLATE", "it must contain {dealId} and {folder}");
    return null;
  }
  const filled = template
    .replaceAll("{dealId}", encodeURIComponent(dealId))
    .replaceAll("{folder}", encodeURIComponent(folder));
  const url = httpsUrl(filled);
  if (url === undefined) {
    warnOnce("HUB_FILES_URL_TEMPLATE", "not an https URL");
    return null;
  }
  return url.toString();
}

/** A station-provided link (links.hub): followed only when it is https. */
export function safeExternalLink(value: string | undefined): string | null {
  if (value === undefined) {
    return null;
  }
  return httpsUrl(value)?.toString() ?? null;
}
