// End-to-end tests of the review screen (web-review §12.4): `next build && next start` with the
// test settings, against the local station of e2e/mock-station.ts (the component tests' fake
// station over HTTP, with the drawn scenario). Chromium only, one worker (the tests switch the
// station's scenario). Screenshots of every page at 1440 and 390 px wide go to
// E2E_SCREENSHOTS (default test-results/e2e-screenshots).
//
//   npm run e2e --workspace web
//
// E2E_WEB_PORT / E2E_STATION_PORT move the two servers; E2E_SKIP_BUILD=1 reuses the last build.

import { defineConfig, devices } from "@playwright/test";
import { TEST_ENV } from "./test/support/tokens";

const WEB_PORT = Number(process.env.E2E_WEB_PORT ?? "3916");
const STATION_PORT = Number(process.env.E2E_STATION_PORT ?? "3917");

export const E2E_WEB_URL = `http://127.0.0.1:${WEB_PORT}`;
export const E2E_STATION_URL = `http://127.0.0.1:${STATION_PORT}`;

const build = process.env.E2E_SKIP_BUILD === "1" ? "" : "next build && ";

export default defineConfig({
  testDir: "./e2e",
  outputDir: process.env.E2E_OUTPUT ?? "test-results/e2e",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 60_000,
  reporter: [["list"]],
  use: {
    baseURL: E2E_WEB_URL,
    viewport: { width: 1440, height: 900 },
    locale: "en-US",
    timezoneId: "America/New_York",
    trace: "off",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } },
    },
  ],
  webServer: [
    {
      command: "node --import tsx e2e/mock-station.ts",
      url: `${E2E_STATION_URL}/health`,
      reuseExistingServer: false,
      timeout: 60_000,
      env: {
        E2E_STATION_PORT: String(STATION_PORT),
        TSX_TSCONFIG_PATH: "e2e/tsconfig.json",
        CHAPTER_REPO_ROOT: new URL("..", import.meta.url).pathname,
      },
    },
    {
      command: `${build}next start -p ${WEB_PORT} -H 127.0.0.1`,
      url: `${E2E_WEB_URL}/sign-in`,
      reuseExistingServer: false,
      timeout: 300_000,
      env: {
        ...TEST_ENV,
        STATION_API_URL: E2E_STATION_URL,
        AUTH_TRUST_HOST: "true",
        HUB_APP_URL: "https://hub.example",
        HUB_FILES_URL_TEMPLATE: "https://hub.example/deals/{dealId}/files?folder={folder}",
        INTAKE_GUIDE_URL: "https://hub.example/guides/file-intake-r01",
        NEXT_TELEMETRY_DISABLED: "1",
      },
    },
  ],
});
