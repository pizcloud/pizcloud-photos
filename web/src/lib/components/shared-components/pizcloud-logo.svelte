<script lang="ts">
  import { t } from 'svelte-i18n';
  import type { HTMLImgAttributes } from 'svelte/elements';
  // SAFE UI VERSION (no {@html}, no global SVG styles)
  // Use file URLs so the SVG is rendered inside <img>/<picture>.
  import darkUrl from '$lib/assets/pizcloud-logo-inline-dark.svg';
  import lightUrl from '$lib/assets/pizcloud-logo-inline-light.svg';
  import iconUrl from '$lib/assets/pizcloud-logo.svg';
  // no-text version you provided

  interface Props extends HTMLImgAttributes {
    /** 'auto' (default): follows prefers-color-scheme; force 'light' or 'dark' */
    mode?: 'auto' | 'light' | 'dark';
    /** Render icon-only (no text) using iconUrl */
    noText?: boolean;
    /** Tailwind / classes applied directly to <img>/<picture> */
    class?: string | undefined;
    /** Accessibility text */
    alt?: string;
    /** Tooltip/title attribute */
    title?: string;
  }

  let {
    mode = 'auto',
    noText = false,
    class: cssClass,
    alt = $t('pizcloud_logo'),
    title = $t('pizcloud_logo'),
    decoding = 'async',
    loading = 'lazy',
  }: Props = $props();
</script>

{#if noText}
  <!-- Icon-only: single asset for all themes -->
  <img src={iconUrl} {alt} {title} class={`block ${cssClass || ''}`} {decoding} {loading} />
{:else if mode === 'light'}
  <!-- Force light -->
  <img src={lightUrl} {alt} {title} class={`block ${cssClass || ''}`} {decoding} {loading} />
{:else if mode === 'dark'}
  <!-- Force dark -->
  <img src={darkUrl} {alt} {title} class={`block ${cssClass || ''}`} {decoding} {loading} />
{:else}
  <!-- AUTO: prefers-color-scheme-based swap (no Tailwind .dark required) -->
  <picture class={`block ${cssClass || ''}`} aria-label={alt} {title}>
    <source srcset={darkUrl} media="(prefers-color-scheme: dark)" />
    <img src={lightUrl} {alt} {decoding} {loading} class="block" />
  </picture>
{/if}

<style>
  /* No global SVG rules to avoid impacting other parts of the app. */
  /* Sizing is fully controlled by the classes you pass, e.g. w-40 h-[50px] object-contain */
</style>
