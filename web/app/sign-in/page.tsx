// "/sign-in" — the sign-in page, in the review screen's look instead of the Auth.js default
// page. Auth.js sends sign-in and its errors here (auth.ts pages); the proxy serves it without a
// session. Shows no data and does not echo the error code.

import type { Metadata } from "next";
import { Notice } from "@/components/Notice";
import { AppHeader } from "@/components/PageFrame";
import { safeReturnPath } from "@/lib/auth-redirect";
import { startSignIn } from "./actions";

export const dynamic = "force-dynamic";

export const metadata: Metadata = { title: "Sign in · Capture review · Chapter" };

interface SignInPageProps {
  readonly searchParams: Promise<Record<string, string | string[] | undefined>>;
}

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

export default async function SignInPage({ searchParams }: SignInPageProps) {
  const query = await searchParams;
  const callbackUrl = safeReturnPath(first(query.callbackUrl));
  const failed = first(query.error) !== undefined;
  return (
    <>
      <AppHeader />
      <main className="frame">
        <div className="main">
          <div className="page-title">
            <h1>Sign in</h1>
            <span className="page-title__meta">
              Use your Chapter Microsoft account to see projects, capture packages, verdicts and
              files.
            </span>
          </div>
          {failed ? (
            <Notice role="alert" title="Sign-in did not finish">
              Try again. If it keeps happening, ask a Chapter admin.
            </Notice>
          ) : null}
          <form action={startSignIn}>
            <input type="hidden" name="callbackUrl" value={callbackUrl} />
            <button type="submit" className="button-primary">
              Sign in with Microsoft
            </button>
          </form>
        </div>
      </main>
    </>
  );
}
