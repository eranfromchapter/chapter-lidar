// Helpers of the end-to-end tests: a signed-in session cookie, the local station's scenario,
// and full-page screenshots at the two widths the review screen is checked at.

import { mkdirSync } from "node:fs";
import { join } from "node:path";
import type { APIRequestContext, BrowserContext, Page } from "@playwright/test";
import type { StationRole } from "../lib/roles";
import { SESSION_COOKIE, sessionCookie } from "../test/support/tokens";

const STATION_PORT = Number(process.env.E2E_STATION_PORT ?? "3917");
export const STATION_URL = `http://127.0.0.1:${STATION_PORT}`;

/** Where screenshots go (E2E_SCREENSHOTS, else test-results/e2e-screenshots). */
export const SCREENSHOT_DIR = process.env.E2E_SCREENSHOTS ?? "test-results/e2e-screenshots";

/** The widths every page is captured at: the drawing (1440) and a phone (390). */
export const WIDTHS = [1440, 390] as const;

/** Signs the browser context in as a user with these station roles (an Auth.js session cookie). */
export async function signIn(
  context: BrowserContext,
  roles: StationRole[],
  name = "Dana BIM",
): Promise<void> {
  const value = await sessionCookie({ roles, name });
  await context.addCookies([
    {
      name: SESSION_COOKIE,
      value,
      domain: "127.0.0.1",
      path: "/",
      httpOnly: true,
      sameSite: "Lax",
    },
  ]);
}

export interface ScenarioControl {
  readonly scenario?: "drawn" | "empty" | "states";
  readonly reportReady?: boolean;
  readonly failWith?: number;
}

/** Switches the local station to a scenario (fresh data each time). */
export async function useScenario(
  request: APIRequestContext,
  control: ScenarioControl = {},
): Promise<void> {
  const response = await request.post(`${STATION_URL}/__control`, { data: control });
  if (!response.ok()) {
    throw new Error(`station control answered ${response.status()}`);
  }
}

/** Waits until the self-hosted fonts are in use and the page has settled. */
export async function settle(page: Page): Promise<void> {
  await page.waitForLoadState("networkidle");
  await page.evaluate(async () => {
    await document.fonts.ready;
  });
}

/**
 * Full-page screenshots of the current URL at 1440 and 390 px wide, named
 * "{name}-1440.png" and "{name}-390.png". The viewport is restored to 1440 afterwards.
 */
export async function screenshots(page: Page, name: string): Promise<void> {
  mkdirSync(SCREENSHOT_DIR, { recursive: true });
  for (const width of WIDTHS) {
    await page.setViewportSize({ width, height: 900 });
    await page.reload();
    await settle(page);
    await page.screenshot({ path: join(SCREENSHOT_DIR, `${name}-${width}.png`), fullPage: true });
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    if (overflow > 0) {
      throw new Error(`${name} at ${width} px scrolls sideways by ${overflow} px`);
    }
    if (width === 1440) {
      // As drawn, tables fit their cards at 1440 px; they scroll inside the card only on phones.
      const scrolling = await page.evaluate(() =>
        [...document.querySelectorAll(".hub-card__scroll")]
          .filter((element) => element.scrollWidth > element.clientWidth + 1)
          .map((element) => element.closest("section")?.getAttribute("aria-label") ?? "table"),
      );
      if (scrolling.length > 0) {
        throw new Error(`${name} at 1440 px: tables scroll sideways: ${scrolling.join(", ")}`);
      }
    }
  }
  await page.setViewportSize({ width: 1440, height: 900 });
}
