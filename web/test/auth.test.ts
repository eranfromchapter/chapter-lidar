// @vitest-environment jsdom
// AC1: unauthenticated users are redirected to sign-in, and capture-role users cannot download
// or log decisions (no controls on screen, and the server-side entry points refuse).

import { cleanup, render, screen } from "@testing-library/react";
import { NextRequest } from "next/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ViewerSession } from "@/lib/viewer";
import { contractExampleCase } from "./support/fixtures";
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
const { default: PackagePage } = await import("@/app/packages/[packageId]/page");
const { default: DecisionsPage } = await import("@/app/packages/[packageId]/decisions/page");
const { saveDecision } = await import("@/app/packages/[packageId]/decisions/actions");
const { GET: downloadFile } = await import("@/app/packages/[packageId]/files/download/route");
const { GET: previewFile } = await import("@/app/packages/[packageId]/files/preview/route");

const example = contractExampleCase();
const packageId = example.pkg.packageId;
const dxfPath = example.pkg.files.find((file) => file.role === "plan_dxf")?.path ?? "";

function freshStation(): FakeStation {
  return createFakeStation({
    projects: [example.project],
    packages: [structuredClone(example.pkg)],
    verdicts: { [packageId]: example.verdict },
    decisions: {},
  });
}

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
    "/projects/example-deal-0001",
    `/packages/${packageId}`,
    `/packages/${packageId}/decisions`,
  ])(
    "redirects an unauthenticated GET %s to sign-in with the path as callbackUrl",
    async (path) => {
      const response = await proxy(request(path), event);
      expect(response.status).toBe(307);
      const location = new URL(response.headers.get("location") ?? "");
      expect(location.pathname).toBe("/api/auth/signin");
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
    expect(response.headers.get("location")).toContain("/api/auth/signin");
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

  it("covers every page and route handler, excluding only auth routes and static assets", () => {
    const matcher = new RegExp(`^${proxyConfig.matcher[0]}$`);
    for (const path of [
      "/",
      "/projects/x",
      `/packages/${packageId}`,
      `/packages/${packageId}/decisions`,
      `/packages/${packageId}/files/download`,
      `/packages/${packageId}/files/preview`,
    ]) {
      expect(matcher.test(path), path).toBe(true);
    }
    for (const path of [
      "/api/auth/signin",
      "/api/auth/callback/microsoft-entra-id",
      "/_next/static/x.js",
    ]) {
      expect(matcher.test(path), path).toBe(false);
    }
  });
});

describe("proxy: missing configuration fails closed", () => {
  it("serves the configuration page and no data when settings are missing", async () => {
    stubConfig();
    vi.stubEnv("STATION_API_URL", "");
    const errors = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const cookie = await sessionCookie({ roles: ["bim"] });
    const response = await proxy(request("/", { cookie: `${SESSION_COOKIE}=${cookie}` }), event);
    expect(response.status).toBe(503);
    const body = await response.text();
    expect(body).toContain("Capture review is not configured");
    expect(body).not.toContain(TEST_ENV.AUTH_SECRET);
    expect(errors).toHaveBeenCalledWith(expect.stringContaining("STATION_API_URL"));
  });
});

