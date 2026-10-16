<script lang="ts">
  import type { Snippet } from 'svelte';
  import { localeNames, locales, type Locale } from '#lib/i18n/config.ts';
  import { getMarketingDictionary } from '#lib/i18n/dictionaries/index.ts';
  import { buildLocalizedPath } from '#lib/paths.ts';

  interface Props {
    locale: Locale;
    /** The current page without the locale prefix, so the language toggle stays on it. */
    path?: string;
    children: Snippet;
  }

  let { locale, path = '', children }: Props = $props();
  const footer = $derived(getMarketingDictionary(locale).marketing.footer);
</script>

<div class="flex min-h-dvh flex-col">
  <header
    class="relative z-10 mx-auto flex w-full max-w-6xl items-center justify-between gap-5 px-5 pb-4 pt-[max(1.25rem,env(safe-area-inset-top))] sm:px-8"
  >
    <a href={buildLocalizedPath(locale)} class="inline-flex items-center gap-2.5 text-lg font-semibold tracking-[-0.03em] text-text-primary">
      <img src="/brand/paeonia-mark-tight.svg" alt="" width="32" height="32" class="h-8 w-8" />
      Paeonia
    </a>
    <nav
      aria-label="Language"
      class="inline-flex shrink-0 items-center rounded-full border border-white/8 bg-white/[0.02] p-[0.2rem] text-sm font-medium text-text-muted backdrop-blur-sm"
    >
      {#each locales as item (item)}
        <a
          href={buildLocalizedPath(item, path)}
          hreflang={item}
          lang={item}
          aria-current={item === locale ? 'page' : undefined}
          class={[
            'inline-flex items-center rounded-full px-3.5 py-1.5 transition-colors hover:text-text-primary',
            item === locale && 'bg-white/[0.07] text-text-primary',
          ]}
        >
          {localeNames[item]}
        </a>
      {/each}
    </nav>
  </header>

  {@render children()}

  <footer class="mt-auto border-t border-white/8 px-5 py-10 sm:px-8">
    <div class="mx-auto flex w-full max-w-6xl flex-col gap-4 text-sm sm:flex-row sm:items-center sm:justify-between">
      <p class="text-text-muted">{footer.copyright}</p>
      <nav aria-label={footer.footerNavigationLabel} class="flex flex-wrap gap-x-6 gap-y-2">
        <a href={buildLocalizedPath(locale, 'privacy')} class="text-text-secondary transition-colors hover:text-text-primary">{footer.privacy}</a>
        <a href={buildLocalizedPath(locale, 'terms')} class="text-text-secondary transition-colors hover:text-text-primary">{footer.terms}</a>
        <a href={buildLocalizedPath(locale, 'support')} class="text-text-secondary transition-colors hover:text-text-primary">{footer.support}</a>
      </nav>
    </div>
  </footer>
</div>
