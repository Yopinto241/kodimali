"use client";

import { useEffect, useRef, useState } from "react";

export function SquareMediaVideo({
  src,
  poster,
  autoPlay = false,
  controls = true,
  className = "",
  wide = false,
  onError,
}: {
  src: string;
  poster?: string | null;
  autoPlay?: boolean;
  controls?: boolean;
  className?: string;
  wide?: boolean;
  onError?: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [nearViewport, setNearViewport] = useState(false);
  const visible = useRef(false);
  useEffect(() => {
    if (!autoPlay) return;
    const video = videoRef.current;
    if (!video) return;
    function update() {
      if (visible.current && !document.hidden) {
        if (video!.readyState >= 2) void video!.play().catch(() => {});
      } else video!.pause();
    }
    const observer = new IntersectionObserver(([entry]) => { visible.current = entry.intersectionRatio >= .5; update(); }, {threshold: [0, .5]});
    observer.observe(video);
    video.addEventListener("canplay", update);
    document.addEventListener("visibilitychange", update);
    return () => { observer.disconnect(); video.removeEventListener("canplay", update); document.removeEventListener("visibilitychange", update); video.pause(); };
  }, [autoPlay]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const observer = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) { setNearViewport(true); observer.disconnect(); } },
      { rootMargin: "320px" },
    );
    observer.observe(video);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (nearViewport) videoRef.current?.load();
  }, [nearViewport, src]);

  return (
    <video
      ref={videoRef}
      className={`${wide ? "aspect-video object-contain" : "aspect-square object-cover"} h-full w-full bg-brand-card-soft ${className}`}
      onError={onError}
      controls={controls}
      autoPlay={autoPlay}
      onPlay={() => { if (autoPlay && (!visible.current || document.hidden)) videoRef.current?.pause(); }}
      muted
      loop={autoPlay}
      playsInline
      preload={nearViewport ? "metadata" : "none"}
      poster={poster ?? undefined}
    >
      {nearViewport ? <source src={src} /> : null}
    </video>
  );
}
