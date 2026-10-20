// @vitest-environment jsdom
// The sign-in page: the review screen's header with the Chapter logo instead of the Auth.js
// default page, a sign-in button that starts the Entra sign-in, and a return path that never
// leaves this site.

import { cleanup, render, screen, within } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { safeReturnPath } from "@/lib/auth-redirect";

const signIn = vi.hoisted(() => vi.fn(async () => undefined));

vi.mock("@/auth", () => ({ signIn }));

const { default: SignInPage } = await import("@/app/sign-in/page");
const { startSignIn } = await import("@/app/sign-in/actions");

async function renderPage(query: Record<string, string>) {
  return render(await SignInPage({ searchParams: Promise.resolve(query) }));
}

afterEach(() => {
  cleanup();
  signIn.mockClear();
});

describe("sign-in page", () => {
  it("shows the Chapter logo, the title and the sign-in button", async () => {
    const { container } = await renderPage({ callbackUrl: "/packages/abc?x=1" });
    const header = screen.getByRole("banner");
    const logo = within(header).getByRole("img", { name: "Chapter Renovation" });
    expect(logo.getAttribute("src")).toBe("/brand/chapter-logo.svg");
    expect(header.textContent).toContain("Capture review");
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Sign in");
    expect(screen.getByRole("button", { name: "Sign in with Microsoft" })).toBeTruthy();
    expect(screen.queryByRole("alert")).toBeNull();
    const callback = container.querySelector<HTMLInputElement>('input[name="callbackUrl"]');
    expect(callback?.value).toBe("/packages/abc?x=1");
  });

  it("says sign-in did not finish after an Auth.js error, without echoing the code", async () => {
    const { container } = await renderPage({ error: "<b>OAuthCallbackError</b>" });
    expect(within(screen.getByRole("alert")).getByText("Sign-in did not finish")).toBeTruthy();
    expect(container.textContent).not.toContain("OAuthCallbackError");
  });

  it("keeps only a path on this site as the return path", async () => {
    const { container } = await renderPage({ callbackUrl: "https://elsewhere.example/steal" });
    const callback = container.querySelector<HTMLInputElement>('input[name="callbackUrl"]');
    expect(callback?.value).toBe("/steal");
  });
});

describe("sign-in action", () => {
  it("starts the Microsoft Entra sign-in back to the given path", async () => {
    const form = new FormData();
    form.set("callbackUrl", "/projects/example-deal-0001");
    await startSignIn(form);
    expect(signIn).toHaveBeenCalledWith("microsoft-entra-id", {
      redirectTo: "/projects/example-deal-0001",
    });
  });

  it("returns to the project list when the form's path is unsafe or missing", async () => {
    const form = new FormData();
    form.set("callbackUrl", "//elsewhere.example");
    await startSignIn(form);
    await startSignIn(new FormData());
    expect(signIn.mock.calls).toEqual([
      ["microsoft-entra-id", { redirectTo: "/" }],
      ["microsoft-entra-id", { redirectTo: "/" }],
    ]);
  });
});

describe("return path after sign-in", () => {
  it.each([
    ["/packages/abc/decisions", "/packages/abc/decisions"],
    ["/?q=12%20Example", "/?q=12%20Example"],
    ["http://localhost:3000/projects/x?y=1", "/projects/x?y=1"],
    ["https://elsewhere.example/x", "/x"],
    ["//elsewhere.example/x", "/x"],
    ["/\\elsewhere.example", "/"],
    ["/.//elsewhere.example", "/"],
    ["javascript:alert(1)", "/"],
    ["/sign-in?callbackUrl=%2F", "/"],
    ["", "/"],
    [undefined, "/"],
  ])("%s becomes %s", (value, expected) => {
    expect(safeReturnPath(value)).toBe(expected);
  });
});
