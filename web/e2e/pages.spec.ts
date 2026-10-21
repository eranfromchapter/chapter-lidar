// Every page of the review screen against the local station, at 1440 and 390 px (web-review
// §12.4): the pages render in Inter from /brand with the HUB wordmark, and no page scrolls
// sideways. Screenshots are compared with the artboards (2h, 2i, 2j) by eye; baselines are
// approved by the owner before they become toHaveScreenshot assertions.

import { expect, test } from "@playwright/test";
import { DEALS, IDS } from "../test/support/scenario-ids";
import { screenshots, settle, signIn, useScenario } from "./support";

test.beforeEach(async ({ request }) => {
  await useScenario(request);
});

test("sign-in page", async ({ page }) => {
  await page.goto("/sign-in?callbackUrl=%2F");
  await settle(page);
  await expect(page.getByRole("heading", { level: 1, name: "Sign in" })).toBeVisible();
  await expect(page.getByRole("img", { name: "Chapter" })).toHaveAttribute(
    "src",
    "/brand/chapter-wordmark.svg",
  );
  await screenshots(page, "sign-in");
  await page.goto("/sign-in?error=OAuthCallbackError");
  await expect(page.locator("#main").getByRole("alert")).toContainText("Sign-in did not finish");
  await screenshots(page, "sign-in-error");
});

test("projects (2h)", async ({ page, context }) => {
  await signIn(context, ["bim"]);
  await page.goto("/");
  await settle(page);
  await expect(page.getByRole("heading", { level: 2, name: "Projects" })).toBeVisible();
  await expect(page.getByRole("row")).toHaveCount(6);
  const fonts = await page.evaluate(() =>
    [...document.fonts].filter((font) => font.status === "loaded").map((font) => font.family),
  );
  expect(fonts).toContain("Inter");
  await screenshots(page, "projects");
  await page.goto("/?tab=limited");
  await expect(page.getByRole("row")).toHaveCount(2);
  await screenshots(page, "projects-tab-limited");
  await page.goto("/?q=nothing-like-this");
  await expect(page.getByText("No project matches “nothing-like-this”")).toBeVisible();
  await screenshots(page, "projects-no-match");
});

test("projects: empty, station error, no station role", async ({ page, context, request }) => {
  await signIn(context, ["bim"]);
  await useScenario(request, { scenario: "empty" });
  await page.goto("/");
  await expect(page.getByText("No capture packages yet")).toBeVisible();
  await screenshots(page, "projects-empty");
  await useScenario(request, { failWith: 503 });
  await page.goto("/");
  await expect(page.locator("#main").getByRole("alert")).toContainText(
    "The station could not answer",
  );
  await screenshots(page, "projects-station-error");
  await context.clearCookies();
  await signIn(context, []);
  await page.goto("/");
  await expect(page.locator("#main").getByRole("alert")).toContainText("No access");
  await screenshots(page, "projects-no-role");
});

test("packages list", async ({ page, context }) => {
  await signIn(context, ["bim"]);
  await page.goto("/packages");
  await expect(page.getByRole("heading", { level: 2, name: "Packages" })).toBeVisible();
  await screenshots(page, "packages");
});

test("project (2i): revision 2 on the phone", async ({ page, context }) => {
  await signIn(context, ["bim"]);
  await page.goto(`/projects/${DEALS.westEnd}`);
  await expect(page.getByText("not sealed · on the phone")).toBeVisible();
  await expect(page.getByRole("heading", { name: "What revision 2 adds" })).toBeVisible();
  await screenshots(page, "project");
  await page.goto(`/projects/${DEALS.westEnd}?tab=log`);
  await expect(page.getByRole("heading", { name: "Modeling decision log" })).toBeVisible();
  await screenshots(page, "project-log");
  await page.goto(`/projects/${DEALS.valley}`);
  await expect(page.getByText(/uploading from the phone · \d+%/)).toBeVisible();
  await screenshots(page, "project-uploading");
  await page.goto(`/projects/${DEALS.shawnee}`);
  await screenshots(page, "project-two-revisions");
});

test("project: capture role", async ({ page, context }) => {
  await signIn(context, ["capture"], "Casey Capture");
  await page.goto(`/projects/${DEALS.westEnd}`);
  await expect(page.getByRole("link", { name: /Decision log/ })).toHaveCount(0);
  await screenshots(page, "project-capture-role");
});

test("package (2j)", async ({ page, context, request }) => {
  await signIn(context, ["bim"]);
  await page.goto(`/packages/${IDS.westEnd1}`);
  await expect(page.getByRole("region", { name: "Verdict: Limited" })).toBeVisible();
  await screenshots(page, "package");
  await useScenario(request, { reportReady: true });
  await page.goto(`/packages/${IDS.westEnd1}`);
  await expect(page.getByRole("link", { name: "Spatial report PDF" }).first()).toBeVisible();
  await screenshots(page, "package-report-ready");
});

test("package: capture role", async ({ page, context }) => {
  await signIn(context, ["capture"], "Casey Capture");
  await page.goto(`/packages/${IDS.westEnd1}`);
  await expect(
    page.getByText("Checks, files and downloads are shown to BIM operators and admins."),
  ).toBeVisible();
  await screenshots(page, "package-capture-role");
});

