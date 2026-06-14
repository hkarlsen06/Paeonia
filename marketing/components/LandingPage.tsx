import Link from 'next/link';
import type { Locale } from '@/lib/i18n/config';
import type { Dictionary } from '@/lib/i18n/dictionaries';
import { buildLocalizedPath } from '@/lib/paths';
import { SiteShell } from './SiteShell';

interface LandingPageProps {
  locale: Locale;
  dictionary: Dictionary;
}

export function LandingPage({ locale, dictionary }: LandingPageProps) {
  const content = dictionary.marketing.home;

  return (
    <SiteShell locale={locale}>
      <main className="page-shell">
        <section className="notice">
          <h1>{content.title}</h1>
          <p className="lede">{content.description}</p>
          <p>{content.note}</p>
          <div className="actions">
            <Link className="button" href={buildLocalizedPath(locale, '/support')}>
              {content.supportCta}
            </Link>
            <Link className="button secondary" href={buildLocalizedPath(locale, '/privacy')}>
              {content.privacyCta}
            </Link>
          </div>
        </section>
      </main>
    </SiteShell>
  );
}
