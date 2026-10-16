import Link from 'next/link';
import { ArrowDown, ArrowRight, Dice5, Hourglass, Mail, PenLine, Plus, Radio } from 'lucide-react';
import type { Locale } from '@/lib/i18n/config';
import type { Dictionary } from '@/lib/i18n/dictionaries';
import { buildLocalizedPath } from '@/lib/paths';
import { PhoneScreenshot } from './PhoneScreenshot';
import { SiteShell } from './SiteShell';

interface LandingPageProps {
  locale: Locale;
  dictionary: Dictionary;
}

function MailButton({ href, label, className = '' }: { href: string; label: string; className?: string }) {
  return (
    <a
      href={href}
      className={`inline-flex h-13 items-center justify-center gap-2.5 whitespace-nowrap rounded-full bg-white px-7 text-base font-semibold text-text-inverse shadow-[0_8px_32px_rgba(239,80,148,0.35)] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98] ${className}`}
    >
      <Mail aria-hidden="true" className="h-[1.1rem] w-[1.1rem] shrink-0" />
      {label}
    </a>
  );
}

function Glow({ className }: { className: string }) {
  return (
    <div
      aria-hidden="true"
      className={`pointer-events-none absolute -z-10 rounded-full bg-[radial-gradient(circle,rgba(239,80,148,0.42),rgba(239,80,148,0.16)_40%,transparent_70%)] ${className}`}
    />
  );
}

