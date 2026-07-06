"use client";

import { useRouter } from "next/navigation";

type BackNavButtonProps = {
  fallbackHref?: string;
  label?: string;
};

export function BackNavButton({
  fallbackHref = "/",
  label = "Back",
}: BackNavButtonProps) {
  const router = useRouter();

  return (
    <button
      type="button"
      onClick={() => {
        if (window.history.length > 1) {
          router.back();
          return;
        }
        router.push(fallbackHref);
      }}
      className="inline-flex items-center gap-2 rounded-full border border-brand-border-strong bg-brand-card-soft px-4 py-2 text-sm font-semibold text-brand-navy transition hover:border-brand-navy hover:bg-white hover:text-brand-ink"
    >
      <span aria-hidden>&larr;</span>
      <span>{label}</span>
    </button>
  );
}
