// End-to-end flows of the review screen (web-review §12.4) against the local station: search to
// project to package, tabs, file filters and deep links, saving a decision, downloads through
// short-lived links, the keyboard, and no request leaving the app (no Google fonts).

import { expect, test, type Page } from "@playwright/test";
import { DEALS, IDS } from "../test/support/scenario-ids";
import { settle, signIn, STATION_URL, useScenario } from "./support";

const WEB_ORIGIN = `http://127.0.0.1:${process.env.E2E_WEB_PORT ?? "3916"}`;

test.beforeEach(async ({ request, context }) => {
  await useScenario(request);
  await signIn(context, ["bim"]);
});

/** Every request the page makes, by origin. */
function recordRequests(page: Page): string[] {
  const urls: string[] = [];
  page.on("request", (request) => {
    urls.push(request.url());
  });
  return urls;
}

test("search, then project, then package", async ({ page }) => {
  await page.goto("/");
  const search = page.getByRole("searchbox", { name: "Search projects" });
  await search.fill("West End");
  await search.press("Enter");
  await expect(page).toHaveURL(/\/\?q=West\+End$/);
  await expect(page.locator("tr[data-deal]")).toHaveCount(1);
  await page.getByRole("link", { name: "Open 424 West End Ave, Apt 4K" }).click();
  await expect(page).toHaveURL(new RegExp(`/projects/${DEALS.westEnd}$`));
  await expect(page.getByText("not sealed · on the phone")).toBeVisible();
  await page.getByRole("link", { name: "Open revision 1" }).click();
  await expect(page).toHaveURL(new RegExp(`/packages/${IDS.westEnd1}$`));
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "424 West End Ave, Apt 4K · Revision 1",
  );
  await page.getByRole("link", { name: "424 West End Ave, Apt 4K", exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`/projects/${DEALS.westEnd}$`));
});

test("tabs on the projects and project pages", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("link", { name: /^Ready/ }).click();
  await expect(page).toHaveURL(/\?tab=ready$/);
  await expect(page.locator("tr[data-deal]")).toHaveCount(2);
  await expect(page.getByRole("link", { name: /^Ready/ })).toHaveAttribute("aria-current", "page");
  await page.goto(`/projects/${DEALS.westEnd}`);
  await page
    .getByRole("navigation", { name: "Project" })
    .getByRole("link", { name: /Decision log/ })
    .click();
  await expect(page).toHaveURL(/\?tab=log$/);
  await expect(page.getByRole("heading", { name: "Modeling decision log" })).toBeVisible();
  await page.getByRole("link", { name: "All entries →" }).click();
  await expect(page).toHaveURL(/\?tab=log$/);
});

test("file filters, photo group and Show all", async ({ page }) => {
  await page.goto(`/packages/${IDS.westEnd1}`);
  await settle(page);
  const files = page.getByRole("region", { name: "Files · 33" });
  const rows = files.locator("tr[data-kind]");
  await expect(rows).toHaveCount(8);
  await files.getByRole("button", { name: "Show all 33 files" }).click();
  await expect(rows).toHaveCount(17);
  await files.getByRole("button", { name: "Show photos" }).click();
  await expect(rows).toHaveCount(35);
  await files.getByRole("combobox", { name: "Role" }).selectOption("Mesh GLB");
  await expect(rows).toHaveCount(1);
  await expect(rows.first()).toContainText("Floor 1 / mesh.glb");
  await files.getByRole("combobox", { name: "Role" }).selectOption("all");
  await files.getByRole("searchbox", { name: "Search files" }).fill("photo-0007");
  await expect(rows).toHaveCount(2);
  await files.getByRole("searchbox", { name: "Search files" }).fill("no such file");
  await expect(files.getByText("No files match these filters.")).toBeVisible();
  await files.getByRole("button", { name: "Clear filters" }).click();
  await expect(files.getByRole("searchbox", { name: "Search files" })).toHaveValue("");
});

test("a deep link to a file highlights it and scrolls it into view", async ({ page }) => {
  await page.goto(`/packages/${IDS.westEnd1}`);
  const mesh = await page
    .locator('tr[data-kind="file"]', { hasText: "mesh.glb" })
    .getAttribute("data-path");
  await page.goto(`/packages/${IDS.westEnd1}?file=${encodeURIComponent(mesh ?? "")}`);
  await settle(page);
  const target = page.locator("#file-target");
  await expect(target).toHaveAttribute("aria-current", "true");
  await expect(target).toBeInViewport();
  await expect(target).toHaveCSS("background-color", "rgb(231, 251, 246)");
});

test("the plan preview is streamed through this app", async ({ page }) => {
  await page.goto(`/packages/${IDS.westEnd1}`);
  const image = page.getByRole("img", { name: "Plan of Floor 1" });
  await expect(image).toHaveAttribute("src", /^\/packages\/.+\/files\/preview\?path=/);
  await expect
    .poll(() => image.evaluate((element) => (element as HTMLImageElement).naturalWidth))
    .toBeGreaterThan(0);
});

