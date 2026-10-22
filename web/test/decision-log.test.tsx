// @vitest-environment jsdom
// The modeling decision log on the package page (web-review §6.4.7-6.4.8, WR-AC9): the form's
// fields and source groups, a decision saved through the station with the sources resolved on
// the server, listed with author and time; the v1 page redirects to it.

import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { StationPackage } from "@/lib/station-types";
import type { ViewerSession } from "@/lib/viewer";
import { drawnScenario, IDS } from "./support/scenarios";
import { createFakeStation, sessionFor, type FakeStation } from "./support/station";

const state = vi.hoisted(() => ({ session: null as ViewerSession | null }));

vi.mock("@/lib/viewer", () => ({
  getViewerSession: async () => state.session,
  requireViewerSession: async () => state.session,
}));
const cacheMock = vi.hoisted(() => ({ revalidatePath: vi.fn() }));
vi.mock("next/cache", () => cacheMock);
const navigation = vi.hoisted(() => ({ permanentRedirect: vi.fn() }));
vi.mock("next/navigation", async (original) => ({
  ...(await original<typeof import("next/navigation")>()),
  permanentRedirect: navigation.permanentRedirect,
}));

const { default: PackagePage } = await import("@/app/(review)/packages/[packageId]/page");
const { default: DecisionsRedirect } =
  await import("@/app/(review)/packages/[packageId]/decisions/page");
const { saveDecision } = await import("@/app/(review)/packages/[packageId]/decisions/actions");

const NOW = new Date("2026-10-21T18:00:00Z");

beforeAll(() => {
  Element.prototype.scrollIntoView = vi.fn();
});

afterEach(() => {
  cleanup();
  state.session = null;
  cacheMock.revalidatePath.mockClear();
});

function freshStation(): FakeStation {
  return createFakeStation(drawnScenario(NOW));
}

function sample(station: FakeStation): StationPackage {
  return station.data.packages.find((pkg) => pkg.packageId === IDS.westEnd1) as StationPackage;
}

async function renderPackage(station: FakeStation) {
  state.session = sessionFor(["bim"], station);
  return render(
    await PackagePage({
      params: Promise.resolve({ packageId: IDS.westEnd1 }),
      searchParams: Promise.resolve({}),
    }),
  );
}

describe("decision form", () => {
  it("has the drawn fields, placeholders and source groups", async () => {
    await renderPackage(freshStation());
    const form = screen.getByRole("form", { name: "Log a decision" });
    expect(within(form).getByLabelText("Element or area").getAttribute("placeholder")).toBe(
      "Floor 1 · kitchen east wall",
    );
    expect(within(form).getByLabelText("Decision").getAttribute("placeholder")).toBe(
      "Modeled as a native Revit wall, 4,520 mm",
    );
    expect(
      within(form)
        .getByLabelText("Remaining uncertainty and next check")
        .getAttribute("placeholder"),
    ).toBe("Wall thickness unknown; verify at demolition");
    const select = within(form).getByLabelText("Source used") as HTMLSelectElement;
    expect(select.required).toBe(true);
    expect(select.options[0]?.textContent).toBe("Choose a source");
    expect(select.options[0]?.disabled).toBe(true);
    expect([...select.querySelectorAll("optgroup")].map((group) => group.label)).toEqual([
      "Plans and models",
      "Plan checked against tape",
      "Field controls",
      "Site photos",
    ]);
    expect(form.textContent).toContain(
      "Saved through the station with your name and time. Entries cannot be edited, only followed by a new one.",
    );
    // Option values are keys, resolved on the server; no package path is posted.
    for (const option of [...select.options].slice(1)) {
      expect(option.value).toMatch(/^(file|filectl|ctl|photos):/);
    }
  });

  it("lists the logged decisions oldest first with their sources, author and time", async () => {
    await renderPackage(freshStation());
    const card = screen.getByRole("region", { name: "Modeling decision log" });
    expect(card.textContent).toContain(
      "3 entries · the source used for each modeling decision, its remaining uncertainty and the next check",
    );
    const entries = within(card).getAllByRole("listitem");
    expect(entries.map((entry) => entry.querySelector("b")?.textContent)).toEqual([
      "Living Room walls",
      "Kitchen cabinetry",
      "Room 4 ceiling",
    ]);
    expect(entries[0]?.textContent).toContain(
      "Living Room walls — native Revit walls from plan.dxf, checked against Distance A · from Floor 1 / plan.dxf + Distance A (laser) · uncertainty: wall thickness; check at demolition",
    );
    expect(entries[0]?.textContent).toContain("Robin Revit · Oct 17, 2026 12:05");
    expect(
      within(entries[0] as HTMLElement)
        .getByText("Oct 17, 2026 12:05")
        .getAttribute("datetime"),
    ).toBe("2026-10-17T16:05:00Z");
  });

  it("saves a decision through the station and lists it with author and time", async () => {
    const station = freshStation();
    station.author = { name: "Dana BIM", userId: "11111111-1111-4111-8111-111111111111" };
    station.now = "2026-10-21T17:42:07Z";
    await renderPackage(station);
    const pkg = sample(station);
    const dxf = pkg.files.find((file) => file.role === "plan_dxf")?.path ?? "";
    const controls = pkg.files.find((file) => file.role === "field_controls")?.path ?? "";
    const form = screen.getByRole("form", { name: "Log a decision" });
    fireEvent.change(within(form).getByLabelText("Element or area"), {
      target: { value: "Floor 1 · kitchen east wall" },
    });
    fireEvent.change(within(form).getByLabelText("Source used"), {
      target: { value: `filectl:${dxf}|floor-1-distance-a` },
    });
    fireEvent.change(within(form).getByLabelText("Decision"), {
      target: { value: "Modeled as a native Revit wall, 4,520 mm" },
    });
    fireEvent.change(within(form).getByLabelText("Remaining uncertainty and next check"), {
      target: { value: "Wall thickness unknown; verify at demolition" },
    });
    await act(async () => {
      fireEvent.click(within(form).getByRole("button", { name: "Save decision" }));
    });
    await waitFor(() => expect(screen.getByText("Decision saved.")).toBeTruthy());
    expect(screen.getByRole("status").textContent).toBe("Decision saved.");
    const posts = station.calls.filter((call) => call.method === "POST");
    expect(posts).toHaveLength(1);
    expect(posts[0]?.path).toBe(`/packages/${IDS.westEnd1}/modeling-decisions`);
    expect(posts[0]?.body).toEqual({
      element: "Floor 1 · kitchen east wall",
      decision: "Modeled as a native Revit wall, 4,520 mm",
      captureId: "33ede7f4-cfcb-4cd6-9af5-7daffee829a9",
      areaKey: "floor-1",
      sources: [{ path: dxf }, { path: controls, controlId: "floor-1-distance-a" }],
      note: "Wall thickness unknown; verify at demolition",
    });
    expect(cacheMock.revalidatePath).toHaveBeenCalledWith(`/packages/${IDS.westEnd1}`);

    // Next.js renders the page again after revalidatePath; the entry is listed.
    cleanup();
    await renderPackage(station);
    const entries = within(
      screen.getByRole("region", { name: "Modeling decision log" }),
    ).getAllByRole("listitem");
    expect(entries).toHaveLength(4);
    expect(entries[3]?.textContent).toContain(
      "Floor 1 · kitchen east wall — Modeled as a native Revit wall, 4,520 mm · from Floor 1 / plan.dxf + Distance A (laser) · Wall thickness unknown; verify at demolition",
    );
    expect(entries[3]?.textContent).toContain("Dana BIM · Oct 21, 2026 13:42");
  });
});

