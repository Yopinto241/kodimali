const messages = {
  connection: ["Connection unavailable. Check your internet and try again.", "Muunganisho haupatikani. Angalia intaneti kisha ujaribu tena."],
  timeout: ["We could not confirm the result. Check your account before trying again.", "Hatukuweza kuthibitisha matokeo. Angalia akaunti yako kabla ya kujaribu tena."],
  session: ["Your session expired. Please sign in again.", "Kipindi chako kimeisha. Ingia tena."],
  denied: ["You do not have permission to do this.", "Huna ruhusa ya kufanya hili."],
  payment: ["Payment verification is pending. Check the status before paying again.", "Uhakiki wa malipo unasubiri. Angalia hali kabla ya kulipa tena."],
  unavailable: ["This option is no longer available. Please choose another.", "Chaguo hili halipatikani tena. Tafadhali chagua jingine."],
  login: ["The email or password is incorrect.", "Barua pepe au nenosiri si sahihi."],
  other: ["We could not complete the request. Please try again.", "Hatukuweza kukamilisha ombi. Tafadhali jaribu tena."],
} as const;
export function safeUserMessage(error: unknown, language: "en"|"sw"="en") {
  const value = error && typeof error === "object" && "message" in error ? String(error.message) : String(error);
  const key = /timeout|timed out|abort/i.test(value) ? "timeout" : /network|connection|fetch|socket/i.test(value) ? "connection" :
    /invalid login|invalid credentials/i.test(value) ? "login" : /session|jwt|401/i.test(value) ? "session" :
    /permission|forbidden|42501/i.test(value) ? "denied" : /payment|verification pending/i.test(value) ? "payment" :
    /not available|no longer available/i.test(value) ? "unavailable" : "other";
  return messages[key][language==="sw"?1:0];
}
