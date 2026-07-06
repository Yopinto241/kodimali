"use client";

import { useMemo, useState } from "react";

import { DirectMediaImage } from "@/components/direct-media-image";

type MediaItem = {
  media_type?: string | null;
  signed_url?: string | null;
  display_order?: number | null;
};

export function ListingMediaGallery({
  media,
  title,
}: {
  media: MediaItem[];
  title: string;
}) {
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [fullscreenOpen, setFullscreenOpen] = useState(false);

  const visibleMedia = useMemo(
    () =>
      media.filter(
        (item) => typeof item.signed_url === "string" && item.signed_url.trim().length > 0,
      ),
    [media],
  );

  const selected = visibleMedia[selectedIndex];

  if (visibleMedia.length === 0 || !selected?.signed_url) {
    return null;
  }

  const mainMedia = (
    <div className="overflow-hidden rounded-[20px] border border-brand-border bg-brand-card-soft">
      {selected.media_type === "video" ? (
        <video
          className="aspect-[16/10] w-full bg-black object-contain"
          controls
          playsInline
          preload="metadata"
        >
          <source src={selected.signed_url} type="video/mp4" />
        </video>
      ) : (
        <button
          type="button"
          onClick={() => setFullscreenOpen(true)}
          className="block w-full cursor-zoom-in bg-transparent p-0"
        >
          <DirectMediaImage
            src={selected.signed_url}
            alt={`${title} media ${selectedIndex + 1}`}
            priority
            sizes="(min-width: 1280px) 52vw, (min-width: 1024px) 58vw, 100vw"
            className="aspect-[16/10] w-full object-cover"
          />
        </button>
      )}
    </div>
  );

  return (
    <>
      <div className="mt-8">
        <div className="flex items-center justify-between gap-3">
          <p className="eyebrow">Media</p>
          <p className="text-sm font-semibold text-muted">
            {selectedIndex + 1} / {visibleMedia.length}
          </p>
        </div>
        <div className="mt-4 space-y-4">
          {mainMedia}
          {visibleMedia.length > 1 ? (
            <div className="grid grid-cols-4 gap-3 sm:grid-cols-6">
              {visibleMedia.map((item, index) => (
                <button
                  key={`${item.signed_url}-${index}`}
                  type="button"
                  onClick={() => setSelectedIndex(index)}
                  className={`overflow-hidden rounded-2xl border bg-brand-card-soft transition ${
                    index === selectedIndex
                      ? "border-brand-navy shadow-[0_12px_24px_rgba(11,31,58,0.12)]"
                      : "border-brand-border hover:border-brand-border-strong"
                  }`}
                >
                  {item.media_type === "video" ? (
                    <div className="flex aspect-square items-center justify-center bg-brand-navy text-white">
                      <span className="text-xs font-bold">VIDEO</span>
                    </div>
                  ) : (
                    <DirectMediaImage
                      src={item.signed_url!}
                      alt={`${title} thumbnail ${index + 1}`}
                      sizes="160px"
                      className="aspect-square w-full object-cover"
                    />
                  )}
                </button>
              ))}
            </div>
          ) : null}
        </div>
      </div>

      {fullscreenOpen && selected.media_type !== "video" ? (
        <div className="fixed inset-0 z-[90] bg-black/88 p-4">
          <div className="mx-auto flex h-full max-w-7xl flex-col">
            <div className="flex justify-end">
              <button
                type="button"
                onClick={() => setFullscreenOpen(false)}
                className="rounded-full bg-white/12 px-4 py-2 text-sm font-semibold text-white"
              >
                Close
              </button>
            </div>
            <div className="flex flex-1 items-center justify-center">
              <DirectMediaImage
                src={selected.signed_url}
                alt={`${title} fullscreen ${selectedIndex + 1}`}
                priority
                sizes="100vw"
                className="max-h-[84vh] w-auto max-w-full rounded-[20px] object-contain"
              />
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}
