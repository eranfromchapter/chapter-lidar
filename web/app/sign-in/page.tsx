// "/sign-in" — the sign-in page in the HUB look (web-review §6.7) instead of the Auth.js default
// page. Auth.js sends sign-in and its errors here (auth.ts pages); the proxy serves it without a
// session. Shows no data and does not echo the error code.

import type { Metadata } from "next";
import { Button } from "@/components/hub/Button";
import { Card } from "@/components/hub/Card";
import { SoloPage } from "@/components/SoloPage";
import { safeReturnPath } from "@/lib/auth-redirect";
import { startSignIn } from "./actions";

export const dynamic = "force-dynamic";

export const metadata: Metadata = { title: "Sign in · Capture review" };

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
    <SoloPage>
      <Card padding="lg">
        <div className="hub-stack hub-stack--16">
          <h1 className="page-title">Sign in</h1>
          <p className="text-14" style={{ margin: 0 }}>
            Use your Chapter Microsoft account to see projects, capture packages, verdicts and
            files.
          </p>
          {failed ? (
            <div role="alert" className="alert-box">
              <strong>Sign-in did not finish</strong>
              <span>Try again. If it keeps happening, ask a Chapter admin.</span>
            </div>
          ) : null}
          <form action={startSignIn}>
            <input type="hidden" name="callbackUrl" value={callbackUrl} />
            <Button type="submit" variant="primary" size="md" fullWidth>
              Sign in with Microsoft
            </Button>
          </form>
        </div>
      </Card>
    </SoloPage>
  );
}
