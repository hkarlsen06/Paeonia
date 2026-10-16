<script lang="ts">
  import { ArrowDown, ArrowRight, Dice5, Hourglass, Mail, PenLine, Plus, Radio } from '@lucide/svelte';
  import type { ClassValue } from 'svelte/elements';
  import PageHead from '#lib/components/PageHead.svelte';
  import PhoneScreenshot from '#lib/components/PhoneScreenshot.svelte';
  import SiteShell from '#lib/components/SiteShell.svelte';
  import { buildLocalizedPath } from '#lib/paths.ts';

  let { data } = $props();
  const { meta, hero, games, live, features, extras, privacy, faq, contact } = $derived(data.dictionary.marketing);
  const mailtoHref = $derived(
    `mailto:${data.dictionary.legal.contactEmail}?subject=${encodeURIComponent(contact.emailSubject)}&body=${encodeURIComponent(contact.emailBody)}`,
  );
  const [titleStart, titleEnd] = $derived(hero.title.split(hero.titleEmphasis));
  const screen = (name: string) => `/screens/${name}.webp`;
  const liveIcons = [Radio, Dice5, PenLine, Hourglass];
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

<PageHead title={meta.title} description={meta.description} url={`https://paeonia.no/${data.locale}/`} />

<SiteShell locale={data.locale}>
  <main class="pb-[calc(7rem+env(safe-area-inset-bottom))] text-text-primary lg:pb-0">
    <section class="relative isolate overflow-hidden px-5 sm:px-8">
      {@render glow('right-[-30%] top-[30%] h-[36rem] w-[36rem] lg:right-[2%] lg:top-[4%] lg:h-[46rem] lg:w-[46rem]')}

      <div
        class="mx-auto grid w-full max-w-6xl items-center gap-12 pb-16 pt-8 sm:pt-14 lg:min-h-[calc(100dvh-5rem)] lg:grid-cols-[minmax(0,1fr)_26rem] lg:gap-12 lg:py-10 xl:grid-cols-[minmax(0,1fr)_29rem]"
      >
        <div>
          <h1 class="text-balance text-[2.75rem] font-semibold leading-[1.04] tracking-[-0.04em] sm:text-6xl lg:text-[4.5rem] xl:text-[5rem]">
            {titleStart}<em class="not-italic text-brand-highlight">{hero.titleEmphasis}</em>{titleEnd}
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
          <PhoneScreenshot src={screen(hero.screenshots[0].src)} alt={hero.screenshots[0].alt} priority class="w-[58%]" />
          <PhoneScreenshot src={screen(hero.screenshots[1].src)} alt={hero.screenshots[1].alt} priority class="-ml-[16%] mt-[14%] w-[58%]" />
        </div>
      </div>
    </section>

    <div
      class="fixed inset-x-0 bottom-0 z-30 border-t border-white/8 bg-background/85 px-5 pb-[calc(env(safe-area-inset-bottom)+0.75rem)] pt-3 backdrop-blur-xl lg:hidden"
    >
      {@render mailButton(hero.primaryCta, 'w-full')}
      <p class="mt-2 text-center text-xs text-text-muted">{hero.note}</p>
    </div>

    <section id="games" aria-labelledby="games-heading" class="scroll-mt-4 overflow-x-clip px-5 pt-10 sm:px-8 lg:pt-16">
      <div class="relative isolate mx-auto max-w-6xl">
        {@render glow('left-1/2 top-[40%] h-[56rem] w-[56rem] -translate-x-1/2')}
        <div class="max-w-3xl">
          <h2 id="games-heading" class="text-balance text-4xl font-semibold tracking-[-0.035em] sm:text-5xl lg:text-[3.5rem] lg:leading-[1.05]">
            {games.title}
          </h2>
          <p class="mt-5 max-w-[50ch] text-pretty text-lg leading-relaxed text-text-secondary sm:text-xl">
            {games.description}
          </p>
        </div>

        <div
          class="-mx-5 mt-12 flex snap-x snap-mandatory gap-5 overflow-x-auto px-5 pb-6 [scrollbar-width:none] sm:-mx-8 sm:px-8 lg:mx-0 lg:grid lg:grid-cols-4 lg:gap-6 lg:overflow-visible lg:px-0"
        >
          {#each games.screens as shot, index (shot.src)}
            <PhoneScreenshot
              src={screen(shot.src)}
              alt={shot.alt}
              class={['w-[min(62vw,15rem)] shrink-0 snap-center lg:w-auto', index % 2 === 1 && 'lg:mt-16']}
            />
          {/each}
        </div>

        <div class="mt-12 grid gap-8 sm:grid-cols-3 sm:gap-10">
          {#each games.points as point (point.title)}
            <div class="border-t border-brand-highlight/40 pt-5">
              <h3 class="text-lg font-semibold tracking-[-0.02em]">{point.title}</h3>
              <p class="mt-2 text-base leading-7 text-text-secondary">{point.description}</p>
            </div>
          {/each}
        </div>

        <h3 class="mt-16 text-sm font-medium text-text-muted">{games.listHeading}</h3>
        <ul class="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {#each games.list as game (game.name)}
            <li class="rounded-2xl bg-surface-primary/70 p-5 ring-1 ring-white/8">
              <p class="text-base font-semibold tracking-[-0.01em]">{game.name}</p>
              <p class="mt-1.5 text-sm leading-6 text-text-secondary">{game.description}</p>
            </li>
          {/each}
        </ul>
      </div>
    </section>

    <section id="live" aria-labelledby="live-heading" class="scroll-mt-4 overflow-x-clip px-5 sm:px-8">
      <div
        class="mx-auto mt-16 grid max-w-6xl items-center gap-12 border-t border-white/8 py-16 sm:mt-20 sm:py-20 lg:grid-cols-[minmax(0,1fr)_19rem] lg:gap-20"
      >
        <div>
          <h2 id="live-heading" class="text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl lg:text-[2.75rem] lg:leading-[1.1]">
            {live.title}
          </h2>
          <p class="mt-5 max-w-[46ch] text-pretty text-lg leading-relaxed text-text-secondary">{live.description}</p>

          <ul class="mt-10 grid gap-x-10 gap-y-8 sm:grid-cols-2">
            {#each live.items as item, index (item.title)}
              {@const Icon = liveIcons[index]}
              <li class="flex gap-4">
                <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-surface-secondary ring-1 ring-white/10">
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

        <div class="relative isolate flex justify-center">
          {@render glow('left-1/2 top-1/2 h-[40rem] w-[40rem] -translate-x-1/2 -translate-y-1/2')}
          <PhoneScreenshot src={screen(live.screenshot.src)} alt={live.screenshot.alt} class="w-[min(72vw,18rem)]" />
        </div>
      </div>
    </section>

    <section id="inside" class="scroll-mt-4 overflow-x-clip px-5 sm:px-8">
      <div class="mx-auto max-w-6xl">
        {#each features.items as item, index (item.title)}
          <article class="grid items-center gap-12 border-t border-white/8 py-16 sm:py-20 lg:grid-cols-2 lg:gap-20">
            <div class={index % 2 === 1 ? 'lg:order-last' : undefined}>
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
              <div class="flex items-start">
                {#each item.screens as shot, shotIndex (shot.src)}
                  <PhoneScreenshot
                    src={screen(shot.src)}
                    alt={shot.alt}
                    class={['w-[min(46vw,16.5rem)]', shotIndex > 0 && '-ml-[12%] mt-[18%]']}
                  />
                {/each}
              </div>
            </div>
          </article>
        {/each}
      </div>
    </section>

    <section aria-labelledby="extras-heading" class="px-5 sm:px-8">
      <div class="mx-auto max-w-6xl border-t border-white/8 py-16 sm:py-20">
        <h2 id="extras-heading" class="text-2xl font-semibold tracking-[-0.03em] sm:text-3xl">{extras.heading}</h2>
        <div class="mt-10 grid gap-8 sm:grid-cols-2 sm:gap-10 lg:grid-cols-4">
          {#each extras.items as item (item.title)}
            <div class="border-t border-brand-highlight/40 pt-5">
              <h3 class="text-lg font-semibold tracking-[-0.02em]">{item.title}</h3>
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
        <div>
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
        <ul class="border-t border-white/10">
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

    <section class="px-5 pb-20 pt-4 sm:px-8 sm:pb-28">
      <div
        class="mx-auto flex max-w-3xl flex-col items-center rounded-[2rem] bg-[linear-gradient(110deg,#3a0f2a_0%,#6b1d4b_55%,#b8407a_100%)] px-6 py-12 text-center ring-1 ring-white/10 sm:py-16"
      >
        <div
          class="flex h-16 w-16 items-center justify-center rounded-[22%] bg-[linear-gradient(160deg,#4f203a,#2a0b1e)] shadow-[0_10px_30px_rgba(0,0,0,0.35)] ring-1 ring-white/10"
        >
          <img src="/brand/paeonia-mark-tight.svg" alt="" width="40" height="40" class="h-10 w-10" />
        </div>
        <h2 class="mt-6 text-balance text-3xl font-semibold tracking-[-0.03em] sm:text-4xl">{contact.heading}</h2>
        <p class="mt-3 max-w-[40ch] text-pretty text-base leading-7 text-white/80">{contact.description}</p>
        {@render mailButton(contact.button, 'mt-8')}
      </div>
    </section>
  </main>
</SiteShell>
