// A problem or status card (web-review §6.8): a HUB card with a 16 px title, a sentence and an
// optional outline button.

import type { ReactNode } from "react";
import { Button } from "./hub/Button";
import { Card } from "./hub/Card";

export interface NoticeProps {
  readonly title: string;
  readonly children?: ReactNode;
  /** "alert" for errors, "status" for state such as checks running. */
  readonly role?: "alert" | "status";
  readonly action?: { readonly label: string; readonly href: string };
}

export function Notice({ title, children, role = "status", action }: NoticeProps) {
  return (
    <Card padding="md" role={role}>
      <div className="hub-stack hub-stack--8">
        <h2 className="hub-problem__title">{title}</h2>
        {children === undefined ? null : <p className="hub-problem__body">{children}</p>}
        {action === undefined ? null : (
          <span>
            <Button variant="outline" size="sm" href={action.href}>
              {action.label}
            </Button>
          </span>
        )}
      </div>
    </Card>
  );
}
