import Link from 'next/link';
import type { CSSProperties } from 'react';
import { ArrowRight, Mail } from 'lucide-react';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { Button } from '@/components/ui/button';
import type { Locale } from '@/lib/i18n/config';
import type { Dictionary } from '@/lib/i18n/dictionaries';
import { buildLocalizedPath } from '@/lib/paths';

interface LandingPageProps {
  locale: Locale;
  dictionary: Dictionary;
}

type Preview = Dictionary['marketing']['hero']['preview'];

// Device geometry ported from the Tidex mockup. Model the visible black bezel
// (not the full chassis) so the frame stays physically proportioned.
// iPhone 17 Pro: 1206 x 2622 screen, 66.59 x 144.78mm, ~1.44mm bezel.
const screenAspectRatio = 1206 / 2622;
const screenWidthMm = 66.59;
const screenHeightMm = 144.78;
const visibleBezelMm = 1.44;
const horizontalBezelRatio = visibleBezelMm / screenWidthMm;
const verticalBezelRatio = visibleBezelMm / screenHeightMm;
const horizontalInset = horizontalBezelRatio / (1 + horizontalBezelRatio * 2);
const verticalInset = verticalBezelRatio / (1 + verticalBezelRatio * 2);
const phoneOuterAspectRatio =
  (screenAspectRatio * (1 + horizontalBezelRatio * 2)) / (1 + verticalBezelRatio * 2);

