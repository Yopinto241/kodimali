/* eslint-disable @next/next/no-img-element */

type DirectMediaImageProps = {
  src: string;
  alt: string;
  className?: string;
  sizes?: string;
  priority?: boolean;
};

export function DirectMediaImage({
  src,
  alt,
  className,
  sizes,
  priority = false,
}: DirectMediaImageProps) {
  return (
    <img
      src={src}
      alt={alt}
      className={className}
      loading={priority ? "eager" : "lazy"}
      decoding="async"
      fetchPriority={priority ? "high" : "auto"}
      sizes={sizes}
    />
  );
}
