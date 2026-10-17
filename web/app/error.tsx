"use client";

// Error page for anything a page could not handle (for example an incomplete configuration or
// an unexpected station answer). Shows no data and no internal detail.

export default function ErrorPage({
  error,
  reset,
}: {
  readonly error: Error & { digest?: string };
  readonly reset: () => void;
}) {
  return (
    <main className="frame">
      <div className="main">
        <div className="page-title">
          <h1>Something went wrong</h1>
          <span className="page-title__meta">
            The review screen could not load this page, so nothing is shown. If it keeps happening,
            send the reference below to a Chapter admin.
          </span>
        </div>
        {error.digest === undefined ? null : (
          <span className="caption">
            Reference <span className="mono">{error.digest}</span>
          </span>
        )}
        <span>
          <button type="button" className="button-primary" onClick={reset}>
            Try again
          </button>
        </span>
      </div>
    </main>
  );
}
