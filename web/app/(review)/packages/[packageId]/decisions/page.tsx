// "/packages/[packageId]/decisions" — the v1 decision log page. The log is now a card of the
// package page; old links keep working through a permanent redirect to it.

import { permanentRedirect } from "next/navigation";

interface DecisionsPageProps {
  readonly params: Promise<{ packageId: string }>;
}

export default async function DecisionsPage({ params }: DecisionsPageProps) {
  const { packageId } = await params;
  permanentRedirect(`/packages/${encodeURIComponent(packageId)}#decisions`);
}