export function LandingPage({ locale, dictionary }: LandingPageProps) {
  const mobileBottomCtaHeight = 'calc(6.5rem + env(safe-area-inset-bottom))';
  const mobileHeroStyle = {
    '--mobile-hero-height': 'var(--hero-initial-dvh)',
    '--mobile-bottom-cta-height': mobileBottomCtaHeight,
    '--mobile-phone-fade-height': '15rem',
  } as CSSProperties;

  const marketing = dictionary.marketing;
  const hero = marketing.hero;
  const faqs = marketing.faq.items;
  const homeHref = buildLocalizedPath(locale);
  const privacyHref = buildLocalizedPath(locale, '/privacy');
  const termsHref = buildLocalizedPath(locale, '/terms');
  const supportHref = buildLocalizedPath(locale, '/support');
  const mailtoHref = `mailto:${dictionary.legal.contactEmail}?subject=${encodeURIComponent(
    marketing.contact.emailSubject,
  )}&body=${encodeURIComponent(marketing.contact.emailBody)}`;

  const phone = (wrapperClassName: string, phoneClassName: string, showAmbientGlow = true) => (
    <div className={wrapperClassName}>
      {showAmbientGlow ? (
        <div className="absolute left-1/2 top-1/2 -z-10 h-[28rem] w-[28rem] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle,rgba(239,80,148,0.2),rgba(239,80,148,0.08)_42%,transparent_72%)]" />
      ) : null}

      <div
        className={`relative inline-block overflow-hidden rounded-[3.15rem] bg-[linear-gradient(180deg,hsl(327_30%_20%)_0%,hsl(327_38%_13%)_22%,hsl(327_45%_8%)_100%)] ${phoneClassName}`}
        style={{
          aspectRatio: `${phoneOuterAspectRatio}`,
          boxShadow: '0 48px 120px rgba(15,4,11,0.6), inset 0 0 0 0.5px rgba(255,255,255,0.05)',
        }}
      >
        <div className="pointer-events-none absolute inset-0 z-20 rounded-[3.15rem] border border-white/10" />

        <div
          className="absolute overflow-hidden rounded-[2.9rem]"
          style={{
            left: `${horizontalInset * 100}%`,
            right: `${horizontalInset * 100}%`,
            top: `${verticalInset * 100}%`,
            bottom: `${verticalInset * 100}%`,
          }}
        >
          <AppScreen preview={hero.preview} />

          <div
            className="pointer-events-none absolute left-1/2 z-10 -translate-x-1/2 overflow-hidden rounded-full bg-[#0a0608] shadow-[0_4px_12px_rgba(0,0,0,0.26)]"
            style={{ top: '1.15%', width: '34.5%', height: '4.3%' }}
          >
            <div className="absolute inset-y-1/2 right-[20%] aspect-square h-[16%] -translate-y-1/2 rounded-full bg-[rgba(22,11,17,0.78)] opacity-40" />
            <div className="absolute inset-y-1/2 right-[9%] aspect-square h-[30%] -translate-y-1/2 rounded-full bg-[radial-gradient(circle_at_35%_35%,rgba(255,255,255,0.12),rgba(95,60,80,0.12)_20%,rgba(22,11,17,0.9)_52%,rgba(0,0,0,0.96)_100%)] opacity-60" />
          </div>

          <div className="pointer-events-none absolute inset-0 z-10 rounded-[2.9rem] border border-[#380F27]/10" />
        </div>
      </div>

      {showAmbientGlow ? (
        <div className="absolute bottom-0 left-1/2 -z-10 h-24 w-[78%] -translate-x-1/2 rounded-full bg-[radial-gradient(ellipse_at_center,rgba(239,80,148,0.18),transparent_72%)]" />
      ) : null}
    </div>
  );

  return (
    <main className="relative pb-[calc(6.5rem+env(safe-area-inset-bottom))] text-text-primary lg:pb-0">
      <section
        className="relative flex min-h-[var(--mobile-hero-height)] flex-col overflow-hidden px-5 pb-[var(--mobile-bottom-cta-height)] pt-[max(1rem,env(safe-area-inset-top))] sm:px-8 sm:pb-8 lg:min-h-dvh lg:pb-10"
        style={mobileHeroStyle}
      >
        <div className="pointer-events-none absolute inset-0 -z-10">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_130%_80%_at_50%_-15%,hsl(334_83%_63%_/_0.2),transparent_60%)]" />
          <div className="absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-background to-transparent" />
          <div className="absolute inset-x-0 top-0 h-px bg-linear-to-r from-transparent via-brand-highlight/20 to-transparent" />
        </div>

        <div className="mx-auto flex w-full max-w-6xl shrink-0 items-center justify-between py-4">
          <Link href={homeHref} className="inline-flex items-center gap-2.5" aria-label={hero.brandName}>
            <img src="/brand/paeonia-mark-tight.svg" alt="" className="h-9 w-9" />
            <span className="text-lg font-semibold tracking-tight text-text-primary">
              {hero.brandName}
            </span>
          </Link>
          <nav className="flex items-center gap-5 text-sm font-medium text-text-muted">
            <Link href={privacyHref} className="transition-colors hover:text-text-primary">
              {hero.navPrivacy}
            </Link>
            <Link href={supportHref} className="transition-colors hover:text-text-primary">
              {hero.navSupport}
            </Link>
          </nav>
        </div>

        <div className="mx-auto flex w-full max-w-6xl flex-1 flex-col lg:flex-row lg:items-center lg:gap-14 xl:gap-20">
          <div className="flex min-h-0 flex-1 flex-col py-10 sm:py-14 lg:max-w-140 lg:flex-none lg:py-0 xl:max-w-150">
            <p className="animate-fade-in text-sm font-semibold uppercase tracking-[0.14em] text-brand-highlight [animation-delay:40ms]">
              {hero.eyebrow}
            </p>
            <h1 className="mt-4 animate-fade-in text-balance text-[3rem] font-semibold leading-[1.02] tracking-[-0.045em] [animation-delay:80ms] sm:text-[3.6rem] lg:text-[4.1rem] xl:text-[4.6rem]">
              {hero.title}
            </h1>
            <p className="mt-5 max-w-[44ch] animate-fade-in text-pretty text-[1.0625rem] leading-[1.7] text-text-secondary [animation-delay:140ms] sm:text-lg lg:mb-10 xl:mb-12">
              {hero.description}
            </p>

            <div className="relative mb-2 mt-auto animate-fade-in pt-10 [animation-delay:160ms] lg:hidden">
              <div className="pointer-events-none absolute inset-0">
                <div className="absolute inset-x-0 top-0 flex justify-center">
                  <div className="h-[21rem] w-[21rem] -translate-y-[1.75rem] rounded-full bg-[radial-gradient(circle,rgba(239,80,148,0.16),rgba(239,80,148,0.06)_44%,transparent_72%)]" />
                </div>
              </div>
              <div className="relative mx-auto h-[20.5rem] w-full max-w-[21rem] overflow-visible">
                <div className="absolute inset-x-0 top-0 flex justify-center">
                  {phone('relative origin-top scale-[0.92]', 'w-[17.1rem]', false)}
                </div>
              </div>
            </div>

            <div className="relative z-10 hidden animate-fade-in flex-wrap items-center gap-5 [animation-delay:200ms] lg:mt-auto lg:flex lg:pt-0">
              <a
                href={mailtoHref}
                className="inline-flex h-12 items-center gap-2.5 whitespace-nowrap rounded-full bg-brand-highlight px-5 text-sm font-semibold text-text-inverse shadow-[0_2px_24px_rgba(242,126,178,0.28)] transition-all duration-200 hover:scale-[1.02] hover:brightness-105 active:scale-[0.98]"
              >
                <Mail className="h-[1.05rem] w-[1.05rem] shrink-0" />
                {hero.primaryCta}
              </a>
              <Link
                href="#faq"
                className="flex items-center gap-1.5 text-sm font-medium text-text-muted transition-colors hover:text-text-primary"
              >
                {hero.secondaryCta}
                <ArrowRight className="h-3.5 w-3.5" />
              </Link>
            </div>

            <p className="mt-6 hidden text-sm text-text-muted lg:block">{hero.trustNote}</p>
          </div>

          <div className="hidden animate-fade-in [animation-delay:160ms] lg:flex lg:flex-1 lg:items-center lg:justify-end">
            {phone('relative', 'w-[16.8rem] sm:w-[17.2rem]')}
          </div>
        </div>

        <div
          className="pointer-events-none absolute inset-x-0 bottom-0 z-20 lg:hidden"
          style={{
            height: 'calc(var(--mobile-phone-fade-height) + var(--mobile-bottom-cta-height))',
            background:
              'linear-gradient(to bottom, transparent 0%, transparent 18%, hsl(var(--background) / 0.32) 38%, hsl(var(--background) / 0.86) 62%, hsl(var(--background)) 78%, hsl(var(--background)) 100%)',
          }}
        />
      </section>

      <div className="fixed inset-x-0 bottom-0 z-30 lg:hidden">
        <div className="border-t border-white/8 bg-[linear-gradient(180deg,rgba(36,11,26,0.96),rgba(24,7,18,0.98))] px-5 pb-[calc(env(safe-area-inset-bottom)+0.9rem)] pt-3 shadow-[0_-18px_48px_rgba(0,0,0,0.28)] backdrop-blur-xl">
          <div className="mx-auto flex w-full max-w-6xl items-center justify-center gap-4">
            <a
              href={mailtoHref}
              className="inline-flex h-12 items-center gap-2.5 whitespace-nowrap rounded-full bg-brand-highlight px-5 text-sm font-semibold text-text-inverse shadow-[0_2px_20px_rgba(242,126,178,0.24)] transition-all duration-200 active:scale-[0.98]"
            >
              <Mail className="h-[1.05rem] w-[1.05rem] shrink-0" />
              <span>{hero.primaryCta}</span>
            </a>
            <Link
              href="#faq"
              className="flex shrink-0 items-center gap-1.5 text-sm font-medium text-text-muted transition-colors active:text-text-primary"
            >
              {hero.secondaryCta}
              <ArrowRight className="h-3.5 w-3.5" />
            </Link>
          </div>
        </div>
      </div>

      <section id="faq" className="relative overflow-hidden px-6 pb-14 pt-14 sm:pb-16 sm:pt-16 lg:pb-20">
        <div className="pointer-events-none absolute inset-0 -z-10">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_130%_80%_at_50%_-15%,hsl(334_83%_63%_/_0.18),transparent_60%)]" />
        </div>
        <div className="mx-auto w-full max-w-5xl">
          <div className="mb-10 max-w-2xl space-y-4 sm:mb-14 sm:space-y-5">
            <p className="text-xs font-semibold uppercase tracking-[0.22em] text-text-muted">
              {marketing.faq.eyebrow}
            </p>
            <h2 className="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">
              {marketing.faq.heading}
            </h2>
            <p className="text-base leading-7 text-text-secondary sm:text-lg">
              {marketing.faq.description}
            </p>
          </div>

          <Accordion type="single" collapsible defaultValue={faqs[0]?.question} className="space-y-3">
            {faqs.map((faq) => (
              <AccordionItem
                key={faq.question}
                value={faq.question}
                className="rounded-[1.15rem] border border-white/8 bg-background/60 px-4 last:border-b sm:rounded-[1.4rem] sm:px-6"
              >
                <AccordionTrigger className="py-5 text-left text-base font-medium hover:text-brand-highlight sm:py-6 sm:text-lg">
                  {faq.question}
                </AccordionTrigger>
                <AccordionContent className="pb-5 sm:pb-6">
                  {faq.answers.map((paragraph, answerIndex) => (
                    <p
                      key={`${faq.question}-${answerIndex}`}
                      className="pb-3 text-base leading-7 text-text-secondary last:pb-0"
                    >
                      {paragraph}
                    </p>
                  ))}
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </div>
      </section>

      <section className="border-y border-white/10 px-6 py-14 sm:py-16">
        <div className="mx-auto w-full max-w-5xl">
          <div className="mb-6 max-w-2xl space-y-2 sm:mb-8">
            <p className="text-xs font-medium uppercase tracking-[0.22em] text-text-muted">
              {marketing.socialProof.eyebrow}
            </p>
            <h2 className="text-balance text-2xl font-semibold tracking-[-0.03em] sm:text-3xl">
              {marketing.socialProof.heading}
            </h2>
            <p className="text-sm leading-7 text-text-secondary sm:text-base">
              {marketing.socialProof.description}
            </p>
          </div>

          <div className="grid gap-3 sm:grid-cols-3">
            {marketing.socialProof.items.map((item) => (
              <div key={item.title} className="rounded-[1.15rem] border border-white/8 bg-background/55 p-5">
                <h3 className="text-base font-semibold tracking-[-0.02em]">{item.title}</h3>
                <p className="mt-2 text-sm leading-7 text-text-secondary">{item.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="px-6 pb-20 pt-14 sm:pb-28 sm:pt-16">
        <div className="mx-auto grid w-full max-w-5xl gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
          <div className="rounded-[1.75rem] border border-white/12 bg-background/50 p-8 backdrop-blur-xl sm:p-10">
            <h2 className="max-w-lg text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">
              {marketing.ctaPrimary.heading}
            </h2>
            <p className="mt-5 max-w-xl text-base leading-7 text-text-secondary sm:text-lg">
              {marketing.ctaPrimary.description}
            </p>
            <Button
              asChild
              className="mt-8 h-11 rounded-full bg-brand-highlight px-5 text-sm font-semibold text-text-inverse hover:brightness-105"
            >
              <Link href={privacyHref}>
                <span>{marketing.ctaPrimary.button}</span>
                <ArrowRight className="h-4 w-4" />
              </Link>
            </Button>
          </div>

          <div className="rounded-[1.75rem] border border-white/12 bg-background/45 p-8 backdrop-blur-xl sm:p-10">
            <h2 className="text-2xl font-semibold tracking-[-0.03em] sm:text-[1.75rem]">
              {marketing.contact.heading}
            </h2>
            <p className="mt-5 text-sm leading-7 text-text-secondary sm:text-base">
              {marketing.contact.description}
            </p>
            <Button
              asChild
              variant="outline"
              className="mt-7 h-10 rounded-full border-white/18 bg-white/8 px-5 text-sm font-semibold text-text-primary hover:bg-white/12"
            >
              <a href={mailtoHref}>{marketing.contact.button}</a>
            </Button>
          </div>
        </div>
      </section>

      <footer className="border-t border-white/8 px-6 py-10">
        <div className="mx-auto flex w-full max-w-6xl flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="text-sm text-text-muted">{marketing.footer.copyright}</div>
          <div className="flex w-full flex-col items-start gap-2 text-sm sm:w-auto sm:flex-row sm:items-center sm:gap-6">
            <Link href={privacyHref} className="text-text-secondary transition-colors hover:text-text-primary">
              {marketing.footer.privacy}
            </Link>
            <Link href={termsHref} className="text-text-secondary transition-colors hover:text-text-primary">
              {marketing.footer.terms}
            </Link>
            <Link href={supportHref} className="text-text-secondary transition-colors hover:text-text-primary">
              {marketing.footer.support}
            </Link>
          </div>
        </div>
      </footer>
    </main>
  );
}

function AppScreen({ preview }: { preview: Preview }) {
  return (
    <div className="absolute inset-0 flex flex-col gap-3 bg-[radial-gradient(circle_at_76%_4%,rgba(242,126,178,0.16),transparent_9rem),linear-gradient(180deg,#4F203A_0%,#380F27_44%,#2A0B1E_100%)] px-4 pb-4 pt-3 text-[#FFF9FC]">
      <div className="relative h-4 text-[0.72rem] font-semibold tracking-tight text-[#FFF9FC]">
        <span className="absolute left-[13%] top-0">21:47</span>
        <span className="absolute right-[6.5%] top-[1px] flex items-end gap-[2px]">
          <span className="block h-[4px] w-[3px] rounded-[1px] bg-[#FFF9FC]" />
          <span className="block h-[6px] w-[3px] rounded-[1px] bg-[#FFF9FC]" />
          <span className="block h-[8px] w-[3px] rounded-[1px] bg-[#FFF9FC]" />
          <span className="block h-[10px] w-[3px] rounded-[1px] bg-[#FFF9FC]" />
          <span className="ml-1 block h-[11px] w-[22px] rounded-[3px] border-[1.5px] border-[#FFF9FC] after:absolute after:mt-[1px] after:ml-[1px] after:block after:h-[6px] after:w-[14px] after:rounded-[1px] after:bg-[#FFF9FC] after:content-['']" />
        </span>
      </div>

      <div className="mt-1 flex items-center gap-3">
        <div className="flex h-9 w-9 items-center justify-center rounded-[10px] bg-[#FFF9FC]/8 ring-1 ring-[#FFF9FC]/10">
          <img src="/brand/paeonia-mark-tight.svg" alt="" className="h-6 w-6" />
        </div>
        <div className="leading-tight">
          <span className="block text-[0.6rem] font-bold uppercase tracking-[0.08em] text-[#F27EB2]">
            {preview.appLabel}
          </span>
          <strong className="block text-[1rem] font-semibold tracking-[-0.03em] text-[#FFF9FC]">
            {preview.partnerName}
          </strong>
        </div>
      </div>

      <div className="rounded-[18px] border border-[#FFF9FC]/10 bg-[#FFF9FC]/8 p-4 shadow-[0_18px_36px_-26px_rgba(0,0,0,0.7)]">
        <span className="block text-[0.6rem] font-bold uppercase tracking-[0.08em] text-[#F27EB2]">
          {preview.checkInLabel}
        </span>
        <p className="mt-2 text-[1.02rem] font-medium leading-snug tracking-[-0.03em] text-[#FFF9FC]">
          {preview.checkInText}
        </p>
      </div>

      <div className="rounded-[18px] border border-[#FFF9FC]/10 bg-[#FFF9FC]/7 p-3.5">
        <svg viewBox="0 0 220 96" className="w-full" aria-hidden="true">
          <path
            d="M22 64C48 22 86 34 96 56C109 85 145 82 156 52C167 21 198 22 206 44"
            fill="none"
            stroke="#EF5094"
            strokeWidth="7"
            strokeLinecap="round"
          />
          <path
            d="M44 76C64 62 83 62 101 76C118 89 143 88 164 70"
            fill="none"
            stroke="#E85D86"
            strokeWidth="5"
            strokeLinecap="round"
          />
        </svg>
        <span className="mt-1.5 block text-[0.6rem] font-bold uppercase tracking-[0.08em] text-[#F27EB2]">
          {preview.drawingLabel}
        </span>
      </div>

      <div className="mt-auto rounded-[18px] bg-[#F27EB2]/12 p-4 ring-1 ring-[#F27EB2]/14">
        <span className="block text-[0.6rem] font-bold uppercase tracking-[0.08em] text-[#F27EB2]">
          {preview.memoryDate}
        </span>
        <strong className="mt-1 block text-[1rem] font-semibold tracking-[-0.03em] text-[#FFF9FC]">
          {preview.memoryTitle}
        </strong>
      </div>
    </div>
  );
}
