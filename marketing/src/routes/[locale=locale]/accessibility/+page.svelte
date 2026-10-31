<script lang="ts">
  import LegalPage from '#lib/components/LegalPage.svelte';

  let { data } = $props();
  const content = $derived(data.dictionary.legal.accessibility);
  const email = $derived(data.dictionary.legal.supportEmail);
</script>

<LegalPage
  locale={data.locale}
  path="accessibility"
  meta={content.meta}
  title={content.title}
  lede={content.description}
  label={content.updated}
  sections={content.sections}
>
  <div class="actions">
    <a class="button" href={`mailto:${email}`}>{email}</a>
  </div>
</LegalPage>
