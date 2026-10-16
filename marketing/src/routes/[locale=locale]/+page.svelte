<script lang="ts">
  import { ArrowDown, ArrowRight, Dice5, Hourglass, Mail, PenLine, Plus, Radio } from '@lucide/svelte';
  import type { ClassValue } from 'svelte/elements';
  import PageHead from '#lib/components/PageHead.svelte';
  import PhoneScreenshot from '#lib/components/PhoneScreenshot.svelte';
  import SiteShell from '#lib/components/SiteShell.svelte';
  import { buildLocalizedPath } from '#lib/paths.ts';

  let { data } = $props();
  const { meta, hero, games, moment, live, features, extras, privacy, faq, contact } = $derived(data.dictionary.marketing);
  const mailtoHref = $derived(
    `mailto:${data.dictionary.legal.contactEmail}?subject=${encodeURIComponent(contact.emailSubject)}&body=${encodeURIComponent(contact.emailBody)}`,
  );
  const [titleStart, titleEnd] = $derived(hero.title.split(hero.titleEmphasis));
  const screen = (name: string) => `/screens/${name}.webp`;
  const art = (name: string) => `/art/${name}.webp`;
  const liveIcons = [Radio, Dice5, PenLine, Hourglass];
  // One sticker per feature and extra, in dictionary order.
  const featureArt = ['envelope', 'photo-stack'];
  const featureTints = [
    'bg-[radial-gradient(120%_90%_at_100%_0%,rgba(239,80,148,0.22),transparent_60%),linear-gradient(180deg,#3a1030,#2a0b24)]',
    'bg-[radial-gradient(120%_90%_at_0%_0%,rgba(167,139,250,0.22),transparent_60%),linear-gradient(180deg,#2f1238,#240b2a)]',
  ];
  const extraArt = ['calendar', 'pencil', 'heart', 'peony-bud'];
  // Petals that drift down behind the hero: [left, size, duration, delay, sway, image].
  const petals: [string, number, number, number, number, string][] = [
    ['6%', 34, 17, -3, 50, 'petal-pink'],
    ['18%', 26, 21, -11, -30, 'petal-lavender'],
    ['34%', 22, 19, -7, 40, 'petal-rose'],
    ['52%', 30, 23, -15, -50, 'petal-pink'],
    ['66%', 24, 18, -1, 30, 'petal-lavender'],
    ['80%', 36, 22, -9, -40, 'petal-rose'],
    ['92%', 28, 20, -5, 35, 'petal-pink'],
  ];
</script>

