interface PhoneScreenshotProps {
  src: string;
  alt: string;
  className?: string;
  priority?: boolean;
}

// A real simulator screenshot in a thin bezel. Sizes are in container units, so the
// bezel and the iPhone corner radius scale with whatever width the caller sets.
export function PhoneScreenshot({ src, alt, className = '', priority = false }: PhoneScreenshotProps) {
  return (
    <div className={`@container ${className}`}>
      <div className="rounded-[15.3cqw] bg-[#0d0509] p-[2.2cqw] shadow-[0_40px_90px_-24px_rgba(8,1,5,0.85)] ring-1 ring-white/12">
        <img
          src={src}
          alt={alt}
          width={780}
          height={1696}
          loading={priority ? 'eager' : 'lazy'}
          fetchPriority={priority ? 'high' : undefined}
          decoding="async"
          className="block h-auto w-full rounded-[13.1cqw]"
        />
      </div>
    </div>
  );
}
