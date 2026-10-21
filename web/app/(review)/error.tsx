"use client";

// Error page inside the shell (web-review §6.7) for anything a review page could not handle.

import { ErrorCard } from "@/components/ErrorCard";

export default function ReviewError({
  error,
  reset,
}: {
  readonly error: Error & { digest?: string };
  readonly reset: () => void;
}) {
  return (
    <>
      <header className="topbar">
        <h1 className="topbar__title">Something went wrong</h1>
      </header>
      <main className="page" id="main">
        <ErrorCard
          {...(error.digest === undefined ? {} : { digest: error.digest })}
          reset={reset}
        />
      </main>
    </>
  );
}
