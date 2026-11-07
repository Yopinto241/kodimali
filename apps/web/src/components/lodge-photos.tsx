"use client";
import { useEffect, useState } from "react";
import { getLodgeClient } from "@/lib/lodge-client";
import { DirectMediaImage } from "./direct-media-image";
export function LodgePhotos({ paths }: { paths: unknown }) {
  const key = Array.isArray(paths)
    ? paths.filter((x) => typeof x === "string").join("|")
    : "";
  const [images, setImages] = useState<{ key: string; urls: string[] }>({
    key: "",
    urls: [],
  });
  useEffect(() => {
    let active = true;
    if (key) {
      void getLodgeClient()
        .storage.from("lodge-media")
        .createSignedUrls(key.split("|"), 3600)
        .then((r) => {
          if (active)
            setImages({
              key,
              urls: (r.data ?? []).flatMap((x) =>
                x.signedUrl ? [x.signedUrl] : [],
              ),
            });
        });
    }
    return () => {
      active = false;
    };
  }, [key]);
  if (!key || images.key !== key) return null;
  return (
    <div className="flex gap-3 overflow-x-auto rounded-xl">
      {images.urls.map((url, i) => (
        <div key={url} className="h-40 w-56 shrink-0 bg-[#edf5f1]">
          <DirectMediaImage
            src={url}
            alt={`Lodge photo ${i + 1}`}
            className="h-full w-full object-contain"
            sizes="224px"
          />
        </div>
      ))}
    </div>
  );
}
