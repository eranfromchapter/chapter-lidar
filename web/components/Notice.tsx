import type { ReactNode } from "react";

export interface NoticeProps {
  readonly title: string;
  readonly children?: ReactNode;
  /** "alert" for errors, "status" for state such as checks running. */
  readonly role?: "alert" | "status";
}

export function Notice({ title, children, role = "status" }: NoticeProps) {
  return (
    <div role={role} className="notice">
      <strong>{title}</strong>
      {children}
    </div>
  );
}
