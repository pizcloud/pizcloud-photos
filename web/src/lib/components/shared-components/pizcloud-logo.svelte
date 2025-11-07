<!-- <script lang="ts">
  import { t } from 'svelte-i18n';
  import type { HTMLImgAttributes } from 'svelte/elements';
  // Import raw SVG strings (SvelteKit/Vite)
  import darkSVG from '$lib/assets/pizcloud-logo-inline-dark.svg?raw';
  import lightSVG from '$lib/assets/pizcloud-logo-inline-light.svg?raw';
  // New: icon/logo không chữ
  import iconSVG from '$lib/assets/pizcloud-logo.svg?raw';

  interface Props extends HTMLImgAttributes {
    /** auto (default): follow page theme (.dark) or prefers-color-scheme; force with 'light' | 'dark' */
    mode?: 'auto' | 'light' | 'dark';
    noText?: boolean;
    class?: string | undefined;
    alt?: string;
    title?: string;
  }

  let {
    mode = 'auto',
    noText = false,
    class: cssClass,
    alt = $t('pizcloud_logo'),
    title = $t('pizcloud_logo'),
  }: Props = $props();
</script>

{#if noText}
  <div class={cssClass} role="img" aria-label={alt} {title}>
    {@html iconSVG}
  </div>
{:else if mode === 'light'}
  <div class={cssClass} role="img" aria-label={alt} {title}>
    {@html lightSVG}
  </div>
{:else if mode === 'dark'}
  <div class={cssClass} role="img" aria-label={alt} {title}>
    {@html darkSVG}
  </div>
{:else}
  <div class={`block dark:hidden ${cssClass || ''}`} role="img" aria-label={alt} {title}>
    {@html lightSVG}
  </div>
  <div class={`hidden dark:block ${cssClass || ''}`} role="img" aria-label={alt} {title}>
    {@html darkSVG}
  </div>
{/if}

<style>
  :global(svg) {
    display: block;
    width: 100%;
    height: auto;
  }
</style> -->

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
