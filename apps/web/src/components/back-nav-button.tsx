"use client";
import { UiButton, UiText } from "@/components/ui-text";

import { useNavigate } from "@/components/navigation-progress";

type BackNavButtonProps = {
  fallbackHref?: string;
  label?: string;
};

export function BackNavButton({
  fallbackHref = "/",
  label = "Back",
}: BackNavButtonProps) {
  const navigate = useNavigate();

  return (
    <UiButton
      type="button"
      onClick={() => {
        if (window.history.length > 1) {
          window.history.back();
          return;
        }
        navigate(fallbackHref);
      }}
      className="back-nav-button"
      aria-label={label}
      title={label}
    >
      <svg aria-hidden="true" viewBox="0 0 24 24" fill="none"><path d="M15 18l-6-6 6-6" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" /></svg>
      <span className="sr-only"><UiText text={label} /></span>
    </UiButton>
  );
}
