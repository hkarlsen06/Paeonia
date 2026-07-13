import Link from 'next/link';
import type { Locale } from '@/lib/i18n/config';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { buildLocalizedPath } from '@/lib/paths';
import { SiteShell } from './SiteShell';

interface SupportPageProps {
  locale: Locale;
}

export function SupportPage({ locale }: SupportPageProps) {
  const dictionary = getMarketingDictionary(locale);
  const content = dictionary.marketing.support;
  const supportEmail = dictionary.legal.supportEmail;
  const contactEmail = dictionary.legal.contactEmail;

  return (
    <SiteShell locale={locale}>
      <main className="page-shell narrow">
        <h1>{content.title}</h1>
        <p className="lede">{content.description}</p>
        <p className="label">{content.emailLabel}</p>
        <div className="actions">
          <a className="button" href={`mailto:${supportEmail}`}>
            {supportEmail}
          </a>
          <a className="button secondary" href={`mailto:${contactEmail}`}>
            {contactEmail}
          </a>
          <Link className="button secondary" href={buildLocalizedPath(locale)}>
            {content.back}
          </Link>
        </div>
      </main>
    </SiteShell>
  );
}
