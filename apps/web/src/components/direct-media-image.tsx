import Image from "next/image";

type DirectMediaImageProps = {
  src: string;
  alt: string;
  className?: string;
  sizes?: string;
  priority?: boolean;
  onError?: () => void;
};

export function DirectMediaImage({
  src,
  alt,
  className,
  sizes,
  priority = false,
  onError,
}: DirectMediaImageProps) {
  return (
    <Image
      src={src}
      alt={alt}
      className={className}
      width={1200}
      height={1200}
      quality={72}
      // This deployment has no IMAGES binding. Its Next image proxy returns
      // original bytes for every requested width; use the cached origin directly
      // rather than adding a second fetch and duplicate width-specific copies.
      unoptimized={src.includes(".supabase.co/storage/v1/")}
      fetchPriority={priority ? "high" : undefined}
      loading={priority ? "eager" : "lazy"}
      sizes={sizes}
      onError={onError}
    />
  );
}
