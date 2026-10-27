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
      className="back-nav-button"
      aria-label={label}
      title={label}
    >
      <svg aria-hidden="true" viewBox="0 0 24 24" fill="none"><path d="M15 18l-6-6 6-6" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" /></svg>
      <span className="sr-only">{label}</span>
    </button>
  );
}