test("package states", async ({ page, context, request }) => {
  await signIn(context, ["bim"]);
  await useScenario(request, { scenario: "states" });
  for (const [id, name] of [
    [IDS.valley1, "package-uploading"],
    [IDS.checking, "package-checking"],
    [IDS.checkError, "package-check-error"],
    [IDS.twoFloors, "package-two-floors"],
    [IDS.stopped1, "package-upload-stopped"],
    [IDS.legacy, "package-legacy"],
    [IDS.blocked1, "package-blocked"],
  ] as const) {
    await page.goto(`/packages/${id}`);
    await screenshots(page, name);
  }
});

test("upload stopped and re-sealed: one wording on every page", async ({
  page,
  context,
  request,
}) => {
  await signIn(context, ["bim"]);
  await useScenario(request, { scenario: "states" });
  await page.goto("/projects/4419004");
  await expect(page.getByText("upload stopped · replaced by revision 2")).toBeVisible();
  // Revision 1 was never checked: nothing for revision 2 to add to, no verdict to keep.
  await expect(page.getByRole("heading", { name: /What revision/ })).toHaveCount(0);
  await expect(page.getByText(/keeps its verdict/)).toHaveCount(0);
  await screenshots(page, "project-upload-stopped");
  await page.goto("/packages");
  await expect(
    page.getByText("Revision 1 · upload stopped · replaced by revision 2"),
  ).toBeVisible();
  await screenshots(page, "packages-states");
  await page.goto(`/packages/${IDS.stopped1}`);
  const station = page.getByRole("region", { name: "Station" });
  await expect(station).toContainText("Upload stopped");
  await expect(station).toContainText("replaced by revision 2");
  await expect(station).not.toContainText("after upload");
  await expect(page.locator(".title-row .meta-row")).toHaveText(
    "upload stopped · replaced by revision 2",
  );
});

test("one main landmark while the page streams in", async ({ page, context, request }) => {
  await signIn(context, ["bim"]);
  await useScenario(request, { scenario: "states" });
  for (const path of ["/", "/packages", "/projects/4419004", `/packages/${IDS.westEnd1}`]) {
    await page.goto(path);
    // Right after the load event, before the streamed page has replaced the loading state.
    const early = await page.evaluate(() => ({
      mains: document.querySelectorAll("main").length,
      ids: document.querySelectorAll("#main").length,
    }));
    expect(early, path).toEqual({ mains: 1, ids: 1 });
    await settle(page);
    await expect(page.locator("main")).toHaveCount(1);
    await expect(page.locator("#main")).toBeVisible();
  }
});

test("meta rows wrap with the drawn gap (2i: 16 px, 2j: 14 px)", async ({ page, context }) => {
  await signIn(context, ["bim"]);
  await page.setViewportSize({ width: 390, height: 900 });
  const lineGaps = (selector: string) =>
    page.locator(selector).evaluate((row) => {
      const style = getComputedStyle(row);
      const items = [...row.children].map((child) => child.getBoundingClientRect());
      const tops = [...new Set(items.map((item) => Math.round(item.top)))].sort((a, b) => a - b);
      // The space between the lowest item of a line and the top of the next line.
      const bottomOf = (top: number) =>
        Math.max(
          ...items.filter((item) => Math.round(item.top) === top).map((item) => item.bottom),
        );
      return {
        rowGap: style.rowGap,
        columnGap: style.columnGap,
        lines: tops.length,
        between: tops.slice(1).map((top, index) => top - bottomOf(tops[index] ?? 0)),
      };
    });
  await page.goto(`/packages/${IDS.westEnd1}`);
  await settle(page);
  const pkg = await lineGaps(".title-row .meta-row");
  expect(pkg.rowGap).toBe("14px");
  expect(pkg.columnGap).toBe("14px");
  expect(pkg.lines).toBeGreaterThan(1);
  for (const gap of pkg.between) {
    expect(Math.abs(gap - 14)).toBeLessThanOrEqual(1);
  }
  await page.goto(`/projects/${DEALS.westEnd}`);
  await settle(page);
  const project = await lineGaps(".title-row .meta-row");
  expect(project.rowGap).toBe("16px");
  expect(project.columnGap).toBe("16px");
});

test("decision log", async ({ page, context }) => {
  await signIn(context, ["bim"]);
  await page.goto("/decisions");
  await expect(page.getByRole("heading", { level: 2, name: "Decision log" })).toBeVisible();
  await screenshots(page, "decisions");
  await context.clearCookies();
  await signIn(context, ["capture"], "Casey Capture");
  await page.goto("/decisions");
  await expect(page.locator("#main").getByRole("alert")).toContainText("No access");
  await screenshots(page, "decisions-capture-role");
});

test("not found", async ({ page, context }) => {
  await signIn(context, ["bim"]);
  await page.goto("/packages/00000000-0000-4000-8000-000000000000");
  await expect(page.getByRole("heading", { name: "Not found" }).first()).toBeVisible();
  await screenshots(page, "not-found-package");
  await page.goto("/no/such/page");
  await expect(page.getByRole("heading", { name: "Not found" })).toBeVisible();
  await screenshots(page, "not-found");
});
