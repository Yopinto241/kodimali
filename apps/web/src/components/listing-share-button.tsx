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
    <button type="button" className="btn btn-outline" onClick={share}>
      {copied ? "Link copied" : "Share listing"}
    </button>
  );
}
