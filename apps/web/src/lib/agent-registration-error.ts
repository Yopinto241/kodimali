export const registrationUnavailable = "Sorry, we could not complete your registration just now. Please try again shortly, or contact KODIMALI support for help.";

/** Only actionable, application-owned messages may cross the registration UI. */
export function agentRegistrationError(error: unknown): string {
  const value = error && typeof error === "object" ? error as { code?: string; message?: string; status?: number } : {};
  const code = value.code ?? "";
  const message = (value.message ?? "").toLowerCase();
  if (/abort|timed out|timeout/.test(message) || (error instanceof Error && error.name === "AbortError")) return "Sorry, we could not confirm your registration in time. Please try signing in before registering again, or contact KODIMALI support.";
  if (/100 saved areas|maximum.*areas/.test(message)) return "This ward already has the maximum number of saved areas. Please choose a saved area or contact KODIMALI support.";
  if ((value.status ?? 0) >= 500 || /database|sqlstate|internal server|column reference|relation .*exist/.test(message)) return registrationUnavailable;
  if (/email_exists|user_already_exists/.test(code) || /user already registered|email.*already/.test(message)) return "An account may already exist with these details. Please sign in or reset your password instead of registering again.";
  if (/username.*(use|taken)|username.*unavailable/.test(message)) return "That username is already in use. Please choose another username.";
  if (/phone.*(linked|use|registered)/.test(message)) return "That phone number is already linked to an account. Please sign in or use another number.";
  if (/weak_password/.test(code) || /password.*(least|short|weak)/.test(message)) return "Please choose a stronger password with at least 6 characters.";
  if (/email_address_invalid|email_address_not_authorized/.test(code) || /invalid.*email|email.*invalid/.test(message)) return "Please check your email address and try again.";
  if (/rate_limit|over_email_send_rate_limit/.test(code) || /too many requests|rate limit/.test(message)) return "Please wait a few minutes before trying again.";
  if (/location|operating area/.test(message)) return "Please choose your region, district, ward and operating area before continuing.";
  if (/category/.test(message)) return "Please choose an available service category before continuing.";
  if (/nida/.test(message)) return "Please check your NIDA number and try again. Contact KODIMALI support if you need help.";
  if (/network|failed to fetch|fetch failed/.test(message)) return "Please check your internet connection and try again.";
  return registrationUnavailable;
}
