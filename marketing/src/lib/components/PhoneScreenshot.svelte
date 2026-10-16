<script lang="ts">
  import type { ClassValue } from 'svelte/elements';

  interface Props {
    src: string;
    alt: string;
    class?: ClassValue;
    priority?: boolean;
  }

  let { src, alt, class: className = '', priority = false }: Props = $props();
</script>

<!-- A real simulator screenshot in a thin bezel. Sizes are in container units, so the
     bezel and the iPhone corner radius scale with whatever width the caller sets. -->
<div class={['@container', className]}>
  <div class="rounded-[15.3cqw] bg-[#0d0509] p-[2.2cqw] shadow-[0_40px_90px_-24px_rgba(8,1,5,0.85)] ring-1 ring-white/12">
    <img
      {src}
      {alt}
      width="780"
      height="1696"
      loading={priority ? 'eager' : 'lazy'}
      fetchpriority={priority ? 'high' : undefined}
      decoding="async"
      class="block h-auto w-full rounded-[13.1cqw]"
    />
  </div>
</div>
