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
      priority={priority}
      loading={priority ? "eager" : "lazy"}
      sizes={sizes}
      onError={onError}
    />
  );
}