{#snippet mailButton(label: string, className: ClassValue = '')}
  <a
    href={mailtoHref}
    class={[
      'inline-flex h-13 items-center justify-center gap-2.5 whitespace-nowrap rounded-full bg-white px-7 text-base font-semibold text-text-inverse shadow-[0_8px_32px_rgba(239,80,148,0.35)] transition-transform duration-200 hover:scale-[1.02] active:scale-[0.98]',
      className,
    ]}
  >
    <Mail aria-hidden="true" class="h-[1.1rem] w-[1.1rem] shrink-0" />
    {label}
  </a>
{/snippet}

{#snippet glow(className: ClassValue)}
  <div
    aria-hidden="true"
    class={[
      'pointer-events-none absolute -z-10 rounded-full bg-[radial-gradient(circle,rgba(239,80,148,0.42),rgba(239,80,148,0.16)_40%,transparent_70%)]',
      className,
    ]}
  ></div>
{/snippet}

{#snippet sticker(name: string, className: ClassValue, tilt = 0)}
  <img
    src={art(name)}
    alt=""
    aria-hidden="true"
    loading="lazy"
    decoding="async"
    style:--tilt={`${tilt}deg`}
    class={['sticker-float pointer-events-none absolute drop-shadow-[0_18px_30px_rgba(10,2,8,0.55)]', className]}
  />
{/snippet}

<PageHead title={meta.title} description={meta.description} url={`https://paeonia.no/${data.locale}/`} />

<SiteShell locale={data.locale}>
  <main class="pb-[calc(7rem+env(safe-area-inset-bottom))] text-text-primary lg:pb-0">
    <section class="relative isolate overflow-hidden px-5 sm:px-8">
      {@render glow('right-[-30%] top-[30%] h-[36rem] w-[36rem] lg:right-[2%] lg:top-[4%] lg:h-[46rem] lg:w-[46rem]')}
      <div aria-hidden="true" class="petal-field pointer-events-none absolute inset-0 -z-10 overflow-hidden">
        {#each petals as [left, size, duration, delay, sway, image], index (index)}
          <img
            src={art(image)}
            alt=""
            width={size}
            height={size}
            class="petal opacity-0"
            style:left
            style:--duration={`${duration}s`}
            style:--delay={`${delay}s`}
            style:--sway={`${sway}px`}
          />
        {/each}
      </div>

      <div
        class="mx-auto grid w-full max-w-6xl items-center gap-12 pb-16 pt-8 sm:pt-14 lg:min-h-[calc(100dvh-5rem)] lg:grid-cols-[minmax(0,1fr)_26rem] lg:gap-12 lg:py-10 xl:grid-cols-[minmax(0,1fr)_29rem]"
      >
        <div>
          <h1 class="text-balance text-[2.75rem] font-semibold leading-[1.04] tracking-[-0.04em] sm:text-6xl lg:text-[4.5rem] xl:text-[5rem]">
            {titleStart}<em
              class="bg-[linear-gradient(100deg,#f59ac4,#ef5094_45%,#c4a1ff)] bg-clip-text not-italic text-transparent">{hero.titleEmphasis}</em
            >{titleEnd}
          </h1>
          <p class="mt-6 max-w-[34ch] text-pretty text-lg leading-relaxed text-text-secondary sm:text-xl">
            {hero.description}
          </p>
          <div class="mt-10 hidden flex-wrap items-center gap-x-7 gap-y-4 lg:flex">
            {@render mailButton(hero.primaryCta)}
            <a href="#games" class="inline-flex items-center gap-1.5 text-base font-medium text-text-muted transition-colors hover:text-text-primary">
              {hero.secondaryCta}
              <ArrowDown aria-hidden="true" class="h-4 w-4" />
            </a>
          </div>
          <p class="mt-4 hidden pl-7 text-sm text-text-muted lg:block">{hero.note}</p>
        </div>

        <div class="relative isolate mx-auto flex w-[min(92vw,26rem)] items-start lg:w-full">
          <PhoneScreenshot
            src={screen(hero.screenshots[0].src)}
            alt={hero.screenshots[0].alt}
            priority
            class="w-[58%] -rotate-3"
          />
          <PhoneScreenshot
            src={screen(hero.screenshots[1].src)}
            alt={hero.screenshots[1].alt}
            priority
            class="-ml-[16%] mt-[14%] w-[58%] rotate-2"
          />
          {@render sticker('peony-pair', '-bottom-6 -left-10 z-10 w-[42%] sm:-left-14', -6)}
          {@render sticker('heart', '-top-4 right-2 z-10 w-[16%] [animation-delay:-2s]', 12)}
        </div>
      </div>
    </section>

    <div
      class="fixed inset-x-0 bottom-0 z-30 border-t border-white/8 bg-background/85 px-5 pb-[calc(env(safe-area-inset-bottom)+0.75rem)] pt-3 backdrop-blur-xl lg:hidden"
    >
      {@render mailButton(hero.primaryCta, 'w-full')}
      <p class="mt-2 text-center text-xs text-text-muted">{hero.note}</p>
    </div>

    <section id="games" aria-labelledby="games-heading" class="scroll-mt-4 overflow-x-clip px-3 pt-6 sm:px-6 lg:pt-12">
      <div
        class="relative isolate mx-auto max-w-[78rem] overflow-hidden rounded-[2.5rem] bg-[radial-gradient(80%_60%_at_15%_0%,rgba(239,80,148,0.35),transparent_60%),radial-gradient(70%_60%_at_95%_20%,rgba(167,139,250,0.3),transparent_60%),linear-gradient(180deg,#4a1238,#2c0b28_70%)] px-5 py-14 ring-1 ring-white/10 sm:px-10 sm:py-20 lg:px-14"
      >
        <img
          src={art('ludo')}
          alt=""
          aria-hidden="true"
          loading="lazy"
          decoding="async"
          class="pointer-events-none absolute right-14 top-14 hidden w-56 rotate-6 drop-shadow-[0_18px_30px_rgba(10,2,8,0.55)] xl:block"
        />
        <div class="reveal max-w-3xl">
          <h2 id="games-heading" class="text-balance text-4xl font-semibold tracking-[-0.035em] sm:text-5xl lg:text-[3.5rem] lg:leading-[1.05]">
            {games.title}
          </h2>
          <p class="mt-5 max-w-[50ch] text-pretty text-lg leading-relaxed text-white/80 sm:text-xl">
            {games.description}
          </p>
        </div>

        <div
          class="-mx-5 -mb-20 mt-6 flex snap-x snap-mandatory gap-5 overflow-x-auto px-5 pb-26 pt-6 [scrollbar-width:none] sm:-mx-10 sm:px-10 lg:mx-0 lg:mb-0 lg:mt-12 lg:grid lg:grid-cols-4 lg:gap-6 lg:overflow-visible lg:px-0 lg:pb-6 lg:pt-0"
        >
          {#each games.screens as shot, index (shot.src)}
            <PhoneScreenshot
              src={screen(shot.src)}
              alt={shot.alt}
              class={[
                'reveal w-[min(62vw,15rem)] shrink-0 snap-center transition-transform duration-500 lg:w-auto lg:hover:-translate-y-2 lg:hover:rotate-0',
                index % 2 === 1 ? 'lg:mt-16 lg:rotate-2' : 'lg:-rotate-2',
              ]}
            />
          {/each}
        </div>

        <div class="mt-12 grid gap-8 sm:grid-cols-3 sm:gap-10">
          {#each games.points as point (point.title)}
            <div class="reveal border-t border-white/25 pt-5">
              <h3 class="text-lg font-semibold tracking-[-0.02em]">{point.title}</h3>
              <p class="mt-2 text-base leading-7 text-white/75">{point.description}</p>
            </div>
          {/each}
        </div>

        <h3 class="mt-16 text-sm font-medium text-white/70">{games.listHeading}</h3>
        <ul class="mt-5 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
          {#each games.list as game (game.name)}
            <li
              class="reveal group overflow-hidden rounded-3xl bg-[#2a0b24]/80 ring-1 ring-white/10 transition-transform duration-300 hover:-translate-y-1.5"
            >
              <div class="relative flex aspect-[4/3] items-center justify-center overflow-hidden bg-cover bg-center" style:background-image={`url(${art('backdrop')})`}>
                <img
                  src={art(game.art)}
                  alt=""
                  loading="lazy"
                  decoding="async"
                  class="max-h-[78%] max-w-[78%] object-contain drop-shadow-[0_14px_22px_rgba(60,10,40,0.45)] transition-transform duration-500 group-hover:-translate-y-1 group-hover:rotate-[-3deg] group-hover:scale-105"
                />
              </div>
              <div class="p-4 sm:p-5">
                <p class="text-base font-semibold tracking-[-0.01em]">{game.name}</p>
                <p class="mt-1.5 text-sm leading-6 text-text-secondary">{game.description}</p>
              </div>
            </li>
          {/each}
        </ul>
      </div>
    </section>

    <section
      aria-labelledby="moment-heading"
      class="bg-[radial-gradient(ellipse_75%_50%_at_50%_50%,rgba(239,80,148,0.26),rgba(239,80,148,0.08)_45%,transparent_72%)] px-5 py-24 sm:px-8 sm:py-32"
    >
      <div class="reveal mx-auto flex max-w-4xl flex-col items-center text-center">
        <img src={art('peony-pair')} alt="" loading="lazy" decoding="async" class="sticker-float w-44 drop-shadow-[0_20px_30px_rgba(10,2,8,0.5)] sm:w-56" />
        <h2
          id="moment-heading"
          class="mt-8 text-balance bg-[linear-gradient(100deg,#fff_20%,#f8b4d4_60%,#d6c1ff)] bg-clip-text text-4xl font-semibold leading-[1.08] tracking-[-0.04em] text-transparent sm:text-6xl"
        >
          {moment.title}
        </h2>
        <p class="mt-6 max-w-[44ch] text-pretty text-lg leading-relaxed text-text-secondary sm:text-xl">{moment.description}</p>
      </div>
    </section>

    <section id="live" aria-labelledby="live-heading" class="scroll-mt-4 overflow-x-clip px-3 sm:px-6">
      <div
        class="relative isolate mx-auto max-w-[78rem] overflow-hidden rounded-[2.5rem] bg-[radial-gradient(60%_70%_at_85%_40%,rgba(52,211,153,0.14),transparent_60%),radial-gradient(70%_60%_at_10%_100%,rgba(239,80,148,0.2),transparent_60%),linear-gradient(180deg,#1f0a22,#170819)] px-5 py-14 ring-1 ring-white/10 sm:px-10 sm:py-20 lg:px-14"
      >
        <div class="grid grid-cols-[minmax(0,1fr)] items-center gap-12 lg:grid-cols-[minmax(0,1fr)_24rem] lg:gap-16">
          <div class="reveal">
            <h2 id="live-heading" class="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl lg:text-[2.75rem] lg:leading-[1.1]">
              {live.title}
            </h2>
            <p class="mt-5 max-w-[46ch] text-pretty text-lg leading-relaxed text-text-secondary">{live.description}</p>

            <ul class="mt-10 grid gap-x-10 gap-y-8 sm:grid-cols-2">
              {#each live.items as item, index (item.title)}
                {@const Icon = liveIcons[index]}
                <li class="flex gap-4">
                  <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white/[0.06] ring-1 ring-white/10">
                    <Icon aria-hidden="true" class="h-5 w-5 text-brand-highlight" />
                  </span>
                  <div>
                    <h3 class="text-base font-semibold tracking-[-0.01em]">{item.title}</h3>
                    <p class="mt-1 text-base leading-7 text-text-secondary">{item.description}</p>
                  </div>
                </li>
              {/each}
            </ul>
          </div>

          <div class="relative mx-auto w-full max-w-[22rem]">
            <!-- Notices take turns over the phone, the way a partner's moves arrive. -->
            <ul aria-hidden="true" class="absolute -left-2 top-[40%] z-10 h-16 w-[18rem] sm:-left-10">
              {#each live.events as event, index (event)}
                <li
                  class="live-notice absolute inset-x-0 top-0 flex items-center gap-3 rounded-2xl bg-white/90 p-2.5 pr-4 text-text-inverse shadow-[0_20px_40px_-12px_rgba(0,0,0,0.6)] backdrop-blur"
                  style:--delay={`${index * 3}s`}
                >
                  <img src={art('elena')} alt="" width="40" height="40" class="h-10 w-10 rounded-full ring-2 ring-[#ef5094]" />
                  <span class="flex-1 text-sm font-semibold">{event}</span>
                  <span class="flex items-center gap-1.5 text-xs text-text-inverse/60">
                    <span class="h-2 w-2 rounded-full bg-emerald-500"></span>
                    {live.now}
                  </span>
                </li>
              {/each}
            </ul>
            <PhoneScreenshot src={screen(live.screenshot.src)} alt={live.screenshot.alt} class="reveal mx-auto w-[min(72vw,18rem)] rotate-2" />
          </div>
        </div>
      </div>
    </section>

    <section id="inside" class="scroll-mt-4 overflow-x-clip px-3 pt-6 sm:px-6 sm:pt-10">
      <div class="mx-auto grid max-w-[78rem] gap-6">
        {#each features.items as item, index (item.title)}
          <article
            class={[
              'relative isolate grid grid-cols-[minmax(0,1fr)] items-center gap-12 overflow-hidden rounded-[2.5rem] px-5 py-14 ring-1 ring-white/10 sm:px-10 sm:py-20 lg:grid-cols-2 lg:gap-20 lg:px-14',
              featureTints[index],
            ]}
          >
            <div class={['reveal relative', index % 2 === 1 && 'lg:order-last']}>
              <img
                src={art(featureArt[index])}
                alt=""
                loading="lazy"
                decoding="async"
                class="sticker-float mb-6 w-28 drop-shadow-[0_16px_24px_rgba(10,2,8,0.5)] sm:w-36"
              />
              <h2 class="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl lg:text-[2.75rem] lg:leading-[1.1]">
                {item.title}
              </h2>
              <p class="mt-5 max-w-[46ch] text-pretty text-lg leading-relaxed text-text-secondary">{item.description}</p>
              <ul class="mt-7 space-y-3">
                {#each item.points as point (point)}
                  <li class="flex gap-3 text-base leading-7 text-text-secondary">
                    <span aria-hidden="true" class="mt-[0.7rem] h-1.5 w-1.5 shrink-0 rounded-full bg-brand-highlight"></span>
                    {point}
                  </li>
                {/each}
              </ul>
            </div>

            <div class="relative isolate flex justify-center">
              {@render glow('left-1/2 top-1/2 h-[44rem] w-[44rem] -translate-x-1/2 -translate-y-1/2')}
              <div class="reveal flex w-full max-w-[33rem] items-start lg:max-w-[min(30rem,calc((100dvh-14rem)/1.4))]">
                {#each item.screens as shot, shotIndex (shot.src)}
                  <PhoneScreenshot
                    src={screen(shot.src)}
                    alt={shot.alt}
                    class={['w-[56%]', shotIndex > 0 ? '-ml-[12%] mt-[18%] rotate-2' : '-rotate-2']}
                  />
                {/each}
              </div>
            </div>
          </article>
        {/each}
      </div>
    </section>

    <section aria-labelledby="extras-heading" class="px-5 sm:px-8">
      <div class="mx-auto max-w-6xl py-16 sm:py-24">
        <h2 id="extras-heading" class="reveal text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">{extras.heading}</h2>
        <div class="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {#each extras.items as item, index (item.title)}
            <div
              class="reveal group rounded-3xl bg-surface-primary/70 p-6 ring-1 ring-white/8 transition-transform duration-300 hover:-translate-y-1.5"
            >
              <img
                src={art(extraArt[index])}
                alt=""
                loading="lazy"
                decoding="async"
                class="h-16 w-16 object-contain drop-shadow-[0_10px_16px_rgba(10,2,8,0.5)] transition-transform duration-500 group-hover:-rotate-6 group-hover:scale-110"
              />
              <h3 class="mt-5 text-lg font-semibold tracking-[-0.02em]">{item.title}</h3>
              <p class="mt-2 text-base leading-7 text-text-secondary">{item.description}</p>
            </div>
          {/each}
        </div>
      </div>
    </section>

    <section aria-labelledby="privacy-heading" class="px-5 sm:px-8">
      <div
        class="mx-auto grid max-w-6xl gap-10 border-t border-white/8 py-16 sm:py-20 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:gap-20"
      >
        <div class="reveal">
          <img src={art('wax-seal')} alt="" loading="lazy" decoding="async" class="mb-6 w-20 drop-shadow-[0_12px_20px_rgba(10,2,8,0.5)]" />
          <h2 id="privacy-heading" class="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">{privacy.heading}</h2>
          <p class="mt-4 text-base leading-7 text-text-secondary">{privacy.description}</p>
          <a
            href={buildLocalizedPath(data.locale, 'privacy')}
            class="mt-6 inline-flex items-center gap-1.5 text-sm font-medium text-text-primary transition-colors hover:text-brand-highlight"
          >
            {privacy.link}
            <ArrowRight aria-hidden="true" class="h-3.5 w-3.5" />
          </a>
        </div>
        <ul class="reveal border-t border-white/10">
          {#each privacy.items as item (item.title)}
            <li class="grid gap-1 border-b border-white/10 py-6 sm:grid-cols-[14rem_minmax(0,1fr)] sm:gap-8">
              <h3 class="text-base font-semibold tracking-[-0.01em] sm:text-lg">{item.title}</h3>
              <p class="text-base leading-7 text-text-secondary">{item.description}</p>
            </li>
          {/each}
        </ul>
      </div>
    </section>

    <section id="faq" aria-labelledby="faq-heading" class="scroll-mt-4 px-5 sm:px-8">
      <div
        class="mx-auto grid max-w-6xl gap-10 border-t border-white/8 py-16 sm:py-20 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)] lg:gap-20"
      >
        <div class="lg:sticky lg:top-12 lg:self-start">
          <h2 id="faq-heading" class="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">{faq.heading}</h2>
          <p class="mt-4 text-base leading-7 text-text-secondary">{faq.description}</p>
          <a
            href={mailtoHref}
            class="mt-6 inline-flex items-center gap-1.5 text-sm font-medium text-text-primary transition-colors hover:text-brand-highlight"
          >
            {faq.contactLink}
            <ArrowRight aria-hidden="true" class="h-3.5 w-3.5" />
          </a>
        </div>

        <div class="border-t border-white/10">
          {#each faq.items as item, index (item.question)}
            <details name="faq" open={index === 0} class="group border-b border-white/10">
              <summary
                class="group/question flex cursor-pointer list-none items-start gap-4 py-5 sm:gap-6 sm:py-6 [&::-webkit-details-marker]:hidden"
              >
                <span
                  class="mt-1 w-6 shrink-0 text-xs font-medium tabular-nums text-text-muted transition-colors group-open:text-brand-highlight sm:mt-1.5"
                >
                  {String(index + 1).padStart(2, '0')}
                </span>
                <span class="flex-1 text-base font-medium text-text-primary transition-colors group-hover/question:text-brand-highlight sm:text-lg">
                  {item.question}
                </span>
                <Plus
                  aria-hidden="true"
                  class="mt-1 h-4 w-4 shrink-0 text-text-muted transition-transform duration-200 group-open:rotate-45 group-open:text-text-primary sm:mt-1.5"
                />
              </summary>
              <div class="space-y-3 pb-6 pl-10 pr-8 sm:pl-12">
                {#each item.answers as answer (answer)}
                  <p class="text-base leading-7 text-text-secondary">{answer}</p>
                {/each}
              </div>
            </details>
          {/each}
        </div>
      </div>
    </section>

    <section class="px-3 pb-20 pt-4 sm:px-6 sm:pb-28">
      <div
        class="reveal relative isolate mx-auto flex max-w-4xl flex-col items-center overflow-hidden rounded-[2.5rem] bg-[linear-gradient(110deg,#3a0f2a_0%,#6b1d4b_55%,#b8407a_100%)] px-6 pb-12 pt-10 text-center ring-1 ring-white/10 sm:pb-16"
      >
        {@render sticker('petal-pink', 'left-[8%] top-10 w-10', -20)}
        {@render sticker('petal-lavender', 'right-[10%] top-16 w-8 [animation-delay:-3s]', 25)}
        {@render sticker('petal-rose', 'bottom-10 left-[14%] w-9 [animation-delay:-1.5s]', 10)}
        <img src={art('peony')} alt="" loading="lazy" decoding="async" class="sticker-float w-28 drop-shadow-[0_16px_24px_rgba(10,2,8,0.45)]" />
        <h2 class="mt-4 text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">{contact.heading}</h2>
        <p class="mt-3 max-w-[40ch] text-pretty text-base leading-7 text-white/80">{contact.description}</p>
        {@render mailButton(contact.button, 'mt-8')}
      </div>
    </section>
  </main>
</SiteShell>
