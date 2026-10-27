"use client";

import { useState } from "react";

export function ListingShareButton({ title }: { title: string }) {
  const [copied, setCopied] = useState(false);

  async function share() {
    const url = window.location.href;
    if (navigator.share) {
      await navigator.share({ title, text: `${title} on KODIMALI`, url });
      return;
    }
    await navigator.clipboard.writeText(url);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 2000);
  }

  return (
    <button type="button" className="listing-icon-action" onClick={share} aria-label={copied ? "Link copied" : "Share listing"} title={copied ? "Link copied" : "Share"}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="18" cy="5" r="2.5"/><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="19" r="2.5"/><path d="m8.2 10.8 7.6-4.5M8.2 13.2l7.6 4.5"/></svg>
      <span className="sr-only">{copied ? "Link copied" : "Share listing"}</span>
    </button>
  );
}
