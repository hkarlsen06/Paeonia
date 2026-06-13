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
  return (
    <SiteShell locale={locale}>
      <main className="page-shell">
        <section className="hero">
          <div className="hero-copy">
            <p className="kicker">{dictionary.home.kicker}</p>
            <h1>{dictionary.home.title}</h1>
            <p className="lede">{dictionary.home.lede}</p>
            <div className="actions">
              <Link className="button" href={buildLocalizedPath(locale, '/support')}>
                {dictionary.home.primaryAction}
              </Link>
              <Link className="button secondary" href={buildLocalizedPath(locale, '/privacy')}>
                {dictionary.home.secondaryAction}
              </Link>
            </div>
          </div>

          <div className="product-card checkin-card" aria-label={dictionary.home.previewLabel}>
            <div className="answer-row">
              <strong>{dictionary.home.previewQuestion}</strong>
              <p>{dictionary.home.previewAnswerOne}</p>
            </div>
            <div className="answer-row">
              <strong>{dictionary.home.previewPartner}</strong>
              <p>{dictionary.home.previewAnswerTwo}</p>
            </div>
          </div>
        </section>

        <section className="sections" aria-label={dictionary.home.sectionsLabel}>
          {dictionary.home.sections.map((section) => (
            <article className="section-card" key={section.title}>
              <h3>{section.title}</h3>
              <p>{section.body}</p>
            </article>
          ))}
        </section>
      </main>
    </SiteShell>
  );
}
