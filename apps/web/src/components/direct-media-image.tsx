import Image from "next/image";

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
    <Image
      src={src}
      alt={alt}
      className={className}
      width={1200}
      height={1200}
      quality={72}
      priority={priority}
      sizes={sizes}
    />
  );
}
