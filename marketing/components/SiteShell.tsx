import Link from 'next/link';
import type { Locale } from '@/lib/i18n/config';
import { buildLocalizedPath } from '@/lib/paths';

interface SiteShellProps {
  children: React.ReactNode;
  locale: Locale;
}

export function SiteShell({ children, locale }: SiteShellProps) {
  return (
    <div className="site-frame">
      <header className="site-header">
        <Link className="brand" href={buildLocalizedPath(locale)}>
          Paeonia
        </Link>
        <nav className="nav" aria-label="Main navigation">
          <Link href={buildLocalizedPath(locale, '/privacy')}>Privacy</Link>
          <Link href={buildLocalizedPath(locale, '/terms')}>Terms</Link>
          <Link href={buildLocalizedPath(locale, '/support')}>Support</Link>
        </nav>
      </header>
      {children}
      <footer className="site-footer">
        <span>Paeonia</span>
        <div className="footer-links">
          <Link href={buildLocalizedPath(locale, '/privacy')}>Privacy</Link>
          <Link href={buildLocalizedPath(locale, '/terms')}>Terms</Link>
          <Link href={buildLocalizedPath(locale, '/support')}>Support</Link>
        </div>
      </footer>
    </div>
  );
}
