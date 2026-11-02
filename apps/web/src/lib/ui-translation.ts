import copy from "./ui-copy.json";
import aliases from "./ui-aliases.json";
import templates from "./ui-templates.json";

const translations: Readonly<Record<string, string>> = copy;
const legacy: Readonly<Record<string, string>> = aliases;
const english = new Map(Object.entries(translations).map(([en, sw]) => [sw, en]));
const normalize = (text: string) => text.replace(/\s+/g, " ").trim();
export const protectedUiTerms = ["apartment", "book", "booking"] as const;
const escapePattern = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const templatePatterns = templates.flatMap(pair => pair.map(source => ({
  pair,
  pattern: new RegExp(`^${source.split(/\{\d+\}/).map(escapePattern).join("(.+?)")}$`),
})));

// Exact application-copy lookup only. Never translate substrings of names, descriptions, addresses, IDs or submitted form values.
export function translateUiText(language: "sw" | "en", value: unknown): string {
  if (value == null) return "";
  const original = String(value);
  const text = normalize(original);
  if (protectedUiTerms.some(term => term === text.toLowerCase())) return original;
  const suffix = /^(.*?)(\s+\*|:)$/.exec(text);
  if (suffix) {
    const translated = translateUiText(language, suffix[1]);
    if (translated !== suffix[1]) return translated + suffix[2];
  }
  const key = legacy[text] ?? (Object.hasOwn(translations, text) ? text : english.get(text));
  if (!key) {
    for (const { pair, pattern } of templatePatterns) {
      const match = pattern.exec(text);
      if (match) return pair[language === "en" ? 0 : 1].replace(/\{(\d+)\}/g, (_, index) => {
        const value = match[Number(index) + 1];
        return /^(Search|View|Change this record|Listing changed|Payment status:|Assign|Remove) /.test(pair[0]) || pair[0].startsWith("{0} for this service") ? translateUiText(language, value) : value;
      });
    }
    return original;
  }
  const translated = language === "sw" ? translations[key] ?? original : key;
  return `${original.match(/^\s*/)?.[0] ?? ""}${translated}${original.match(/\s*$/)?.[0] ?? ""}`;
}

export function translateUiPrompt(value: string) {
  return translateUiText(typeof document !== "undefined" && document.documentElement.lang === "en" ? "en" : "sw", value);
}
