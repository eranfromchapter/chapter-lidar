// @vitest-environment jsdom
// AC3: a decision log entry is saved through the station and listed with author and time.

import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { formatDateTime } from "@/lib/format";
import type { ModelingDecision } from "@/lib/station-types";
import type { ViewerSession } from "@/lib/viewer";
import { contractExampleCase } from "./support/fixtures";
import { createFakeStation, sessionFor } from "./support/station";

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
const cacheMock = vi.hoisted(() => ({ revalidatePath: vi.fn() }));
vi.mock("next/cache", () => cacheMock);

const { default: DecisionsPage } = await import("@/app/packages/[packageId]/decisions/page");
const { saveDecision } = await import("@/app/packages/[packageId]/decisions/actions");

const example = contractExampleCase();
const packageId = example.pkg.packageId;
const dxf = example.pkg.files.find((file) => file.role === "plan_dxf");
const mesh = example.pkg.files.find((file) => file.role === "mesh_glb");

const existing: ModelingDecision = {
  decisionId: "33333333-3333-4333-8333-333333333333",
  packageId,
  element: "Floor 1 · stair opening",
  decision: "linked mesh as reference only; native stair not modeled",
  sources: [{ path: mesh?.path ?? "" }],
  decidedBy: { name: "Robin Revit", userId: "44444444-4444-4444-8444-444444444444" },
  decidedAt: "2026-10-16T19:05:00Z",
};

function freshStation() {
  return createFakeStation({
    projects: [example.project],
    packages: [structuredClone(example.pkg)],
    verdicts: { [packageId]: example.verdict },
    decisions: { [packageId]: [structuredClone(existing)] },
  });
}

async function renderDecisions() {
  return render(await DecisionsPage({ params: Promise.resolve({ packageId }) }));
}

afterEach(() => {
  cleanup();
  state.session = null;
  cacheMock.revalidatePath.mockClear();
});

describe("decision log", () => {
  it("lists logged decisions with author and time from the station", async () => {
    const station = freshStation();
    state.session = sessionFor(["bim"], station);
    await renderDecisions();
    const list = screen.getByRole("list", { name: "Logged decisions" });
    const items = within(list).getAllByRole("listitem");
    expect(items).toHaveLength(1);
    expect(items[0]?.textContent).toContain("Floor 1 · stair opening");
    expect(items[0]?.textContent).toContain(existing.decision);
    expect(items[0]?.textContent).toContain("Robin Revit");
    // Shown in Eastern Time with the zone named.
    expect(formatDateTime(existing.decidedAt)).toBe("Oct 16, 2026, 3:05 PM EDT");
    expect(items[0]?.textContent).toContain("Robin Revit · Oct 16, 2026, 3:05 PM EDT");
    expect(
      within(items[0] as HTMLElement)
        .getByText(/3:05 PM/)
        .getAttribute("datetime"),
    ).toBe(existing.decidedAt);
  });

  it("saves a decision through the station from the form and lists it with author and time", async () => {
    const station = freshStation();
    station.author = { name: "Dana BIM", userId: "11111111-1111-4111-8111-111111111111" };
    station.now = "2026-10-17T15:42:07Z";
    state.session = sessionFor(["bim"], station);
    await renderDecisions();

    const form = screen.getByRole("form", { name: "Log a decision" });
    fireEvent.change(within(form).getByLabelText("Element or area"), {
      target: { value: "Floor 1 · kitchen east wall" },
    });
    fireEvent.change(within(form).getByLabelText("Source used"), {
      target: { value: dxf?.path },
    });
    fireEvent.change(within(form).getByLabelText("Decision"), {
      target: { value: "Modeled as native Revit wall, 4 520 mm" },
    });
    fireEvent.change(within(form).getByLabelText("Remaining uncertainty and next check"), {
      target: { value: "Wall thickness unknown; verify at demo" },
    });
    await act(async () => {
      fireEvent.click(within(form).getByRole("button", { name: "Save decision" }));
    });

    await waitFor(() => expect(screen.getByText("Decision saved.")).toBeTruthy());
    const posts = station.calls.filter(
      (call) => call.method === "POST" && call.path === `/packages/${packageId}/modeling-decisions`,
    );
    expect(posts).toHaveLength(1);
    expect(posts[0]?.authorization).toBe("Bearer test-access-token");
    expect(posts[0]?.body).toEqual({
      element: "Floor 1 · kitchen east wall",
      decision: "Modeled as native Revit wall, 4 520 mm",
      sources: [{ path: dxf?.path }],
      note: "Wall thickness unknown; verify at demo",
    });
    expect(cacheMock.revalidatePath).toHaveBeenCalledWith(`/packages/${packageId}/decisions`);

    // Next.js re-renders the page after revalidatePath; the list now shows the new entry.
    cleanup();
    await renderDecisions();
    const items = within(screen.getByRole("list", { name: "Logged decisions" })).getAllByRole(
      "listitem",
    );
    expect(items).toHaveLength(2);
    const saved = items[1] as HTMLElement;
    expect(saved.textContent).toContain("Floor 1 · kitchen east wall");
    expect(saved.textContent).toContain("Modeled as native Revit wall, 4 520 mm");
    expect(saved.textContent).toContain("Wall thickness unknown; verify at demo");
    expect(saved.textContent).toContain("Floor 1 / plan.dxf");
    expect(saved.textContent).toContain("Dana BIM · Oct 17, 2026, 11:42 AM EDT");
  });

  it("shows the station's rule violation and keeps the entered values", async () => {
    const station = freshStation();
    state.session = sessionFor(["admin"], station);
    const form = new FormData();
    form.set("packageId", packageId);
    form.set("element", "Floor 2 · hall");
    form.set("source", "Original Exports/not-in-package.dxf");
    form.set("decision", "Taken from the plan");
    const result = await saveDecision({ status: "idle", attempt: 0 }, form);
    expect(result.status).toBe("error");
    if (result.status !== "error") {
      return;
    }
    expect(result.message).toContain("not a file of the package");
    expect(result.values.element).toBe("Floor 2 · hall");
    expect(cacheMock.revalidatePath).not.toHaveBeenCalled();
  });

  it("validates required fields before calling the station", async () => {
    const station = freshStation();
    state.session = sessionFor(["bim"], station);
    const form = new FormData();
    form.set("packageId", packageId);
    form.set("element", " ");
    const result = await saveDecision({ status: "idle", attempt: 0 }, form);
    expect(result.status).toBe("error");
    expect(station.calls.filter((call) => call.method === "POST")).toHaveLength(0);
  });
});
