import Link from 'next/link';
import type { Locale } from '@/lib/i18n/config';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { buildLocalizedPath } from '@/lib/paths';
import { LocaleToggle } from './LocaleToggle';

interface SiteShellProps {
  children: React.ReactNode;
  locale: Locale;
  /** The current page without the locale prefix, so the language toggle stays on it. */
  path?: string;
}

export function SiteShell({ children, locale, path }: SiteShellProps) {
  const footer = getMarketingDictionary(locale).marketing.footer;

  return (
    <div className="flex min-h-dvh flex-col">
      <header className="relative z-10 mx-auto flex w-full max-w-6xl items-center justify-between gap-5 px-5 pb-4 pt-[max(1.25rem,env(safe-area-inset-top))] sm:px-8">
        <Link
          href={buildLocalizedPath(locale)}
          className="inline-flex items-center gap-2.5 text-lg font-semibold tracking-[-0.03em] text-text-primary"
        >
          <img src="/brand/paeonia-mark-tight.svg" alt="" width="32" height="32" className="h-8 w-8" />
          Paeonia
        </Link>
        <LocaleToggle locale={locale} path={path} />
      </header>

      {children}

      <footer className="mt-auto border-t border-white/8 px-5 py-10 sm:px-8">
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-4 text-sm sm:flex-row sm:items-center sm:justify-between">
          <p className="text-text-muted">{footer.copyright}</p>
          <nav aria-label={footer.footerNavigationLabel} className="flex flex-wrap gap-x-6 gap-y-2">
            <Link href={buildLocalizedPath(locale, '/privacy')} className="text-text-secondary transition-colors hover:text-text-primary">
              {footer.privacy}
            </Link>
            <Link href={buildLocalizedPath(locale, '/terms')} className="text-text-secondary transition-colors hover:text-text-primary">
              {footer.terms}
            </Link>
            <Link href={buildLocalizedPath(locale, '/support')} className="text-text-secondary transition-colors hover:text-text-primary">
              {footer.support}
            </Link>
          </nav>
        </div>
      </footer>
    </div>
  );
}
