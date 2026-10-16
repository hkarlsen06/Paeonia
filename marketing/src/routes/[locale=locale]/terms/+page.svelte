<script lang="ts">
  import LegalPage from '#lib/components/LegalPage.svelte';

  let { data } = $props();
  const content = $derived(data.dictionary.legal.terms);
</script>

<LegalPage
  locale={data.locale}
  path="terms"
  meta={content.meta}
  label={content.updated}
  title={content.title}
  lede={content.meta.description}
  sections={content.sections}
/>
