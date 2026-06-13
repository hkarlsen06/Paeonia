import type { Locale } from '@/lib/i18n/config';
import { getDictionary } from '@/lib/i18n/dictionaries';
import { SiteShell } from './SiteShell';

interface LegalPageProps {
  locale: Locale;
  variant: 'privacy' | 'terms';
}

export function LegalPage({ locale, variant }: LegalPageProps) {
  const dictionary = getDictionary(locale);
  const content = dictionary[variant];

  return (
    <SiteShell locale={locale}>
      <main className="page-shell narrow">
        <p className="kicker">{content.updated}</p>
        <h1>{content.title}</h1>
        <p className="lede">{content.description}</p>

        <div className="legal-content">
          {content.sections.map((section) => (
            <section key={section.title}>
              <h2>{section.title}</h2>
              {section.body.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </section>
          ))}
        </div>
      </main>
    </SiteShell>
  );
}
