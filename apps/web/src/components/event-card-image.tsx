"use client";
import Image from "next/image";
import { useEffect, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";
export function EventCardImage({
  media,
  title,
  compact = false,
}: {
  media: unknown;
  title: string;
  compact?: boolean;
}) {
  const path =
    Array.isArray(media) && typeof media[0] === "string" ? media[0] : "";
  const [resolved, setResolved] = useState({ path: "", url: "" });
  const [failedPath, setFailedPath] = useState<string | null>(null);
  useEffect(() => {
    let active = true;
    if (path && !/^https?:\/\//.test(path))
      void getBrowserSupabase()
        .storage.from("listing-media")
        .createSignedUrl(path, 3600)
        .then(({ data }) => {
          if (active) setResolved({ path, url: data?.signedUrl ?? "" });
        });
    return () => {
      active = false;
    };
  }, [path]);
  const src = /^https?:\/\//.test(path)
    ? path
    : resolved.path === path
      ? resolved.url
      : "";
  return (
    <div className={compact ? "event-thumbnail" : "event-cover"}>
      {src && failedPath !== path ? (
        <Image
          src={src}
          alt={title}
          fill
          sizes={
            compact
              ? "72px"
              : "(max-width:640px) 100vw,(max-width:1024px) 50vw,33vw"
          }
          className="object-cover"
          onError={() => setFailedPath(path)}
        />
      ) : (
        <span aria-hidden="true">&#9671;</span>
      )}
    </div>
  );
}
