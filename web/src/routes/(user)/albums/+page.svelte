<script lang="ts">
  import { scrollMemory } from '$lib/actions/scroll-memory';
  import AlbumsControls from '$lib/components/album-page/albums-controls.svelte';
  import Albums from '$lib/components/album-page/albums-list.svelte';
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import { AppRoute } from '$lib/constants';
  import GroupTab from '$lib/elements/GroupTab.svelte';
  import SearchBar from '$lib/elements/SearchBar.svelte';
  import { AlbumFilter, albumViewSettings } from '$lib/stores/preferences.store';
  import { createAlbumAndRedirect } from '$lib/utils/album-utils';
  import { t } from 'svelte-i18n';
  import { findFilterOption } from '../../../lib/utils/album-utils';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let searchQuery = $state('');
  let albumGroups: string[] = $state([]);

  let albumFilterNames: Record<AlbumFilter, string> = $derived({
    [AlbumFilter.All]: $t('all'),
    [AlbumFilter.Owned]: $t('owned'),
    [AlbumFilter.Shared]: $t('shared'),
  });
  let selectedFilterOption = $derived(albumFilterNames[findFilterOption($albumViewSettings.filter)]);

  const handleChangeAlbumFilter = (filter: string, defaultFilter: AlbumFilter) => {
    $albumViewSettings.filter =
      Object.keys(albumFilterNames).find((key) => albumFilterNames[key as AlbumFilter] === filter) ?? defaultFilter;
  };
</script>

<UserPageLayout title={data.meta.title} use={[[scrollMemory, { routeStartsWith: AppRoute.ALBUMS }]]}>
  {#snippet buttons()}
    <div class="flex place-items-center gap-2">
      <AlbumsControls {albumGroups} bind:searchQuery />
    </div>
  {/snippet}

  <div class="2xl:hidden">
    <div class="w-fit h-14 dark:text-immich-dark-fg py-2">
      <GroupTab
        label={$t('show_albums')}
        filters={Object.values(albumFilterNames)}
        selected={selectedFilterOption}
        onSelect={(selected) => handleChangeAlbumFilter(selected, AlbumFilter.All)}
      />
    </div>
    <div class="w-60">
      <SearchBar placeholder={$t('search_albums')} bind:name={searchQuery} showLoadingSpinner={false} />
    </div>
  </div>

  <Albums
    ownedAlbums={data.albums}
    sharedAlbums={data.sharedAlbums}
    userSettings={$albumViewSettings}
    allowEdit
    {searchQuery}
    bind:albumGroupIds={albumGroups}
  >
    {#snippet empty()}
      <EmptyPlaceholder text={$t('no_albums_message')} onClick={() => createAlbumAndRedirect()} class="mt-10 mx-auto" />
    {/snippet}
  </Albums>
</UserPageLayout>
