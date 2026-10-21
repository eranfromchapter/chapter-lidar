// Empty state inside a table card (web-review §6.1): a muted box icon, a heading, a sentence and
// an optional action.

import type { ReactNode } from "react";
import { PackagesIcon } from "./icons";

export interface EmptyStateProps {
  readonly title: string;
  readonly body: string;
  readonly action?: ReactNode;
}

export function EmptyState({ title, body, action }: EmptyStateProps) {
  return (
    <div className="hub-empty">
      <span className="hub-empty__icon">
        <PackagesIcon size={32} />
      </span>
      <p className="hub-empty__title" style={{ margin: 0 }}>
        {title}
      </p>
      <p className="hub-empty__body" style={{ margin: 0 }}>
        {body}
      </p>
      {action}
    </div>
  );
}
