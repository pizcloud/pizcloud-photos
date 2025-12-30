<script lang="ts">
  import AlbumSharedLink from '$lib/components/album-page/album-shared-link.svelte';
  import { AppRoute } from '$lib/constants';
  import { addSharedEmail, getSharedEmails, removeSharedEmail } from '$lib/services/pizcloud/album-share-email.service';
  import { resolveAlbumShareEmails } from '$lib/services/pizcloud/album-share-resolve.service';
  import { handleError } from '$lib/utils/handle-error';
  import {
    AlbumUserRole,
    getAllSharedLinks,
    removeUserFromAlbum,
    // searchUsers,
    type AlbumResponseDto,
    type AlbumUserAddDto,
    type SharedLinkResponseDto,
    type UserResponseDto,
  } from '@immich/sdk';
  import {
    Button,
    Icon,
    IconButton,
    Input,
    Modal,
    ModalBody,
    Stack,
    Text,
    modalManager,
    toastManager,
  } from '@immich/ui';
  import { mdiCheck, mdiDeleteOutline, mdiLink, mdiLinkOff, mdiPlus } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  interface Props {
    album: AlbumResponseDto;
    onClose: (
      result?:
        | { action: 'sharedLink' }
        | { action: 'sharedUsers'; data: AlbumUserAddDto[] }
        | { action: 'refreshAlbum' },
    ) => void;
  }

  let { album, onClose }: Props = $props();

  type SharedEmailDto = { email: string; createdAt: string };

  let sharedEmails: SharedEmailDto[] = $state([]);
  let selectedEmails: Record<string, boolean> = $state({});
  let sharedUserByEmail: Record<string, UserResponseDto> = $state({});
  let sharedLinks: SharedLinkResponseDto[] = $state([]);
  let emailInput = $state('');
  let loading = $state(true);
  let isSubmitting = $state(false);
  let didChange = $state(false);

  const normalizeEmail = (value: string) => value.trim().toLowerCase();
  const selectedEmailList = $derived(Object.keys(selectedEmails).filter((email) => selectedEmails[email]));
  const canShare = $derived(selectedEmailList.length > 0);

  const formatDate = (value: string) => {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return '';
    }
    return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(date);
  };

  const syncSharedUsers = () => {
    sharedUserByEmail = {};
    for (const { user } of album.albumUsers) {
      sharedUserByEmail[normalizeEmail(user.email)] = user;
    }
  };

  const loadSharedEmails = async () => {
    loading = true;
    try {
      const items = await getSharedEmails(album.id);
      sharedEmails = items;
      if (Object.keys(selectedEmails).length === 0) {
        for (const item of items) {
          const normalized = normalizeEmail(item.email);
          if (sharedUserByEmail[normalized]) {
            selectedEmails[normalized] = true;
          }
        }
      } else {
        const available = new Set(items.map((item) => normalizeEmail(item.email)));
        for (const email of Object.keys(selectedEmails)) {
          if (!available.has(email)) {
            delete selectedEmails[email];
          }
        }
      }
      // Old behavior: default-select all emails on first load.
      // if (Object.keys(selectedEmails).length === 0) {
      //   for (const item of items) {
      //     selectedEmails[normalizeEmail(item.email)] = true;
      //   }
      // }
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    } finally {
      loading = false;
    }
  };

  onMount(async () => {
    syncSharedUsers();
    await loadSharedEmails();
    sharedLinks = await getAllSharedLinks({ albumId: album.id });

    // Old behavior: search all users and show the entire system user list.
    // const data = await searchUsers();
  });

  const toggleSelected = (email: string) => {
    const normalized = normalizeEmail(email);
    if (selectedEmails[normalized]) {
      delete selectedEmails[normalized];
    } else {
      selectedEmails[normalized] = true;
    }
  };

  const onSaveEmail = async () => {
    const email = normalizeEmail(emailInput);
    if (!email) {
      toastManager.danger($t('email_required'));
      return;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      toastManager.danger($t('invalid_email'));
      return;
    }

    try {
      isSubmitting = true;
      await addSharedEmail(album.id, email);
      selectedEmails[email] = true;
      emailInput = '';
      await loadSharedEmails();
      toastManager.success($t('success'));
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    } finally {
      isSubmitting = false;
    }
  };

  const onRemoveEmail = async (email: string) => {
    try {
      isSubmitting = true;
      await removeSharedEmail(album.id, email);
      delete selectedEmails[normalizeEmail(email)];
      await loadSharedEmails();
      toastManager.success($t('success'));
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    } finally {
      isSubmitting = false;
    }
  };
  // Old behavior: remove only from email list without selection updates.
  // const onRemoveEmail = async (email: string) => {
  //   await removeSharedEmail(album.id, email);
  // };

  const onUnshareUser = async (user: UserResponseDto) => {
    const confirmed = await modalManager.showDialog({
      icon: false,
      title: $t('album_remove_user'),
      prompt: $t('album_remove_user_confirmation', { values: { user: user.name } }),
      confirmText: $t('remove_user'),
    });

    if (!confirmed) {
      return;
    }

    try {
      isSubmitting = true;
      await removeUserFromAlbum({ id: album.id, userId: user.id });
      album = { ...album, albumUsers: album.albumUsers.filter((entry) => entry.user.id !== user.id) };
      syncSharedUsers();
      didChange = true;
      toastManager.success($t('album_user_removed', { values: { user: user.name } }));
    } catch (error) {
      handleError(error, $t('errors.unable_to_remove_album_users'));
    } finally {
      isSubmitting = false;
    }
  };

  const onShareSelected = async () => {
    const selected = selectedEmailList;
    if (selected.length === 0) {
      return;
    }

    try {
      isSubmitting = true;
      // const users = await searchUsers();
      // const userByEmail = new Map(users.map((user) => [normalizeEmail(user.email), user]));
      const existingIds = new Set([album.ownerId, ...album.albumUsers.map((entry) => entry.user.id)]);
      // const albumUsers: AlbumUserAddDto[] = [];
      // const missingEmails: string[] = [];
      // for (const email of selected) {
      //   const user = userByEmail.get(email);
      //   if (!user) {
      //     missingEmails.push(email);
      //     continue;
      //   }
      //   if (!existingIds.has(user.id)) {
      //     albumUsers.push({ userId: user.id, role: AlbumUserRole.Editor });
      //   }
      // }

      const resolution = await resolveAlbumShareEmails(album.id, selected);
      const uniqueUserIds = [...new Set(resolution.userIds)];
      const albumUsers: AlbumUserAddDto[] = uniqueUserIds
        .filter((userId) => !existingIds.has(userId))
        .map((userId) => ({ userId, role: AlbumUserRole.Editor }));
      const missingEmails = resolution.missingEmails;

      if (missingEmails.length > 0) {
        const preview = missingEmails.slice(0, 3).join(', ');
        const suffix = missingEmails.length > 3 ? '...' : '';
        toastManager.info(`Not found in Pizcloud: ${preview}${suffix}`);
      }

      if (albumUsers.length === 0) {
        toastManager.info('No new users to add from selected emails.');
        return;
      }

      onClose({ action: 'sharedUsers', data: albumUsers });
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    } finally {
      isSubmitting = false;
    }
  };
