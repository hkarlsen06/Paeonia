import Link from 'next/link';
import type { Locale } from '@/lib/i18n/config';
import { getDictionary } from '@/lib/i18n/dictionaries';
import { buildLocalizedPath } from '@/lib/paths';
import { SiteShell } from './SiteShell';

interface SupportPageProps {
  locale: Locale;
}

export function SupportPage({ locale }: SupportPageProps) {
  const dictionary = getDictionary(locale);

  return (
    <SiteShell locale={locale}>
      <main className="page-shell narrow">
        <p className="kicker">{dictionary.support.kicker}</p>
        <h1>{dictionary.support.title}</h1>
        <p className="lede">{dictionary.support.description}</p>
        <div className="actions">
          <a className="button" href="mailto:support@paeonia.no">
            support@paeonia.no
          </a>
          <Link className="button secondary" href={buildLocalizedPath(locale)}>
            {dictionary.support.back}
          </Link>
        </div>
      </main>
    </SiteShell>
  );
}
