// @vitest-environment jsdom
// The pages behind the sidebar that are not drawn (web-review §6.5, §6.7): the global decision
// log for bim and admin, and the error pages that show no data.

import { act, cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ViewerSession } from "@/lib/viewer";
import { DEALS, drawnScenario, IDS } from "./support/scenarios";
import { createFakeStation, sessionFor } from "./support/station";

const state = vi.hoisted(() => ({ session: null as ViewerSession | null }));

vi.mock("@/lib/viewer", () => ({
  getViewerSession: async () => state.session,
  requireViewerSession: async () => state.session,
}));

const { default: DecisionLogPage } = await import("@/app/(review)/decisions/page");
const { default: ReviewError } = await import("@/app/(review)/error");
const { default: RootError } = await import("@/app/error");

const NOW = new Date("2026-10-21T18:00:00Z");

afterEach(() => {
  cleanup();
  state.session = null;
});

describe("decision log page", () => {
  it("lists every decision newest first, each linked to its package", async () => {
    const station = createFakeStation(drawnScenario(NOW));
    state.session = sessionFor(["admin"], station);
    render(await DecisionLogPage());
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Decision log");
    expect(
      screen.getByText("Every modeling decision logged against a capture package, newest first."),
    ).toBeTruthy();
    const entries = within(screen.getByRole("list", { name: "Modeling decisions" })).getAllByRole(
      "listitem",
    );
    expect(entries.map((entry) => entry.querySelector("b")?.textContent)).toEqual([
      "Room 4 ceiling",
      "Kitchen cabinetry",
      "Living Room walls",
    ]);
    const link = within(entries[0] as HTMLElement).getByRole("link", {
      name: "424 West End Ave, Apt 4K · Revision 1",
    });
    expect(link.getAttribute("href")).toBe(`/packages/${IDS.westEnd1}#decisions`);
    expect(entries[2]?.textContent).toContain("from Floor 1 / plan.dxf + Distance A (laser)");
    const listCall = station.calls.find((call) => call.path === "/modeling-decisions");
    expect(listCall?.search.get("limit")).toBe("100");
    expect(listCall?.search.get("dealId")).toBeNull();
    expect(screen.queryByText(/Showing the 100 newest/)).toBeNull();
  });

  it("names a project the station's lists do not know by its deal", async () => {
    const data = drawnScenario(NOW);
    const station = createFakeStation(data);
    const original = station.fetch;
    const station2 = {
      ...station,
      fetch: (async (input, init) => {
        if (String(input).includes("/review/projects")) {
          return new Response(JSON.stringify({ projects: [], truncated: false }), {
            headers: { "content-type": "application/json" },
          });
        }
        return original(input, init);
      }) as typeof fetch,
    };
    state.session = sessionFor(["bim"], station2);
    render(await DecisionLogPage());
    expect(
      screen.getAllByRole("link", { name: `HUB deal ${DEALS.westEnd} · Revision 1` }),
    ).toHaveLength(3);
  });

  it("says when there are no decisions", async () => {
    const data = drawnScenario(NOW);
    data.decisions = {};
    state.session = sessionFor(["bim"], createFakeStation(data));
    render(await DecisionLogPage());
    expect(screen.getByText("No decisions logged yet.")).toBeTruthy();
  });
});

describe("error pages", () => {
  it("show no detail, only the reference, and try again", async () => {
    const reset = vi.fn();
    render(
      <ReviewError
        error={Object.assign(new Error("secret detail"), { digest: "ab12cd" })}
        reset={reset}
      />,
    );
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Something went wrong");
    const card = screen.getByRole("alert");
    expect(card.textContent).toContain(
      "The review screen could not load this page, so nothing is shown. If it keeps happening, send the reference below to a Chapter admin.",
    );
    expect(card.textContent).toContain("Reference ab12cd");
    expect(card.textContent).not.toContain("secret detail");
    await act(async () => {
      fireEvent.click(within(card).getByRole("button", { name: "Try again" }));
    });
    expect(reset).toHaveBeenCalled();
    cleanup();
    render(<RootError error={new Error("x")} reset={reset} />);
    expect(screen.getByRole("img", { name: "Chapter" }).getAttribute("src")).toBe(
      "/brand/chapter-wordmark.svg",
    );
    expect(screen.queryByText(/Reference/)).toBeNull();
  });
});
