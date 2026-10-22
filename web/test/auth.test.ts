// @vitest-environment jsdom
// Access (web-review §6.6, §10, WR-AC7, WR-AC8): unauthenticated users are redirected to
// sign-in; capture-role users see status only (the hidden parts are absent from the DOM) and
// every download route refuses them without calling the station; bim and admin get
// short-lived links on click, never rendered into a page.

import { cleanup, render, screen } from "@testing-library/react";
import { NextRequest } from "next/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ViewerSession } from "@/lib/viewer";
import { drawnScenario, DEALS, IDS } from "./support/scenarios";
import { createFakeStation, sessionFor, type FakeStation } from "./support/station";
import { SESSION_COOKIE, sessionCookie, TEST_ENV } from "./support/tokens";

const state = vi.hoisted(() => ({ session: null as ViewerSession | null }));

vi.mock("@/lib/viewer", () => ({
  getViewerSession: async () => state.session,
  requireViewerSession: async () => {
    if (state.session === null) {
      throw new Error("requireViewerSession called without a session");
    }
    return state.session;
  },
}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

const { proxy, config: proxyConfig } = await import("@/proxy");
const { handlers } = await import("@/auth");
const { default: PackagePage } = await import("@/app/(review)/packages/[packageId]/page");
const { default: ProjectPage } = await import("@/app/(review)/projects/[dealId]/page");
const { default: DecisionLogPage } = await import("@/app/(review)/decisions/page");
const { saveDecision } = await import("@/app/(review)/packages/[packageId]/decisions/actions");
const { GET: downloadFile } =
  await import("@/app/(review)/packages/[packageId]/files/download/route");
const { GET: previewFile } =
  await import("@/app/(review)/packages/[packageId]/files/preview/route");
const { GET: downloadReport } =
  await import("@/app/(review)/packages/[packageId]/report/download/route");
const { GET: downloadVerdict } =
  await import("@/app/(review)/packages/[packageId]/verdict.json/route");

const NOW = new Date("2026-10-21T18:00:00Z");
const packageId = IDS.westEnd1;

function freshStation(reportReady = false): FakeStation {
  return createFakeStation(drawnScenario(NOW, { reportReady }));
}

const sample = freshStation().data.packages.find((pkg) => pkg.packageId === packageId);
const dxfPath = sample?.files.find((file) => file.role === "plan_dxf")?.path ?? "";
const pngPath = sample?.files.find((file) => file.role === "plan_png")?.path ?? "";
const manifestPath = sample?.manifestFile?.path ?? "";

function stubConfig(): void {
  for (const [name, value] of Object.entries(TEST_ENV)) {
    vi.stubEnv(name, value);
  }
}

function request(path: string, init: { method?: string; cookie?: string } = {}): NextRequest {
  // Next.js always sets host and x-forwarded-proto on proxied requests.
  const headers = new Headers({ host: "localhost:3000", "x-forwarded-proto": "http" });
  if (init.cookie !== undefined) {
    headers.set("cookie", init.cookie);
  }
  return new NextRequest(new URL(path, "http://localhost:3000"), {
    method: init.method ?? "GET",
    headers,
  });
}

const event = { waitUntil: () => undefined } as never;

afterEach(() => {
  cleanup();
  vi.unstubAllEnvs();
  state.session = null;
});

describe("proxy: sign-in is required for every page", () => {
  beforeEach(stubConfig);

  it.each([
    "/",
    "/packages",
    "/decisions",
    "/projects/example-deal-0001",
    `/packages/${packageId}`,
    `/packages/${packageId}/decisions`,
    `/packages/${packageId}/report/download`,
    `/packages/${packageId}/verdict.json`,
  ])(
    "redirects an unauthenticated GET %s to sign-in with the path as callbackUrl",
    async (path) => {
      const response = await proxy(request(path), event);
      expect(response.status).toBe(307);
      const location = new URL(response.headers.get("location") ?? "");
      expect(location.pathname).toBe("/sign-in");
      expect(location.searchParams.get("callbackUrl")).toBe(path);
    },
  );

  it("redirects a file download without a session, before any station call", async () => {
    const path = `/packages/${packageId}/files/download?path=${encodeURIComponent(dxfPath)}`;
    const response = await proxy(request(path), event);
    expect(response.status).toBe(307);
    expect(new URL(response.headers.get("location") ?? "").searchParams.get("callbackUrl")).toBe(
      path,
    );
  });

  it("refuses a server action POST without a session", async () => {
    const response = await proxy(
      request(`/packages/${packageId}/decisions`, { method: "POST" }),
      event,
    );
    expect(response.status).toBe(401);
  });

  it("treats a forged session cookie as no session", async () => {
    const response = await proxy(
      request("/", { cookie: `${SESSION_COOKIE}=not-a-sealed-token` }),
      event,
    );
    expect(response.status).toBe(307);
  });

  it("signs the user out when the station token expired and cannot be refreshed", async () => {
    const cookie = await sessionCookie({ roles: ["bim"], expiresInSeconds: -60 });
    const response = await proxy(request("/", { cookie: `${SESSION_COOKIE}=${cookie}` }), event);
    expect(response.status).toBe(307);
    expect(new URL(response.headers.get("location") ?? "").pathname).toBe("/sign-in");
  });

  it("lets a request with a valid session through", async () => {
    const cookie = await sessionCookie({ roles: ["capture"] });
    const response = await proxy(request("/", { cookie: `${SESSION_COOKIE}=${cookie}` }), event);
    expect(response.headers.get("location")).toBeNull();
    expect(response.headers.get("x-middleware-next")).toBe("1");
  });

  it("leaves the Auth.js routes reachable without a session", async () => {
    const response = await proxy(request("/api/auth/signin"), event);
    expect(response.headers.get("location")).toBeNull();
    expect(response.headers.get("x-middleware-next")).toBe("1");
  });

  it("serves the sign-in page and its sign-in action without a session", async () => {
    for (const method of ["GET", "POST"]) {
      const response = await proxy(request("/sign-in?callbackUrl=%2F", { method }), event);
      expect(response.headers.get("location"), method).toBeNull();
      expect(response.headers.get("x-middleware-next"), method).toBe("1");
    }
  });

  it("does not open anything else that starts like the sign-in page", async () => {
    for (const path of ["/sign-in/x", "/sign-inx", "/brand"]) {
      const response = await proxy(request(path), event);
      expect(response.status, path).toBe(307);
    }
  });

  it("covers every page and route handler, excluding only auth routes and assets", () => {
    const matcher = new RegExp(`^${proxyConfig.matcher[0]}$`);
    for (const path of [
      "/",
      "/packages",
      "/decisions",
      "/projects/x",
      `/packages/${packageId}`,
      `/packages/${packageId}/decisions`,
      `/packages/${packageId}/files/download`,
      `/packages/${packageId}/files/preview`,
      `/packages/${packageId}/report/download`,
      `/packages/${packageId}/verdict.json`,
      "/sign-in",
    ]) {
      expect(matcher.test(path), path).toBe(true);
    }
    // The brand assets (logo and fonts) load on the sign-in and configuration pages too.
    for (const path of [
      "/api/auth/signin",
      "/api/auth/callback/microsoft-entra-id",
      "/_next/static/x.js",
      "/brand/chapter-logo.svg",
      "/brand/chapter-wordmark.svg",
      "/brand/inter-400.woff2",
      "/brand/inter-600.woff2",
    ]) {
      expect(matcher.test(path), path).toBe(false);
    }
  });
});

describe("proxy: missing configuration fails closed", () => {
  it("serves the configuration page instead of the sign-in page", async () => {
    stubConfig();
    vi.stubEnv("AUTH_SECRET", "");
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const response = await proxy(request("/sign-in"), event);
    expect(response.status).toBe(503);
    expect(await response.text()).toContain("Capture review is not configured");
  });

  it("serves the configuration page and no data when settings are missing", async () => {
    stubConfig();
    vi.stubEnv("STATION_API_URL", "");
    const errors = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const cookie = await sessionCookie({ roles: ["bim"] });
    const response = await proxy(request("/", { cookie: `${SESSION_COOKIE}=${cookie}` }), event);
    expect(response.status).toBe(503);
    const body = await response.text();
    expect(body).toContain("Capture review is not configured");
    expect(body).toContain('src="/brand/chapter-wordmark.svg"');
    expect(body).not.toContain("chapter-logo.svg");
    expect(body).not.toMatch(/Times/);
    expect(body).toContain('url("/brand/inter-400.woff2")');
    expect(body).not.toContain(TEST_ENV.AUTH_SECRET);
    expect(errors).toHaveBeenCalledWith(expect.stringContaining("STATION_API_URL"));
  });
});

describe("Auth.js: the review screen's sign-in page replaces the default pages", () => {
  beforeEach(stubConfig);

  it("sends its sign-in page to /sign-in with the callbackUrl", async () => {
    const response = await handlers.GET(request("/api/auth/signin?callbackUrl=%2Fprojects%2Fx"));
    expect(response.status).toBe(302);
    const location = new URL(response.headers.get("location") ?? "", "http://localhost:3000");
    expect(location.pathname).toBe("/sign-in");
    expect(new URL(location.searchParams.get("callbackUrl") ?? "").pathname).toBe("/projects/x");
  });

  it("sends its error page to /sign-in with the error", async () => {
    const response = await handlers.GET(request("/api/auth/error?error=AccessDenied"));
    expect(response.status).toBe(302);
    const location = new URL(response.headers.get("location") ?? "", "http://localhost:3000");
    expect(location.pathname).toBe("/sign-in");
    expect(location.searchParams.get("error")).toBe("AccessDenied");
  });
});

function fileRequest(route: string, path?: string): Request {
  const query = path === undefined ? "" : `?path=${encodeURIComponent(path)}`;
  return new Request(`http://localhost:3000/packages/${packageId}/${route}${query}`);
}

const routeContext = { params: Promise.resolve({ packageId }) };

describe("capture role: status only", () => {
  it("sees the verdict and the station card, and none of the bim parts are in the DOM", async () => {
    const station = freshStation(true);
    state.session = sessionFor(["capture"], station, "Casey Capture");
    const { container } = render(
      await PackagePage({
        params: Promise.resolve({ packageId }),
        searchParams: Promise.resolve({}),
      }),
    );
    expect(screen.getByRole("region", { name: "Verdict: Limited" })).toBeTruthy();
    expect(screen.getByRole("region", { name: "Station" })).toBeTruthy();
    expect(
      screen.getByText("Checks, files and downloads are shown to BIM operators and admins."),
    ).toBeTruthy();
    for (const name of [
      "Plan",
      "Capture checks",
      /^Files · /,
      "Modeling decision log",
      "Capture record",
      "Field controls",
      "Documents",
    ]) {
      expect(screen.queryByRole("region", { name }), String(name)).toBeNull();
    }
    expect(screen.queryByRole("form", { name: "Log a decision" })).toBeNull();
    expect(
      screen.queryAllByRole("link", { name: /Download|PDF|verdict\.json|plan\./ }),
    ).toHaveLength(0);
    expect(screen.queryByRole("link", { name: /HUB › Files/ })).toBeNull();
    for (const route of [
      "/files/download",
      "/files/preview",
      "/report/download",
      "/verdict.json",
    ]) {
      expect(container.innerHTML, route).not.toContain(route);
    }
    expect(station.calls.some((call) => call.path.endsWith("/modeling-decisions"))).toBe(false);
    expect(station.calls.some((call) => call.path.endsWith("/files/download"))).toBe(false);
  });

  it("gets no report button, decision log tab or card on the project page", async () => {
    state.session = sessionFor(["capture"], freshStation(true), "Casey Capture");
    render(
      await ProjectPage({
        params: Promise.resolve({ dealId: DEALS.westEnd }),
        searchParams: Promise.resolve({ tab: "log" }),
      }),
    );
    expect(screen.queryByRole("link", { name: /Spatial report/ })).toBeNull();
    expect(screen.queryByRole("link", { name: /Decision log/ })).toBeNull();
    expect(screen.queryByRole("region", { name: "Decision log" })).toBeNull();
  });

  it("gets No access on the decision log page without a station call", async () => {
    const station = freshStation();
    state.session = sessionFor(["capture"], station, "Casey Capture");
    render(await DecisionLogPage());
    const alert = screen.getByRole("alert");
    expect(alert.textContent).toContain("No access");
    expect(alert.textContent).toContain(
      "Modeling decisions are read and logged by BIM operators and admins. Your account can see the package status only.",
    );
    expect(station.calls).toHaveLength(0);
  });

  it("is refused by the decision server action without calling the station", async () => {
    const station = freshStation();
    state.session = sessionFor(["capture"], station, "Casey Capture");
    const form = new FormData();
    form.set("packageId", packageId);
    form.set("element", "Floor 1 · kitchen east wall");
    form.set("source", `file:${dxfPath}`);
    form.set("decision", "Modeled as native Revit wall");
    const result = await saveDecision({ status: "idle", attempt: 0 }, form);
    expect(result.status).toBe("error");
    expect(result.status === "error" ? result.message : "").toMatch(/BIM operators and admins/);
    expect(station.calls).toHaveLength(0);
  });

  it("is refused by every download route with 403, without calling the station", async () => {
    const station = freshStation(true);
    state.session = sessionFor(["capture"], station, "Casey Capture");
    const answers = [
      await downloadFile(fileRequest("files/download", dxfPath), routeContext),
      await previewFile(fileRequest("files/preview", pngPath), routeContext),
      await downloadReport(fileRequest("report/download"), routeContext),
      await downloadVerdict(fileRequest("verdict.json"), routeContext),
    ];
    for (const answer of answers) {
      expect(answer.status).toBe(403);
      expect(await answer.text()).toBe("Only BIM operators and admins can download package files.");
      expect(answer.headers.get("location")).toBeNull();
    }
    expect(station.calls).toHaveLength(0);
  });
});

describe("signed-out server entry points", () => {
  it("refuse the decision action and every download route", async () => {
    state.session = null;
    const form = new FormData();
    form.set("packageId", packageId);
    const result = await saveDecision({ status: "idle", attempt: 0 }, form);
    expect(result.status).toBe("error");
    for (const answer of [
      await downloadFile(fileRequest("files/download", "x"), routeContext),
      await downloadReport(fileRequest("report/download"), routeContext),
      await downloadVerdict(fileRequest("verdict.json"), routeContext),
    ]) {
      expect(answer.status).toBe(401);
    }
  });
});

describe("bim role: downloads go through a short-lived link fetched on click", () => {
  it("renders download links to this app, never the signed link", async () => {
    const station = freshStation(true);
    state.session = sessionFor(["bim"], station);
    const { container } = render(
      await PackagePage({
        params: Promise.resolve({ packageId }),
        searchParams: Promise.resolve({}),
      }),
    );
    const links = [...container.querySelectorAll("a[href]")]
      .map((link) => link.getAttribute("href") ?? "")
      .filter((href) => href.includes("download") || href.includes("verdict.json"));
    expect(links.length).toBeGreaterThan(5);
    for (const href of links) {
      expect(href, href).toMatch(
        new RegExp(
          `^/packages/${packageId}/(files/download\\?path=|report/download$|verdict\\.json$)`,
        ),
      );
    }
    expect(container.innerHTML).not.toContain("sig=");
    expect(station.calls.some((call) => call.path.endsWith("/files/download"))).toBe(false);
    expect(station.calls.some((call) => call.path.endsWith("/spatial-report"))).toBe(false);
  });

  it("redirects a file download to the station's link with no-store and no referrer", async () => {
    const station = freshStation();
    state.session = sessionFor(["bim"], station);
    const response = await downloadFile(fileRequest("files/download", dxfPath), routeContext);
    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toContain("https://blob.test/originals/");
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("referrer-policy")).toBe("no-referrer");
    const call = station.calls.find((item) => item.path.endsWith("/files/download"));
    expect(call?.search.get("path")).toBe(dxfPath);
    expect(call?.authorization).toBe("Bearer test-access-token");
  });

  it("downloads the sealed manifest by its path", async () => {
    state.session = sessionFor(["bim"], freshStation());
    const response = await downloadFile(fileRequest("files/download", manifestPath), routeContext);
    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toContain(encodeURIComponent("manifest.json"));
  });

  it("redirects the spatial report to the station's link, and says when it is not ready", async () => {
    const ready = freshStation(true);
    state.session = sessionFor(["admin"], ready);
    const response = await downloadReport(fileRequest("report/download"), routeContext);
    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toMatch(
      /^https:\/\/blob\.test\/reports\/spatial-report-[0-9a-f-]{36}\.pdf\?sig=/,
    );
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("referrer-policy")).toBe("no-referrer");
    expect(ready.calls.map((call) => call.path)).toEqual([`/packages/${packageId}/spatial-report`]);

    state.session = sessionFor(["bim"], freshStation(false));
    const pending = await downloadReport(fileRequest("report/download"), routeContext);
    expect(pending.status).toBe(404);
    expect(await pending.text()).toBe("The spatial report is not ready yet.");
  });

  it("streams verdict.json as a JSON attachment named by revision", async () => {
    state.session = sessionFor(["bim"], freshStation());
    const response = await downloadVerdict(fileRequest("verdict.json"), routeContext);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("application/json; charset=utf-8");
    expect(response.headers.get("content-disposition")).toBe(
      'attachment; filename="verdict-r1.json"',
    );
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(response.headers.get("content-security-policy")).toBe("default-src 'none'");
    expect(response.headers.get("cache-control")).toBe("no-store");
    const verdict = (await response.json()) as { outcome: string; packageId: string };
    expect(verdict).toMatchObject({ outcome: "limited", packageId });
  });

  it("answers 404 No verdict yet before the checks finish, and 404 for a malformed id", async () => {
    const station = createFakeStation({ ...drawnScenario(NOW), verdicts: {} });
    state.session = sessionFor(["bim"], station);
    const early = await downloadVerdict(fileRequest("verdict.json"), routeContext);
    expect(early.status).toBe(404);
    expect(await early.text()).toBe("No verdict yet.");
    const malformed = await downloadVerdict(
      new Request("http://localhost:3000/packages/not-an-id/verdict.json"),
      { params: Promise.resolve({ packageId: "not-an-id" }) },
    );
    expect(malformed.status).toBe(404);
    expect(station.calls).toHaveLength(1);
  });
});
