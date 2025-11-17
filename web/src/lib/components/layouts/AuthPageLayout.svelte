<script lang="ts">
  import { Card, CardBody, CardHeader, Heading, VStack } from '@immich/ui';
  import type { Snippet } from 'svelte';

  import PizcloudLogo from '$lib/components/shared-components/pizcloud-logo.svelte';

  import bgDarkUrl from '$lib/assets/pizcloud-logo-inline-dark.svg';
  import bgLightUrl from '$lib/assets/pizcloud-logo-inline-light.svg';

  interface Props {
    title?: string;
    children?: Snippet;
    withHeader?: boolean;
  }

  let { title, children, withHeader = true }: Props = $props();
</script>

<section class="min-w-dvw flex min-h-dvh items-center justify-center relative">
  <div class="absolute -z-10 w-full h-full flex place-items-center place-content-center">
    <picture class="max-w-(--breakpoint-md) mx-auto h-full mb-2 antialiased overflow-hidden">
      <source srcset={bgDarkUrl} media="(prefers-color-scheme: dark)" />
      <img
        src={bgLightUrl}
        alt="PizCloud logo"
        class="block w-full h-full object-contain"
        decoding="async"
        loading="lazy"
      />
    </picture>
    <!-- <img
      src={immichLogo}
      class="max-w-(--breakpoint-md) mx-auto h-full mb-2 antialiased overflow-hidden"
      alt="Immich logo"
    /> -->
    <div
      class="w-full h-[99%] absolute start-0 top-0 backdrop-blur-[200px] bg-transparent dark:bg-immich-dark-bg/20"
    ></div>
  </div>

  <Card color="secondary" class="w-full max-w-lg border m-2">
    {#if withHeader}
      <CardHeader class="mt-6">
        <VStack>
          <PizcloudLogo noText class="w-20 h-20 object-contain" alt="PizCloud" title="PizCloud" />
          <!-- <Logo variant="icon" size="giant" /> -->
          <Heading size="large" class="font-semibold" color="primary" tag="h1">{title}</Heading>
        </VStack>
      </CardHeader>
    {/if}

    <CardBody class="p-8">
      {@render children?.()}
    </CardBody>
  </Card>
</section>
