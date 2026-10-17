// Auth.js routes (sign-in, callback, sign-out, session). Missing settings fail closed with the
// configuration page instead of Auth.js's generic server error.

import type { NextRequest } from "next/server";
import { handlers } from "@/auth";
import { configProblems, failClosed } from "@/lib/config";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest): Promise<Response> {
  const problems = configProblems();
  if (problems.length > 0) {
    return failClosed(problems);
  }
  return handlers.GET(request);
}

export async function POST(request: NextRequest): Promise<Response> {
  const problems = configProblems();
  if (problems.length > 0) {
    return failClosed(problems);
  }
  return handlers.POST(request);
}
