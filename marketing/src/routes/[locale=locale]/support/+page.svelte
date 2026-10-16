<script lang="ts">
  import LegalPage from '#lib/components/LegalPage.svelte';
  import { buildLocalizedPath } from '#lib/paths.ts';

  let { data } = $props();
  const content = $derived(data.dictionary.legal.support);
  const { supportEmail, contactEmail } = $derived(data.dictionary.legal);
</script>

<LegalPage
  locale={data.locale}
  path="support"
  meta={content.meta}
  title={content.title}
  lede={content.description}
  sections={content.sections}
>
  <p class="label">{content.emailLabel}</p>
  <div class="actions">
    <a class="button" href={`mailto:${supportEmail}`}>{supportEmail}</a>
    <a class="button secondary" href={`mailto:${contactEmail}`}>{contactEmail}</a>
    <a class="button secondary" href={buildLocalizedPath(data.locale)}>{content.back}</a>
  </div>
</LegalPage>
