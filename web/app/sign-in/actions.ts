"use server";

// Server action behind the sign-in button: starts the Microsoft Entra sign-in. The return path
// comes from the form, so it is reduced to a path on this site first; Auth.js checks it again.

import { signIn } from "@/auth";
import { safeReturnPath } from "@/lib/auth-redirect";

export async function startSignIn(form: FormData): Promise<void> {
  const callbackUrl = form.get("callbackUrl");
  await signIn("microsoft-entra-id", {
    redirectTo: safeReturnPath(typeof callbackUrl === "string" ? callbackUrl : undefined),
  });
}
