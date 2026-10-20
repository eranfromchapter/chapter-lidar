// @vitest-environment jsdom
// Chapter brand on the review screen: the header shows the Chapter logo (not a typed wordmark),
// the stylesheet loads Inter from public/brand with the brand font stacks, and a missing page
// keeps the review screen's look.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import NotFound from "@/app/not-found";
import { PageFrame } from "@/components/PageFrame";
import type { Viewer } from "@/lib/viewer";

/** web/ of this checkout (CHAPTER_REPO_ROOT is set by vitest.config.ts). */
const WEB = join(process.env.CHAPTER_REPO_ROOT ?? "", "web");

const viewer: Viewer = {
  name: "Dana BIM",
  userId: "11111111-1111-4111-8111-111111111111",
  roles: ["bim"],
  canReview: true,
};

afterEach(() => {
  cleanup();
});

describe("page frame", () => {
  it("shows the Chapter logo image, linked home, instead of a typed wordmark", () => {
    render(
      <PageFrame viewer={viewer} nav={null}>
        <p>Page body</p>
      </PageFrame>,
    );
    const header = screen.getByRole("banner");
    const home = within(header).getByRole("link", {
      name: "Chapter Renovation, capture review home",
    });
    expect(home.getAttribute("href")).toBe("/");
    const logo = within(home).getByRole("img", { name: "Chapter Renovation" });
    expect(logo.getAttribute("src")).toBe("/brand/chapter-logo.svg");
    // The size attributes keep the logo's 1756:635 proportions.
    const width = Number(logo.getAttribute("width"));
    const height = Number(logo.getAttribute("height"));
    expect(width / height).toBeCloseTo(1756 / 635, 2);
    expect(header.textContent).not.toContain("RENOVATION");
    expect(within(header).queryByText("chapter")).toBeNull();
    expect(header.textContent).toContain("Capture review");
    expect(header.textContent).toContain("Dana BIM · BIM operator");
  });

  it("uses the logo file from public/brand, drawn at 1756:635", () => {
    const svg = readFileSync(join(WEB, "public/brand/chapter-logo.svg"), "utf8");
    expect(svg).toContain('viewBox="0 0 1756 635"');
    expect(svg).toContain('aria-label="Chapter Renovation"');
  });
});

describe("stylesheet", () => {
  const css = readFileSync(join(WEB, "app/globals.css"), "utf8");

  it("loads Inter Regular and SemiBold from public/brand only", () => {
    const urls = [...css.matchAll(/url\("([^"]+)"\)/g)].map((match) => match[1] ?? "");
    expect(urls).toEqual(["/brand/inter-400.woff2", "/brand/inter-600.woff2"]);
    for (const url of urls) {
      expect(existsSync(join(WEB, "public", url)), url).toBe(true);
    }
    expect(css).not.toContain("@import");
  });

  it("sets Times for titles and Inter for all other text", () => {
    expect(css).toContain('--font-display: Times, "Times New Roman", serif;');
    expect(css).toContain('--font-body: Inter, "Helvetica Neue", Helvetica, Arial, sans-serif;');
  });
});

describe("not-found page", () => {
  it("keeps the review screen's frame and links back to the projects", () => {
    render(<NotFound />);
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Not found");
    const back = screen.getByRole("link", { name: "Back to the projects" });
    expect(back.getAttribute("href")).toBe("/");
  });
});
