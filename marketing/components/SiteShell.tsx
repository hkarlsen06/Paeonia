import Link from 'next/link';
import type { Locale } from '@/lib/i18n/config';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { buildLocalizedPath } from '@/lib/paths';
import { ScrollReveal } from './ScrollReveal';
import { SiteHeader } from './SiteHeader';

interface SiteShellProps {
  children: React.ReactNode;
  locale: Locale;
}

export function SiteShell({ children, locale }: SiteShellProps) {
  const dictionary = getMarketingDictionary(locale);
  const footer = dictionary.marketing.footer;
  const year = new Date().getFullYear();

  return (
    <div className="site-frame">
      <ScrollReveal />
      <SiteHeader
        locale={locale}
        navLabel={footer.headerNavigationLabel}
        privacyLabel={footer.privacy}
        supportLabel={footer.support}
      />
      {children}
      <footer className="site-footer">
        <div className="footer-top">
          <nav className="footer-links" aria-label={footer.footerNavigationLabel}>
            <Link href={buildLocalizedPath(locale, '/privacy')}>{footer.privacy}</Link>
            <Link href={buildLocalizedPath(locale, '/terms')}>{footer.terms}</Link>
            <Link href={buildLocalizedPath(locale, '/support')}>{footer.support}</Link>
          </nav>
        </div>
        <div className="footer-bottom">
          © {year} Paeonia · {footer.note}
        </div>
      </footer>
    </div>
  );
}
