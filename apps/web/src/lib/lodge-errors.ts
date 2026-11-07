import { safeUserMessage } from "./user-message";
import { translateUiText } from "./ui-translation";
export function lodgeUserMessage(error: unknown, language: "en" | "sw") {
  const e = error as { code?: string; message?: string };
  const text = `${e?.code ?? ""} ${e?.message ?? ""}`.toLowerCase();
  let message = "";
  if (text.includes("23p01") || text.includes("exclusion constraint"))
    message =
      "This room is already reserved for those dates. Choose another room or change the dates.";
  else if (text.includes("23505"))
    message =
      "This room identifier, receipt reference or invitation already exists.";
  else if (text.includes("42501") || text.includes("permission denied"))
    message =
      "You do not have permission for this lodge. Sign in with an authorized account.";
  else if (text.includes("check-in requires"))
    message = "Check-in needs a confirmed stay today and a ready, active room.";
  else if (text.includes("same-day turnover"))
    message = "Same-day checkout and check-in are disabled in lodge settings.";
  else if (text.includes("capacity") || text.includes("guest count"))
    message = "The guest count exceeds the selected room capacity.";
  else if (
    text.includes("dates") ||
    text.includes("departure") ||
    text.includes("arrival")
  )
    message =
      "Choose valid arrival and departure dates. Departure must be after arrival.";
  else if (text.includes("invitation unavailable"))
    message = "This invitation has expired or belongs to a different account.";
  return message
    ? String(translateUiText(language, message))
    : safeUserMessage(error, language);
}
