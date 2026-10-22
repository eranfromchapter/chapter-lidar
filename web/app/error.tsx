"use client";

// Error page for anything outside the review pages (for example the shell itself), in the HUB
// look without the shell. Shows no data and no internal detail.

import { ErrorCard } from "@/components/ErrorCard";
import { SoloPage } from "@/components/SoloPage";

export default function ErrorPage({
  error,
  reset,
}: {
  readonly error: Error & { digest?: string };
  readonly reset: () => void;
}) {
  return (
    <SoloPage>
      <ErrorCard {...(error.digest === undefined ? {} : { digest: error.digest })} reset={reset} />
    </SoloPage>
  );
}