export function LandingPage({ locale, dictionary }: LandingPageProps) {
  const { hero, games, live, features, extras, privacy, faq, contact } = dictionary.marketing;
  const mailtoHref = `mailto:${dictionary.legal.contactEmail}?subject=${encodeURIComponent(
    contact.emailSubject,
  )}&body=${encodeURIComponent(contact.emailBody)}`;
  const screen = (name: string) => `/screens/${name}.webp`;
  const [homeShot, gameShot] = hero.screenshots;
  const liveIcons = [Radio, Dice5, PenLine, Hourglass];
  const [titleStart, titleEnd] = hero.title.split(hero.titleEmphasis);

  return (
    <SiteShell locale={locale}>
      <main className="pb-[calc(7rem+env(safe-area-inset-bottom))] text-text-primary lg:pb-0">
        <section className="relative isolate overflow-hidden px-5 sm:px-8">
          <Glow className="right-[-30%] top-[30%] h-[36rem] w-[36rem] lg:right-[2%] lg:top-[4%] lg:h-[46rem] lg:w-[46rem]" />

          <div className="mx-auto grid w-full max-w-6xl items-center gap-12 pb-16 pt-8 sm:pt-14 lg:min-h-[calc(100dvh-5rem)] lg:grid-cols-[minmax(0,1fr)_26rem] lg:gap-12 lg:py-10 xl:grid-cols-[minmax(0,1fr)_29rem]">
            <div>
              <h1 className="text-balance text-[2.75rem] font-semibold leading-[1.04] tracking-[-0.04em] sm:text-6xl lg:text-[4.5rem] xl:text-[5rem]">
                {titleStart}
                <em className="not-italic text-brand-highlight">{hero.titleEmphasis}</em>
                {titleEnd}
              </h1>
              <p className="mt-6 max-w-[34ch] text-pretty text-lg leading-relaxed text-text-secondary sm:text-xl">
                {hero.description}
              </p>
              <div className="mt-10 hidden flex-wrap items-center gap-x-7 gap-y-4 lg:flex">
                <MailButton href={mailtoHref} label={hero.primaryCta} />
                <a
                  href="#games"
                  className="inline-flex items-center gap-1.5 text-base font-medium text-text-muted transition-colors hover:text-text-primary"
                >
                  {hero.secondaryCta}
                  <ArrowDown aria-hidden="true" className="h-4 w-4" />
                </a>
              </div>
              <p className="mt-4 hidden pl-7 text-sm text-text-muted lg:block">{hero.note}</p>
            </div>

            <div className="relative isolate mx-auto flex w-[min(92vw,26rem)] items-start lg:w-full">
              <PhoneScreenshot
                src={screen(homeShot.src)}
                alt={homeShot.alt}
                priority
                className="w-[58%]"
              />
              <PhoneScreenshot
                src={screen(gameShot.src)}
                alt={gameShot.alt}
                priority
                className="-ml-[16%] mt-[14%] w-[58%]"
              />
            </div>
          </div>
        </section>

        <div className="fixed inset-x-0 bottom-0 z-30 border-t border-white/8 bg-background/85 px-5 pb-[calc(env(safe-area-inset-bottom)+0.75rem)] pt-3 backdrop-blur-xl lg:hidden">
          <MailButton href={mailtoHref} label={hero.primaryCta} className="w-full" />
          <p className="mt-2 text-center text-xs text-text-muted">{hero.note}</p>
        </div>

        <section id="games" aria-labelledby="games-heading" className="scroll-mt-4 overflow-x-clip px-5 pt-10 sm:px-8 lg:pt-16">
          <div className="relative isolate mx-auto max-w-6xl">
            <Glow className="left-1/2 top-[40%] h-[56rem] w-[56rem] -translate-x-1/2" />
            <div className="max-w-3xl">
              <h2
                id="games-heading"
                className="text-balance text-4xl font-semibold tracking-[-0.035em] sm:text-5xl lg:text-[3.5rem] lg:leading-[1.05]"
              >
                {games.title}
              </h2>
              <p className="mt-5 max-w-[50ch] text-pretty text-lg leading-relaxed text-text-secondary sm:text-xl">
                {games.description}
              </p>
            </div>

            <div className="-mx-5 mt-12 flex snap-x snap-mandatory gap-5 overflow-x-auto px-5 pb-6 [scrollbar-width:none] sm:-mx-8 sm:px-8 lg:mx-0 lg:grid lg:grid-cols-4 lg:gap-6 lg:overflow-visible lg:px-0">
              {games.screens.map((shot, index) => (
                <PhoneScreenshot
                  key={shot.src}
                  src={screen(shot.src)}
                  alt={shot.alt}
                  className={`w-[min(62vw,15rem)] shrink-0 snap-center lg:w-auto ${index % 2 === 1 ? 'lg:mt-16' : ''}`}
                />
              ))}
            </div>

            <div className="mt-12 grid gap-8 sm:grid-cols-3 sm:gap-10">
              {games.points.map((point) => (
                <div key={point.title} className="border-t border-brand-highlight/40 pt-5">
                  <h3 className="text-lg font-semibold tracking-[-0.02em]">{point.title}</h3>
                  <p className="mt-2 text-base leading-7 text-text-secondary">{point.description}</p>
                </div>
              ))}
            </div>

            <h3 className="mt-16 text-sm font-medium text-text-muted">{games.listHeading}</h3>
            <ul className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {games.list.map((game) => (
                <li key={game.name} className="rounded-2xl bg-surface-primary/70 p-5 ring-1 ring-white/8">
                  <p className="text-base font-semibold tracking-[-0.01em]">{game.name}</p>
                  <p className="mt-1.5 text-sm leading-6 text-text-secondary">{game.description}</p>
                </li>
              ))}
            </ul>
          </div>
        </section>

        <section id="live" aria-labelledby="live-heading" className="scroll-mt-4 overflow-x-clip px-5 sm:px-8">
          <div className="mx-auto mt-16 grid max-w-6xl items-center gap-12 border-t border-white/8 py-16 sm:mt-20 sm:py-20 lg:grid-cols-[minmax(0,1fr)_19rem] lg:gap-20">
            <div>
              <h2 id="live-heading" className="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl lg:text-[2.75rem] lg:leading-[1.1]">
                {live.title}
              </h2>
              <p className="mt-5 max-w-[46ch] text-pretty text-lg leading-relaxed text-text-secondary">{live.description}</p>

              <ul className="mt-10 grid gap-x-10 gap-y-8 sm:grid-cols-2">
                {live.items.map((item, index) => {
                  const Icon = liveIcons[index];
                  return (
                    <li key={item.title} className="flex gap-4">
                      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-surface-secondary ring-1 ring-white/10">
                        <Icon aria-hidden="true" className="h-5 w-5 text-brand-highlight" />
                      </span>
                      <div>
                        <h3 className="text-base font-semibold tracking-[-0.01em]">{item.title}</h3>
                        <p className="mt-1 text-base leading-7 text-text-secondary">{item.description}</p>
                      </div>
                    </li>
                  );
                })}
              </ul>
            </div>

            <div className="relative isolate flex justify-center">
              <Glow className="left-1/2 top-1/2 h-[40rem] w-[40rem] -translate-x-1/2 -translate-y-1/2" />
              <PhoneScreenshot src={screen(live.screenshot.src)} alt={live.screenshot.alt} className="w-[min(72vw,18rem)]" />
            </div>
          </div>
        </section>

        <section id="inside" className="scroll-mt-4 overflow-x-clip px-5 sm:px-8">
          <div className="mx-auto max-w-6xl">
            {features.items.map((item, index) => (
              <article
                key={item.title}
                className="grid items-center gap-12 border-t border-white/8 py-16 sm:py-20 lg:grid-cols-2 lg:gap-20"
              >
                <div className={index % 2 === 1 ? 'lg:order-last' : undefined}>
                  <h2 className="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl lg:text-[2.75rem] lg:leading-[1.1]">
                    {item.title}
                  </h2>
                  <p className="mt-5 max-w-[46ch] text-pretty text-lg leading-relaxed text-text-secondary">
                    {item.description}
                  </p>
                  <ul className="mt-7 space-y-3">
                    {item.points.map((point) => (
                      <li key={point} className="flex gap-3 text-base leading-7 text-text-secondary">
                        <span aria-hidden="true" className="mt-[0.7rem] h-1.5 w-1.5 shrink-0 rounded-full bg-brand-highlight" />
                        {point}
                      </li>
                    ))}
                  </ul>
                </div>

                <div className="relative isolate flex justify-center">
                  <Glow className="left-1/2 top-1/2 h-[44rem] w-[44rem] -translate-x-1/2 -translate-y-1/2" />
                  <div className="flex items-start">
                    {item.screens.map((shot, shotIndex) => (
                      <PhoneScreenshot
                        key={shot.src}
                        src={screen(shot.src)}
                        alt={shot.alt}
                        className={
                          shotIndex === 0 ? 'w-[min(46vw,16.5rem)]' : '-ml-[12%] mt-[18%] w-[min(46vw,16.5rem)]'
                        }
                      />
                    ))}
                  </div>
                </div>
              </article>
            ))}
          </div>
        </section>

        <section aria-labelledby="extras-heading" className="px-5 sm:px-8">
          <div className="mx-auto max-w-6xl border-t border-white/8 py-16 sm:py-20">
            <h2 id="extras-heading" className="text-2xl font-semibold tracking-[-0.03em] sm:text-3xl">
              {extras.heading}
            </h2>
            <div className="mt-10 grid gap-8 sm:grid-cols-2 sm:gap-10 lg:grid-cols-4">
              {extras.items.map((item) => (
                <div key={item.title} className="border-t border-brand-highlight/40 pt-5">
                  <h3 className="text-lg font-semibold tracking-[-0.02em]">{item.title}</h3>
                  <p className="mt-2 text-base leading-7 text-text-secondary">{item.description}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section aria-labelledby="privacy-heading" className="px-5 sm:px-8">
          <div className="mx-auto grid max-w-6xl gap-10 border-t border-white/8 py-16 sm:py-20 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:gap-20">
            <div>
              <h2 id="privacy-heading" className="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">
                {privacy.heading}
              </h2>
              <p className="mt-4 text-base leading-7 text-text-secondary">{privacy.description}</p>
              <Link
                href={buildLocalizedPath(locale, '/privacy')}
                className="mt-6 inline-flex items-center gap-1.5 text-sm font-medium text-text-primary transition-colors hover:text-brand-highlight"
              >
                {privacy.link}
                <ArrowRight aria-hidden="true" className="h-3.5 w-3.5" />
              </Link>
            </div>
            <ul className="border-t border-white/10">
              {privacy.items.map((item) => (
                <li key={item.title} className="grid gap-1 border-b border-white/10 py-6 sm:grid-cols-[14rem_minmax(0,1fr)] sm:gap-8">
                  <h3 className="text-base font-semibold tracking-[-0.01em] sm:text-lg">{item.title}</h3>
                  <p className="text-base leading-7 text-text-secondary">{item.description}</p>
                </li>
              ))}
            </ul>
          </div>
        </section>

        <section id="faq" aria-labelledby="faq-heading" className="scroll-mt-4 px-5 sm:px-8">
          <div className="mx-auto grid max-w-6xl gap-10 border-t border-white/8 py-16 sm:py-20 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:gap-20">
            <div className="lg:sticky lg:top-12 lg:self-start">
              <h2 id="faq-heading" className="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">
                {faq.heading}
              </h2>
              <p className="mt-4 text-base leading-7 text-text-secondary">{faq.description}</p>
              <a
                href={mailtoHref}
                className="mt-6 inline-flex items-center gap-1.5 text-sm font-medium text-text-primary transition-colors hover:text-brand-highlight"
              >
                {faq.contactLink}
                <ArrowRight aria-hidden="true" className="h-3.5 w-3.5" />
              </a>
            </div>

            <div className="border-t border-white/10">
              {faq.items.map((item, index) => (
                <details key={item.question} name="faq" open={index === 0} className="group border-b border-white/10">
                  <summary className="group/question flex cursor-pointer list-none items-start gap-4 py-5 sm:gap-6 sm:py-6 [&::-webkit-details-marker]:hidden">
                    <span className="mt-1 w-6 shrink-0 text-xs font-medium tabular-nums text-text-muted transition-colors group-open:text-brand-highlight sm:mt-1.5">
                      {String(index + 1).padStart(2, '0')}
                    </span>
                    <span className="flex-1 text-base font-medium text-text-primary transition-colors group-hover/question:text-brand-highlight sm:text-lg">
                      {item.question}
                    </span>
                    <Plus
                      aria-hidden="true"
                      className="mt-1 h-4 w-4 shrink-0 text-text-muted transition-transform duration-200 group-open:rotate-45 group-open:text-text-primary sm:mt-1.5"
                    />
                  </summary>
                  <div className="space-y-3 pb-6 pl-10 pr-8 sm:pl-12">
                    {item.answers.map((answer) => (
                      <p key={answer} className="text-base leading-7 text-text-secondary">
                        {answer}
                      </p>
                    ))}
                  </div>
                </details>
              ))}
            </div>
          </div>
        </section>

        <section className="px-5 pb-20 pt-4 sm:px-8 sm:pb-28">
          <div className="mx-auto flex max-w-3xl flex-col items-center rounded-[2rem] bg-[linear-gradient(110deg,#3a0f2a_0%,#6b1d4b_55%,#b8407a_100%)] px-6 py-12 text-center ring-1 ring-white/10 sm:py-16">
            <div className="flex h-16 w-16 items-center justify-center rounded-[22%] bg-[linear-gradient(160deg,#4f203a,#2a0b1e)] shadow-[0_10px_30px_rgba(0,0,0,0.35)] ring-1 ring-white/10">
              <img src="/brand/paeonia-mark-tight.svg" alt="" width="40" height="40" className="h-10 w-10" />
            </div>
            <h2 className="mt-6 text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">{contact.heading}</h2>
            <p className="mt-3 max-w-[40ch] text-pretty text-base leading-7 text-white/80">{contact.description}</p>
            <MailButton href={mailtoHref} label={contact.button} className="mt-8" />
          </div>
        </section>
      </main>
    </SiteShell>
  );
}