describe("decision action", () => {
  function form(values: Record<string, string>): FormData {
    const data = new FormData();
    for (const [name, value] of Object.entries(values)) {
      data.set(name, value);
    }
    return data;
  }

  it("refuses a source key that is not one of the package's, keeping the values", async () => {
    const station = freshStation();
    state.session = sessionFor(["admin"], station);
    const result = await saveDecision(
      { status: "idle", attempt: 0 },
      form({
        packageId: IDS.westEnd1,
        element: "Floor 2 · hall",
        source: "file:Original Exports/not-in-package.dxf",
        decision: "Taken from the plan",
      }),
    );
    expect(result).toMatchObject({
      status: "error",
      message: "Choose the source used.",
      values: { element: "Floor 2 · hall" },
    });
    expect(station.calls.some((call) => call.method === "POST")).toBe(false);
  });

  it("validates required fields before calling the station", async () => {
    const station = freshStation();
    state.session = sessionFor(["bim"], station);
    const result = await saveDecision(
      { status: "idle", attempt: 3 },
      form({ packageId: IDS.westEnd1, element: " " }),
    );
    expect(result.status).toBe("error");
    expect(result.attempt).toBe(4);
    expect(station.calls).toHaveLength(0);
  });

  it("shows the station's rule violation and keeps the entered values", async () => {
    const station = freshStation();
    state.session = sessionFor(["bim"], station);
    // The station refuses a source of another package (here: the package lost the file).
    const pkg = sample(station);
    const dxf = pkg.files.find((file) => file.role === "plan_dxf")?.path ?? "";
    const original = station.fetch;
    const refusing: typeof fetch = async (input, init) =>
      init?.method === "POST"
        ? new Response(
            JSON.stringify({
              type: "about:blank",
              title: "decision_rule_violation",
              status: 422,
              code: "decision_rule_violation",
              errors: [{ pointer: "/sources/0/path", message: "not a file of the package" }],
            }),
            { status: 422, headers: { "content-type": "application/problem+json" } },
          )
        : original(input, init);
    state.session = {
      ...state.session,
      station: (await import("@/lib/station")).createStationClient({
        baseUrl: "https://station.test",
        accessToken: "test-access-token",
        fetchImpl: refusing,
      }),
    };
    const result = await saveDecision(
      { status: "idle", attempt: 0 },
      form({ packageId: IDS.westEnd1, element: "Hall", source: `file:${dxf}`, decision: "Plan" }),
    );
    expect(result).toMatchObject({
      status: "error",
      message: "The station rejected the decision: not a file of the package",
      values: { element: "Hall", source: `file:${dxf}` },
    });
    expect(cacheMock.revalidatePath).not.toHaveBeenCalled();
  });
});

describe("v1 decision page", () => {
  it("redirects permanently to the package page's decision log", async () => {
    navigation.permanentRedirect.mockImplementation(() => {
      throw new Error("redirected");
    });
    await expect(
      DecisionsRedirect({ params: Promise.resolve({ packageId: IDS.westEnd1 }) }),
    ).rejects.toThrow("redirected");
    expect(navigation.permanentRedirect).toHaveBeenCalledWith(
      `/packages/${IDS.westEnd1}#decisions`,
    );
  });
});
