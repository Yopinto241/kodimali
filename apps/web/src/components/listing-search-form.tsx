"use client";

import { useNavigate } from "@/components/navigation-progress";
import { createPortal } from "react-dom";
import { useEffect, useRef, useState } from "react";
import { UiText } from "@/components/ui-text";
import { revealListingFilterError, validateListingFilterForm } from "@/lib/listing-filter-validation";
import { useHydrated } from "@/lib/use-hydrated";

export function ListingSearchForm({ children, autoSubmitSelects = true, ...props }: React.ComponentProps<"form"> & { autoSubmitSelects?: boolean }) {
  const navigate = useNavigate();
  const ready = useHydrated();
  const ref = useRef<HTMLFormElement>(null);
  const [error, setError] = useState("");
  const [errorTarget, setErrorTarget] = useState<Element | null>(null);
  useEffect(() => {
    const form = ref.current;
    const report = (event: Event) => {
      setErrorTarget(form?.querySelector(".search-price-popover, .category-price-panel") ?? null);
      setError(String((event as CustomEvent).detail));
    };
    form?.addEventListener("kodimali-filter-error", report);
    return () => form?.removeEventListener("kodimali-filter-error", report);
  }, []);
  function submit(form: HTMLFormElement) {
    const problem = validateListingFilterForm(form);
    if (problem) { revealListingFilterError(form, problem); return false; }
    setError("");
    const query = new URLSearchParams();
    for (const [key, value] of new FormData(form)) {
      if (typeof value === "string" && value.trim() && !(key === "sort" && value === "recommended")) query.set(key, value.trim());
    }
    const path = form.getAttribute("action") || "/listings";
    navigate(query.size ? `${path}?${query}` : path);
    return true;
  }
  return <form {...props} ref={ref} noValidate action={props.action ?? "/listings"} onSubmit={(event) => {
    event.preventDefault(); submit(event.currentTarget);
  }} onChange={(event) => {
    const field = event.target;
    if (autoSubmitSelects && field instanceof HTMLSelectElement && ["category", "sort"].includes(field.name) && field.form) {
      if (!submit(field.form)) field.value = new URLSearchParams(window.location.search).get(field.name) ?? (field.name === "sort" ? "recommended" : "");
    } else if (error && !validateListingFilterForm(event.currentTarget)) setError("");
  }}><fieldset className="contents" disabled={!ready} aria-busy={!ready}>{children}</fieldset>{error && (errorTarget ? createPortal(<p role="alert" className="col-span-full rounded-xl bg-white p-3 font-semibold !text-[#842b25]"><UiText text={error} /></p>, errorTarget) : <p role="alert" className="mt-3 rounded-xl bg-white p-3 font-semibold text-[#842b25]"><UiText text={error} /></p>)}</form>;
}
