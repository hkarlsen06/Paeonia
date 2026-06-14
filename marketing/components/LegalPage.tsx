import type { Locale } from '@/lib/i18n/config';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { SiteShell } from './SiteShell';

interface LegalPageProps {
  locale: Locale;
  variant: 'privacy' | 'terms';
}

export function LegalPage({ locale, variant }: LegalPageProps) {
  const dictionary = getMarketingDictionary(locale);
  const content = dictionary.legal[variant];

  return (
    <SiteShell locale={locale}>
      <main className="page-shell narrow">
        <p className="label">{content.updated}</p>
        <h1>{content.title}</h1>
        <p className="lede">{content.meta.description}</p>

        <div className="legal-content">
          {content.sections.map((section) => (
            <section key={section.heading}>
              <h2>{section.heading}</h2>
              {section.paragraphs.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </section>
          ))}
        </div>
      </main>
    </SiteShell>
  );
}
