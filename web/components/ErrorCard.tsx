"use client";

// "Something went wrong" (web-review §6.7): no data and no internal detail, only the reference
// of the error for an admin.

import { Button } from "./hub/Button";
import { Card } from "./hub/Card";

export interface ErrorCardProps {
  readonly digest?: string;
  readonly reset: () => void;
}

export function ErrorCard({ digest, reset }: ErrorCardProps) {
  return (
    <Card padding="md" role="alert">
      <div className="hub-stack hub-stack--10">
        <h2 className="page-title">Something went wrong</h2>
        <p className="text-14" style={{ margin: 0 }}>
          The review screen could not load this page, so nothing is shown. If it keeps happening,
          send the reference below to a Chapter admin.
        </p>
        {digest === undefined ? null : (
          <span className="text-12 text-muted">
            Reference <span className="mono">{digest}</span>
          </span>
        )}
        <span>
          <Button variant="primary" size="sm" onClick={reset}>
            Try again
          </Button>
        </span>
      </div>
    </Card>
  );
}