</script>

<Modal
  icon={false}
  size="small"
  title={$t('share')}
  onClose={() => onClose(didChange ? { action: 'refreshAlbum' } : undefined)}
>
  <ModalBody>
    <Text size="small" color="muted">{$t('save_email_then_share_hint')}</Text>

    <div class="mt-4 flex items-center gap-2">
      <Input
        bind:value={emailInput}
        type="email"
        placeholder={$t('email')}
        onkeydown={(event) => event.key === 'Enter' && onSaveEmail()}
      />
      <Button leadingIcon={mdiPlus} size="small" shape="round" disabled={isSubmitting} onclick={onSaveEmail}>
        {$t('add')}
      </Button>
    </div>

    {#if selectedEmailList.length > 0}
      <div class="mt-4">
        <Text size="large" color="muted">{$t('selected')}</Text>
        <div class="mt-2 flex flex-wrap gap-2">
          {#each selectedEmailList as email (email)}
            <span class="rounded-full border px-2 py-1 text-xs">{email}</span>
          {/each}
        </div>
      </div>
    {/if}

    <div class="immich-scrollbar mt-4 max-h-80 overflow-y-auto">
      {#if loading}
        <Text size="small" color="muted">{$t('loading')}</Text>
      {:else if sharedEmails.length === 0}
        <Text size="small" color="muted">{$t('album_share_no_users')}</Text>
      {:else}
        <div class="flex flex-col gap-2">
          {#each sharedEmails as item (item.email)}
            {@const normalizedEmail = normalizeEmail(item.email)}
            {@const isSelected = selectedEmails[normalizedEmail]}
            {@const sharedUser = sharedUserByEmail[normalizedEmail]}
            <div class="flex items-center gap-3 rounded-xl px-3 py-2 hover:bg-gray-200 dark:hover:bg-gray-700">
              <button
                type="button"
                class="flex h-8 w-8 items-center justify-center rounded-full border text-sm"
                onclick={() => toggleSelected(item.email)}
              >
                {#if isSelected}
                  <Icon icon={mdiCheck} size="16" />
                {/if}
              </button>
              <div class="flex flex-col grow">
                <span class="text-sm">{item.email}</span>
                {#if item.createdAt}
                  <span class="text-xs text-gray-500">{formatDate(item.createdAt)}</span>
                {/if}
              </div>
              {#if sharedUser}
                <IconButton
                  icon={mdiLinkOff}
                  size="small"
                  color="secondary"
                  aria-label={$t('remove_user')}
                  onclick={() => onUnshareUser(sharedUser)}
                />
              {/if}
              <IconButton
                icon={mdiDeleteOutline}
                size="small"
                color="secondary"
                aria-label={$t('remove_from_list')}
                onclick={() => onRemoveEmail(item.email)}
              />
            </div>
          {/each}
        </div>
      {/if}
    </div>

    <div class="mt-4">
      <Button size="small" shape="round" fullWidth disabled={!canShare || isSubmitting} onclick={onShareSelected}>
        {$t('share')}
      </Button>
    </div>

    <hr class="my-4" />

    <Stack gap={6}>
      {#if sharedLinks.length > 0}
        <div class="flex justify-between items-center">
          <Text>{$t('shared_links')}</Text>
          <a href={AppRoute.SHARED_LINKS} class="text-sm text-primary" onclick={() => onClose()}>
            {$t('view_all')}
          </a>
        </div>

        <Stack gap={4}>
          {#each sharedLinks as sharedLink (sharedLink.id)}
            <AlbumSharedLink {album} {sharedLink} />
          {/each}
        </Stack>
      {/if}

      <Button
        leadingIcon={mdiLink}
        size="small"
        shape="round"
        fullWidth
        onclick={() => onClose({ action: 'sharedLink' })}
      >
        {$t('create_link')}
      </Button>
    </Stack>
  </ModalBody>
</Modal>
