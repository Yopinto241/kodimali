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
  const [generatedPoster, setGeneratedPoster] = useState<string | undefined>(
    poster ?? undefined,
  );
  const [posterAttempted, setPosterAttempted] = useState(Boolean(poster));
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
      ([entry]) => setNearViewport(entry.isIntersecting),
      { rootMargin: "320px" },
    );
    observer.observe(video);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (nearViewport) videoRef.current?.load();
  }, [nearViewport, src]);

  function captureUsefulFrame() {
    const video = videoRef.current;
    if (!video || posterAttempted || !video.videoWidth || !video.videoHeight) return;
    setPosterAttempted(true);
    try {
      const size = Math.min(video.videoWidth, video.videoHeight);
      const canvas = document.createElement("canvas");
      canvas.width = 640;
      canvas.height = wide ? Math.round(640 * video.videoHeight / video.videoWidth) : 640;
      const context = canvas.getContext("2d");
      if (!context) return;
      const sourceX = (video.videoWidth - size) / 2;
      const sourceY = (video.videoHeight - size) / 2;
      if (wide) context.drawImage(video, 0, 0, video.videoWidth, video.videoHeight, 0, 0, canvas.width, canvas.height);
      else context.drawImage(video, sourceX, sourceY, size, size, 0, 0, 640, 640);
      setGeneratedPoster(canvas.toDataURL("image/jpeg", 0.82));
    } catch {
      // The video itself remains visible if browser CORS prevents canvas use.
    }
  }

  function seekForPoster() {
    if (autoPlay) return;
    const video = videoRef.current;
    if (!video || poster || posterAttempted) return;
    const target = Number.isFinite(video.duration)
      ? Math.min(Math.max(video.duration * 0.08, 0.35), 1.5)
      : 0.5;
    if (Math.abs(video.currentTime - target) > 0.1) video.currentTime = target;
  }

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
      poster={generatedPoster}
      onLoadedMetadata={seekForPoster}
      onSeeked={captureUsefulFrame}
    >
      {nearViewport ? <source src={src} /> : null}
    </video>
  );
}
