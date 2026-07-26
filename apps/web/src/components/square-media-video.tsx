"use client";

import { useRef, useState } from "react";

export function SquareMediaVideo({
  src,
  poster,
  autoPlay = true,
  controls = true,
  className = "",
}: {
  src: string;
  poster?: string | null;
  autoPlay?: boolean;
  controls?: boolean;
  className?: string;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [generatedPoster, setGeneratedPoster] = useState<string | undefined>(
    poster ?? undefined,
  );
  const [posterAttempted, setPosterAttempted] = useState(Boolean(poster));

  function captureUsefulFrame() {
    const video = videoRef.current;
    if (!video || posterAttempted || !video.videoWidth || !video.videoHeight) return;
    setPosterAttempted(true);
    try {
      const size = Math.min(video.videoWidth, video.videoHeight);
      const canvas = document.createElement("canvas");
      canvas.width = 640;
      canvas.height = 640;
      const context = canvas.getContext("2d");
      if (!context) return;
      const sourceX = (video.videoWidth - size) / 2;
      const sourceY = (video.videoHeight - size) / 2;
      context.drawImage(video, sourceX, sourceY, size, size, 0, 0, 640, 640);
      setGeneratedPoster(canvas.toDataURL("image/jpeg", 0.82));
    } catch {
      // The video itself remains visible if browser CORS prevents canvas use.
    }
  }

  function seekForPoster() {
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
      className={`aspect-square h-full w-full bg-brand-card-soft object-cover ${className}`}
      controls={controls}
      autoPlay={autoPlay}
      muted
      loop={autoPlay}
      playsInline
      preload="metadata"
      poster={generatedPoster}
      onLoadedMetadata={seekForPoster}
      onSeeked={captureUsefulFrame}
    >
      <source src={src} type="video/mp4" />
    </video>
  );
}
