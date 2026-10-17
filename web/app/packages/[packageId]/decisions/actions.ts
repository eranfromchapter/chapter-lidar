"use server";

// Server action behind the decision form. Treated as an untrusted entry point: it checks the
// session and the role itself (render-time gating is not a boundary), validates the form and
// lets the station record the author and time.

import { revalidatePath } from "next/cache";
import { formValues, parseDecisionForm, type DecisionFormState } from "@/lib/decisions";
import { StationError } from "@/lib/station";
import { getViewerSession } from "@/lib/viewer";

function stationMessage(error: StationError): string {
  switch (error.status) {
    case 401:
      return "Your sign-in has expired. Sign in again and save the decision.";
    case 403:
      return "Your account cannot log modeling decisions.";
    case 404:
      return "The station has no package with this id.";
    case 400:
    case 422: {
      const details = error.fieldErrors.map((item) => item.message).join("; ");
      return `The station rejected the decision${details.length > 0 ? `: ${details}` : "."}`;
    }
    default:
      return "The station could not save the decision. Try again in a moment.";
  }
}

export async function saveDecision(
  previous: DecisionFormState,
  form: FormData,
): Promise<DecisionFormState> {
  const attempt = (Number.isSafeInteger(previous?.attempt) ? previous.attempt : 0) + 1;
  const session = await getViewerSession();
  if (session === null) {
    return {
      status: "error",
      attempt,
      message: "Your sign-in has expired. Sign in again and save the decision.",
      values: formValues(form),
    };
  }
  if (!session.viewer.canReview) {
    return {
      status: "error",
      attempt,
      message: "Only BIM operators and admins can log modeling decisions.",
      values: formValues(form),
    };
  }
  const parsed = parseDecisionForm(form);
  if (!parsed.ok) {
    return { status: "error", attempt, message: parsed.message, values: parsed.values };
  }
  try {
    await session.station.createModelingDecision(parsed.packageId, parsed.input);
  } catch (error) {
    if (error instanceof StationError) {
      return {
        status: "error",
        attempt,
        message: stationMessage(error),
        values: formValues(form),
      };
    }
    throw error;
  }
  revalidatePath(`/packages/${parsed.packageId}/decisions`);
  return { status: "saved", attempt, message: "Decision saved." };
}
