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
