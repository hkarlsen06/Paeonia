<script lang="ts">
  import { onMount } from 'svelte';
  import PageHead from '#lib/components/PageHead.svelte';
  import { marketingEn } from '#lib/i18n/dictionaries/marketing.en.ts';
  import { marketingNo } from '#lib/i18n/dictionaries/marketing.no.ts';

  const appStoreURL = 'https://apps.apple.com/us/app/paeonia/id6779833892';
  const copy = { en: marketingEn.join, nb: marketingNo.join } as const;

  function normalizedInviteCode(pathname: string): string | null {
    const match = pathname.match(/^\/join\/([^/]+)\/?$/i);
    if (!match) return null;

    let candidate: string;
    try {
      candidate = decodeURIComponent(match[1]);
    } catch {
      return null;
    }

    const normalized = candidate
      .toUpperCase()
      .replace(/[\s_-]/g, '')
      .replace(/[IL]/g, '1')
      .replace(/O/g, '0');

    return /^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{6}$/.test(normalized) ? normalized : null;
  }

  // Undefined until the page has read the address. The static HTML shows "Opening your invite".
  let inviteCode = $state<string | null>();
  let hasInvitePath = $state(false);
  let language = $state<keyof typeof copy>('en');

  onMount(() => {
    // /join/* is served this page by _redirects, so the code is only in the address bar.
    inviteCode = normalizedInviteCode(window.location.pathname);
    hasInvitePath = /^\/join\/[^/]+\/?$/i.test(window.location.pathname);
    language = /^(nb|no|nn)(-|$)/.test(navigator.language.toLowerCase()) ? 'nb' : 'en';
  });

  // iOS forgets a link on the way through the App Store, so the app can't see it on
  // first launch. Copying it here lets the welcome screen offer a Paste button. The
  // copy has to run inside the tap, so it is not awaited before the App Store opens.
  function copyInviteLink() {
    if (!inviteCode) return;
    navigator.clipboard?.writeText(`https://paeonia.no/join/${inviteCode}`).catch(() => {});
  }

  const text = $derived(copy[language]);
  const home = $derived(language === 'nb' ? '/no/' : '/en/');
</script>

<PageHead title="Join Paeonia - Paeonia" description="Open a Paeonia partner invite on your iPhone or iPad." noindex />

<main class="join-page">
  <a class="join-brand" href={home}>
    <img src="/brand/paeonia-mark-tight.svg" alt="" width="36" height="36" />
    <span>Paeonia</span>
  </a>

  {#if inviteCode === undefined}
    <section class="join-content" aria-busy="true">
      <p class="join-opening">{text.opening}</p>
    </section>
  {:else}
    <section class="join-content" aria-labelledby="join-title">
      <h1 id="join-title">{inviteCode ? text.title : text.invalidTitle}</h1>
      <p>{inviteCode ? text.message : hasInvitePath ? text.invalidMessage : text.missingMessage}</p>

      {#if inviteCode}
        <div class="join-code" aria-label={`${text.code}: ${inviteCode}`}>
          <span>{text.code}</span>
          <strong>{inviteCode}</strong>
        </div>
      {/if}

      <div class="join-actions">
        {#if inviteCode}
          <a class="join-primary" href={`paeonia://join/${inviteCode}`}>{text.open}</a>
        {/if}
        <a class="join-secondary" href={appStoreURL} onclick={copyInviteLink}>{text.install}</a>
      </div>

      {#if inviteCode}
        <p class="join-note">{text.installNote}</p>
      {/if}

      <a class="join-help" href={`${home}support/`}>{text.help}</a>
    </section>
  {/if}
</main>