describe("capture role: status only", () => {
  it("shows the package without download links, plan previews or the decision log", async () => {
    const station = freshStation();
    state.session = sessionFor(["capture"], station, "Casey Capture");
    const { container } = render(
      await PackagePage({
        params: Promise.resolve({ packageId }),
        searchParams: Promise.resolve({}),
      }),
    );
    expect(screen.getByText("Casey Capture · Capture operator")).toBeTruthy();
    expect(screen.getByRole("region", { name: /Verdict/ })).toBeTruthy();
    expect(screen.queryAllByRole("link", { name: /Download/ })).toHaveLength(0);
    expect(container.querySelector("img")).toBeNull();
    expect(container.innerHTML).not.toContain("/files/download");
    expect(container.innerHTML).not.toContain("/files/preview");
    expect(screen.queryByRole("link", { name: /modeling decision/i })).toBeNull();
    expect(station.calls.some((call) => call.path.endsWith("/files/download"))).toBe(false);
  });

  it("shows no decision form and does not read decisions", async () => {
    const station = freshStation();
    state.session = sessionFor(["capture"], station, "Casey Capture");
    render(await DecisionsPage({ params: Promise.resolve({ packageId }) }));
    expect(screen.queryByRole("form", { name: "Log a decision" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Save decision" })).toBeNull();
    expect(station.calls.some((call) => call.path.endsWith("/modeling-decisions"))).toBe(false);
  });

  it("is refused by the decision server action without calling the station", async () => {
    const station = freshStation();
    state.session = sessionFor(["capture"], station, "Casey Capture");
    const form = new FormData();
    form.set("packageId", packageId);
    form.set("element", "Floor 1 · kitchen east wall");
    form.set("source", dxfPath);
    form.set("decision", "Modeled as native Revit wall");
    const result = await saveDecision({ status: "idle", attempt: 0 }, form);
    expect(result.status).toBe("error");
    expect(result.status === "error" ? result.message : "").toMatch(/BIM operators and admins/);
    expect(station.calls).toHaveLength(0);
  });

  it("is refused by the download and preview routes without calling the station", async () => {
    const station = freshStation();
    state.session = sessionFor(["capture"], station, "Casey Capture");
    const url = `http://localhost:3000/packages/${packageId}/files/download?path=${encodeURIComponent(dxfPath)}`;
    const download = await downloadFile(new Request(url), {
      params: Promise.resolve({ packageId }),
    });
    expect(download.status).toBe(403);
    expect(download.headers.get("location")).toBeNull();
    const preview = await previewFile(new Request(url.replace("/download", "/preview")), {
      params: Promise.resolve({ packageId }),
    });
    expect(preview.status).toBe(403);
    expect(station.calls).toHaveLength(0);
  });
});

describe("signed-out server entry points", () => {
  it("refuse the decision action and file routes when there is no session", async () => {
    state.session = null;
    const form = new FormData();
    form.set("packageId", packageId);
    const result = await saveDecision({ status: "idle", attempt: 0 }, form);
    expect(result.status).toBe("error");
    const download = await downloadFile(
      new Request(`http://localhost:3000/packages/${packageId}/files/download?path=x`),
      { params: Promise.resolve({ packageId }) },
    );
    expect(download.status).toBe(401);
  });
});

describe("bim role: downloads go through a short-lived link fetched on click", () => {
  it("renders download links to this app, never the signed link", async () => {
    const station = freshStation();
    state.session = sessionFor(["bim"], station);
    const { container } = render(
      await PackagePage({
        params: Promise.resolve({ packageId }),
        searchParams: Promise.resolve({}),
      }),
    );
    const links = screen.getAllByRole("link", { name: /^Download / });
    expect(links.length).toBe(example.pkg.files.length);
    expect(links[0]?.getAttribute("href")).toMatch(
      new RegExp(`^/packages/${packageId}/files/download\\?path=`),
    );
    expect(container.innerHTML).not.toContain("sig=");
    expect(station.calls.some((call) => call.path.endsWith("/files/download"))).toBe(false);
  });

  it("redirects to the station's link on click with no-store", async () => {
    const station = freshStation();
    state.session = sessionFor(["bim"], station);
    const response = await downloadFile(
      new Request(
        `http://localhost:3000/packages/${packageId}/files/download?path=${encodeURIComponent(dxfPath)}`,
      ),
      { params: Promise.resolve({ packageId }) },
    );
    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toContain("https://blob.test/originals/");
    expect(response.headers.get("cache-control")).toBe("no-store");
    const call = station.calls.find((item) => item.path.endsWith("/files/download"));
    expect(call?.search.get("path")).toBe(dxfPath);
    expect(call?.authorization).toBe("Bearer test-access-token");
  });
});
