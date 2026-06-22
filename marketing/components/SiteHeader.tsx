'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import type { Locale } from '@/lib/i18n/config';
import { buildLocalizedPath } from '@/lib/paths';

interface SiteHeaderProps {
  locale: Locale;
  privacyLabel: string;
  supportLabel: string;
  navLabel: string;
}

export function SiteHeader({ locale, privacyLabel, supportLabel, navLabel }: SiteHeaderProps) {
  const [elevated, setElevated] = useState(false);

  useEffect(() => {
    const onScroll = () => setElevated(window.scrollY > 12);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <header className="site-header" data-elevated={elevated}>
      <div className="site-header-inner">
        <Link className="brand" href={buildLocalizedPath(locale)}>
          <img src="/brand/paeonia-mark-tight.svg" alt="" width="34" height="34" />
          <span>Paeonia</span>
        </Link>
        <nav className="header-links" aria-label={navLabel}>
          <Link href={buildLocalizedPath(locale, '/privacy')}>{privacyLabel}</Link>
          <Link href={buildLocalizedPath(locale, '/support')}>{supportLabel}</Link>
        </nav>
      </div>
    </header>
  );
}