test("save a decision", async ({ page }) => {
  await page.goto(`/packages/${IDS.westEnd1}#decisions`);
  await settle(page);
  const form = page.getByRole("form", { name: "Log a decision" });
  await form.getByLabel("Element or area").fill("Floor 1 · kitchen east wall");
  const source = form.getByLabel("Source used");
  const value = await source
    .locator("option", { hasText: "Floor 1 / plan.dxf + Distance A (laser)" })
    .getAttribute("value");
  await source.selectOption(value ?? "");
  await form
    .getByLabel("Decision", { exact: true })
    .fill("Modeled as a native Revit wall, 4,520 mm");
  await form
    .getByLabel("Remaining uncertainty and next check")
    .fill("Wall thickness unknown; verify at demolition");
  await form.getByRole("button", { name: "Save decision" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Decision saved." })).toBeVisible();
  const log = page.getByRole("region", { name: "Modeling decision log" });
  await expect(log).toContainText("4 entries");
  await expect(log.getByRole("listitem").last()).toContainText(
    "Floor 1 · kitchen east wall — Modeled as a native Revit wall, 4,520 mm · from Floor 1 / plan.dxf + Distance A (laser)",
  );
});

test("downloads answer 303 to a short-lived link that is never in the page", async ({
  page,
  request,
}) => {
  await useScenario(request, { reportReady: true });
  await page.goto(`/packages/${IDS.westEnd1}`);
  const html = await page.content();
  expect(html).not.toContain("sig=");
  expect(html).not.toContain(STATION_URL);
  const hrefs = await page
    .locator('a[href*="/download"], a[href$="verdict.json"]')
    .evaluateAll((links) => links.map((link) => link.getAttribute("href") ?? ""));
  expect(hrefs.length).toBeGreaterThan(5);
  for (const href of [
    hrefs.find((item) => item.includes("files/download")),
    `/packages/${IDS.westEnd1}/report/download`,
  ]) {
    const response = await page.request.get(href ?? "", { maxRedirects: 0 });
    expect(response.status(), href).toBe(303);
    expect(response.headers()["location"], href).toMatch(new RegExp(`^${STATION_URL}/blob/`));
    expect(response.headers()["cache-control"]).toBe("no-store");
    expect(response.headers()["referrer-policy"]).toBe("no-referrer");
  }
  const verdict = await page.request.get(`/packages/${IDS.westEnd1}/verdict.json`);
  expect(verdict.status()).toBe(200);
  expect(verdict.headers()["content-disposition"]).toBe('attachment; filename="verdict-r1.json"');
  // Following a link reaches the blob store with the file.
  const download = page.waitForEvent("download");
  await page.getByRole("link", { name: "Download Floor 1 / plan.dxf" }).click();
  expect((await download).suggestedFilename()).toContain("plan.dxf");
});

test("the capture role cannot download", async ({ page, context }) => {
  await context.clearCookies();
  await signIn(context, ["capture"], "Casey Capture");
  const response = await page.request.get(`/packages/${IDS.westEnd1}/report/download`, {
    maxRedirects: 0,
  });
  expect(response.status()).toBe(403);
  await page.goto(`/packages/${IDS.westEnd1}`);
  await expect(page.locator('a[href*="/download"]')).toHaveCount(0);
});

test("every interactive element is reachable by keyboard with a visible focus", async ({
  page,
}) => {
  await page.goto(`/packages/${IDS.westEnd1}`);
  await settle(page);
  const seen = new Set<string>();
  for (let step = 0; step < 40; step += 1) {
    await page.keyboard.press("Tab");
    const focused = await page.evaluate(() => {
      const element = document.activeElement as HTMLElement | null;
      if (element === null || element === document.body) {
        return null;
      }
      const style = getComputedStyle(element);
      const wrap = element.closest(".hub-input-wrap, .search-pill");
      const ringed =
        (style.outlineStyle !== "none" && style.outlineWidth !== "0px") ||
        style.boxShadow !== "none" ||
        (wrap !== null && getComputedStyle(wrap).boxShadow !== "none");
      return {
        name: `${element.tagName} ${element.textContent?.trim().slice(0, 40) ?? ""} ${element.getAttribute("aria-label") ?? ""}`,
        ringed,
      };
    });
    if (focused === null) {
      continue;
    }
    expect(focused.ringed, focused.name).toBe(true);
    seen.add(focused.name);
  }
  expect(seen.size).toBeGreaterThan(20);
});

test("no request leaves the app: fonts and wordmark are self-hosted", async ({ page }) => {
  const urls = recordRequests(page);
  for (const path of [
    "/",
    "/packages",
    "/decisions",
    `/projects/${DEALS.westEnd}`,
    `/packages/${IDS.westEnd1}`,
  ]) {
    await page.goto(path);
    await settle(page);
  }
  await page.context().clearCookies();
  await page.goto("/sign-in");
  await settle(page);
  const outside = urls.filter((url) => !url.startsWith(WEB_ORIGIN) && !url.startsWith("data:"));
  expect(outside).toEqual([]);
  expect(urls.some((url) => url.endsWith("/brand/inter-400.woff2"))).toBe(true);
  expect(urls.some((url) => url.endsWith("/brand/inter-600.woff2"))).toBe(true);
  expect(urls.some((url) => url.endsWith("/brand/chapter-wordmark.svg"))).toBe(true);
});

test("signed out, every page goes to sign-in and comes back", async ({ page, context }) => {
  await context.clearCookies();
  await page.goto(`/packages/${IDS.westEnd1}`);
  await expect(page).toHaveURL(/\/sign-in\?callbackUrl=/);
  expect(new URL(page.url()).searchParams.get("callbackUrl")).toBe(`/packages/${IDS.westEnd1}`);
  await expect(page.getByRole("button", { name: "Sign in with Microsoft" })).toBeVisible();
});
