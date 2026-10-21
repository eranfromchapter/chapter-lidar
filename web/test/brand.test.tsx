// @vitest-environment jsdom
// The HUB look with Chapter's own brand (web-review §2, B1, B2, WR-AC1, WR-AC2, WR-AC10): the HUB
// "chapter" wordmark byte for byte, Inter 400/600 from public/brand only, the HUB tokens, no
// Lato, no Times, no Google fonts, no typed "RENOVATION" wordmark.

import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import NotFound from "@/app/not-found";
import ReviewNotFound from "@/app/(review)/not-found";
import ReviewLoading from "@/app/(review)/loading";
import { configErrorResponse } from "@/lib/config";

const ROOT = process.env.CHAPTER_REPO_ROOT ?? "";
const WEB = join(ROOT, "web");
const WORDMARK_SHA256 = "8621b72b323ef1394a205fe6ba29f84b2c4ad0cff23fc883f9ee23947a8f2d71";

function sha256(path: string): string {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

/** Every source file of the review screen's pages, components and libraries. */
function sources(): string[] {
  const out: string[] = [];
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) {
        walk(path);
      } else if (/\.(tsx?|css)$/.test(name)) {
        out.push(path);
      }
    }
  };
  for (const dir of ["app", "components", "lib"]) {
    walk(join(WEB, dir));
  }
  return out;
}

afterEach(() => {
  cleanup();
});

describe("wordmark", () => {
  it("is the HUB's chapter wordmark, byte for byte, next to the logo in tools/brand", () => {
    const web = join(WEB, "public/brand/chapter-wordmark.svg");
    const tools = join(ROOT, "tools/brand/chapter-wordmark.svg");
    expect(sha256(web)).toBe(WORDMARK_SHA256);
    expect(sha256(tools)).toBe(WORDMARK_SHA256);
    const svg = readFileSync(web, "utf8");
    expect(svg).toContain('viewBox="0 0 147 33.8"');
    expect(svg).toContain('fill="#221f1f"');
    expect(readFileSync(join(WEB, "public/brand/NOTICE.md"), "utf8")).toContain(
      "chapter-wordmark.svg",
    );
  });

  it("is never replaced by a typed wordmark or the Chapter Renovation logo", () => {
    for (const file of sources()) {
      const text = readFileSync(file, "utf8");
      expect(text, file).not.toMatch(/RENOVATION/);
      expect(text, file).not.toContain("chapter-logo.svg");
    }
  });
});

describe("stylesheets", () => {
  const globals = readFileSync(join(WEB, "app/globals.css"), "utf8");
  const hub = readFileSync(join(WEB, "app/hub.css"), "utf8");

  it("load Inter Regular and SemiBold from public/brand only, with no @import", () => {
    const urls = [...`${globals}\n${hub}`.matchAll(/url\(([^)]*)\)/g)].map((match) =>
      (match[1] ?? "").replace(/["']/g, ""),
    );
    expect(urls).toEqual(["/brand/inter-400.woff2", "/brand/inter-600.woff2"]);
    for (const url of urls) {
      expect(existsSync(join(WEB, "public", url)), url).toBe(true);
    }
    expect(globals).not.toContain("@import");
    expect(hub).not.toContain("@import");
    expect(readFileSync(join(WEB, "app/layout.tsx"), "utf8")).toMatch(
      /import "\.\/globals\.css";\nimport "\.\/hub\.css";/,
    );
  });

  it("never name Lato, Times or a Google font host", () => {
    for (const file of sources()) {
      const text = readFileSync(file, "utf8");
      for (const banned of ["googleapis", "gstatic", "Lato", "Times"]) {
        expect(text.includes(banned), `${file}: ${banned}`).toBe(false);
      }
    }
  });

  it("carry the HUB tokens with Inter for every text and SemiBold for bold", () => {
    expect(globals).toMatch(/--font-sans: Inter, /);
    expect(globals).toContain("--font-display: var(--font-sans);");
    expect(globals).toContain("--fw-bold: 600;");
    expect(globals).toContain("font-synthesis: none;");
    expect(globals).toContain("--mint-400: #30e3ca;");
    expect(globals).toContain("--accent: var(--mint-400);");
    expect(globals).toContain("--surface-page: var(--gray-100);");
    expect(globals).toContain("--surface-inverse: var(--ink-900);");
    expect(globals).toContain("--radius-pill: 100px;");
    expect(globals).toContain("--sidebar-width: 248px;");
    expect(hub).toMatch(/\.hub-btn \{[^}]*border-radius: var\(--radius-pill\);/);
    expect(hub).toMatch(/\.sidebar__wordmark \{[^}]*filter: brightness\(0\) invert\(1\);/);
  });
});

describe("pages outside the data", () => {
  it("not found, outside the shell, shows the wordmark and links back to the projects", () => {
    render(<NotFound />);
    expect(screen.getByRole("img", { name: "Chapter" }).getAttribute("src")).toBe(
      "/brand/chapter-wordmark.svg",
    );
    expect(screen.getByRole("heading", { level: 2 }).textContent).toBe("Not found");
    expect(screen.getByText("There is no project, package or page at this address.")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Back to the projects" }).getAttribute("href")).toBe(
      "/",
    );
  });

  it("not found inside the shell has its topbar title", () => {
    render(<ReviewNotFound />);
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Not found");
  });

  it("loading shows static skeleton rows and no data", () => {
    const { container } = render(<ReviewLoading />);
    expect(container.querySelectorAll(".skeleton-row")).toHaveLength(5);
    expect(screen.getByRole("status").textContent).toBe("Loading");
  });

  it('loading is not a second main: the streamed page keeps the only <main id="main">', () => {
    const { container } = render(<ReviewLoading />);
    expect(container.querySelector("main")).toBeNull();
    expect(container.querySelector("#main")).toBeNull();
    expect(container.querySelector(".page")?.getAttribute("aria-busy")).toBe("true");
  });

  it("the configuration page uses the HUB look, the wordmark and Inter", async () => {
    const html = await configErrorResponse().text();
    expect(html).toContain('src="/brand/chapter-wordmark.svg"');
    expect(html).toContain('url("/brand/inter-400.woff2")');
    expect(html).toContain("background:#f1f1f1");
    expect(html).toContain("Capture review is not configured");
    expect(html).not.toMatch(/Times|chapter-logo|googleapis/);
  });
});
