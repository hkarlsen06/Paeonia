<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { Locale } from '#lib/i18n/config.ts';
  import PageHead from './PageHead.svelte';
  import SiteShell from './SiteShell.svelte';

  interface Section {
    readonly heading: string;
    readonly paragraphs: readonly string[];
  }

  interface Props {
    locale: Locale;
    path: string;
    meta: { readonly title: string; readonly description: string };
    title: string;
    lede: string;
    sections: readonly Section[];
    /** Shown above the title, such as the date a policy was last changed. */
    label?: string;
    /** Shown between the lede and the sections, such as the support email buttons. */
    children?: Snippet;
  }

  let { locale, path, meta, title, lede, sections, label, children }: Props = $props();
</script>

<PageHead title={`${meta.title} - Paeonia`} description={meta.description} />

<SiteShell {locale} {path}>
  <main class="page-shell narrow">
    {#if label}<p class="label">{label}</p>{/if}
    <h1>{title}</h1>
    <p class="lede">{lede}</p>

    {@render children?.()}

    <div class="legal-content">
      {#each sections as section (section.heading)}
        <section>
          <h2>{section.heading}</h2>
          {#each section.paragraphs as paragraph (paragraph)}
            <p>{paragraph}</p>
          {/each}
        </section>
      {/each}
    </div>
  </main>
</SiteShell>
