import Link from 'next/link';
import type { Locale } from '@/lib/i18n/config';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { buildLocalizedPath } from '@/lib/paths';

interface SiteShellProps {
  children: React.ReactNode;
  locale: Locale;
}

export function SiteShell({ children, locale }: SiteShellProps) {
  const dictionary = getMarketingDictionary(locale);
  const footer = dictionary.marketing.footer;

  return (
    <div className="site-frame">
      <header className="site-header">
        <Link className="brand" href={buildLocalizedPath(locale)}>
          Paeonia
        </Link>
      </header>
      {children}
      <footer className="site-footer">
        <span>Paeonia</span>
        <nav className="footer-links" aria-label={footer.navigationLabel}>
          <Link href={buildLocalizedPath(locale, '/privacy')}>{footer.privacy}</Link>
          <Link href={buildLocalizedPath(locale, '/terms')}>{footer.terms}</Link>
          <Link href={buildLocalizedPath(locale, '/support')}>{footer.support}</Link>
        </nav>
      </footer>
    </div>
  );
}
