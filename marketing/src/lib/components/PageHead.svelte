<script lang="ts">
  interface Props {
    title: string;
    description?: string;
    /** The page's own address. The landing pages set it, so they get a canonical link and their own social preview. */
    url?: string;
    noindex?: boolean;
  }

  let { title, description, url, noindex = false }: Props = $props();
  // Pages without their own preview share the site's.
  const shareTitle = $derived(url ? title : 'Paeonia');
  const image = 'https://paeonia.no/opengraph-image.png';
</script>

<svelte:head>
  <title>{title}</title>
  {#if description}<meta name="description" content={description} />{/if}
  {#if noindex}<meta name="robots" content="noindex, nofollow" />{/if}
  {#if url}<link rel="canonical" href={url} />{/if}
  <meta property="og:title" content={shareTitle} />
  {#if url && description}<meta property="og:description" content={description} />{/if}
  <meta property="og:url" content={url ?? 'https://paeonia.no/'} />
  <meta property="og:site_name" content="Paeonia" />
  <meta property="og:image" content={image} />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:alt" content="Paeonia" />
  <meta property="og:type" content="website" />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content={shareTitle} />
  <meta name="twitter:image" content={image} />
</svelte:head>
