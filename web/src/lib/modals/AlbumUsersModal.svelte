<script lang="ts">
  import ButtonContextMenu from '$lib/components/shared-components/context-menu/button-context-menu.svelte';
  import MenuOption from '$lib/components/shared-components/context-menu/menu-option.svelte';
  import UserAvatar from '$lib/components/shared-components/user-avatar.svelte';
  // import { getSharedEmails } from '$lib/services/pizcloud/album-share-email.service';
  import { handleError } from '$lib/utils/handle-error';
  import {
    AlbumUserRole,
    getMyUser,
    removeUserFromAlbum,
    updateAlbumUser,
    type AlbumResponseDto,
    type UserResponseDto,
  } from '@immich/sdk';
  import { Button, Modal, ModalBody, Text, modalManager, toastManager } from '@immich/ui';
  import { mdiDotsVertical } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  interface Props {
    album: AlbumResponseDto;
    onClose: (changed?: boolean) => void;
  }

  let { album, onClose }: Props = $props();

  let currentUser: UserResponseDto | undefined = $state();

  let isOwned = $derived(currentUser?.id == album.ownerId);

  // pizcloud: For shared viewers, mask other users' names/emails in Options.
  let maskForSharedViewer = true;
  // let maskForSharedViewer = false; // If needed, turn off masking entirely.
  const maskEmail = (email: string) => {
    const normalized = email.trim().toLowerCase();
    const atIndex = normalized.indexOf('@');
    if (atIndex <= 0) {
      return '****@';
    }
    return `****@${normalized.slice(atIndex + 1)}`;
  };
  const displayName = (user: UserResponseDto) => {
    if (!maskForSharedViewer || isOwned || user.id === currentUser?.id) {
      return user.name;
    }
    return '****';
  };
  const displayEmail = (user: UserResponseDto) => {
    if (!maskForSharedViewer || isOwned || user.id === currentUser?.id) {
      return user.email;
    }
    return maskEmail(user.email);
  };
  const userRows = $derived(
    [{ user: album.owner, role: 'owner' }, ...album.albumUsers].map(({ user, role }) => ({
      user,
      role,
      displayName: displayName(user),
      displayEmail: displayEmail(user),
    })),
  );
  // #pizcloud

  // Build a map of contributor counts by user id; avoid casts/derived
  const contributorCounts: Record<string, number> = {};
  if (album.contributorCounts) {
    for (const { userId, assetCount } of album.contributorCounts) {
      contributorCounts[userId] = assetCount;
    }
  }

  onMount(async () => {
    try {
      currentUser = await getMyUser();
    } catch (error) {
      handleError(error, $t('errors.unable_to_refresh_user'));
    }
  });

  // pizcloud
  // Old behavior: use server-p saved emails to decide masking.
  // onMount(async () => {
  //   try {
  //     const items = await getSharedEmails(album.id);
  //     knownEmails = new Set(items.map((item) => normalizeEmail(item.email)));
  //   } catch (error) {
  //     handleError(error, $t('errors.something_went_wrong'));
  //   }
  // });
  // #pizcloud

  const handleRemoveUser = async (user: UserResponseDto) => {
    if (!user) {
      return;
    }

    const userId = user.id === currentUser?.id ? 'me' : user.id;
    let confirmed: boolean | undefined;

    // eslint-disable-next-line unicorn/prefer-ternary
    if (userId === 'me') {
      confirmed = await modalManager.showDialog({
        icon: false,
        title: $t('album_leave'),
        prompt: $t('album_leave_confirmation', { values: { album: album.albumName } }),
        confirmText: $t('leave'),
      });
    } else {
      confirmed = await modalManager.showDialog({
        icon: false,
        title: $t('album_remove_user'),
        prompt: $t('album_remove_user_confirmation', { values: { user: user.name } }),
        confirmText: $t('remove_user'),
      });
    }

    if (!confirmed) {
      return;
    }

    try {
      await removeUserFromAlbum({ id: album.id, userId });
      const message =
        userId === 'me'
          ? $t('album_user_left', { values: { album: album.albumName } })
          : $t('album_user_removed', { values: { user: user.name } });
      toastManager.success(message);
      onClose(true);
    } catch (error) {
      handleError(error, $t('errors.unable_to_remove_album_users'));
    }
  };

  const handleChangeRole = async (user: UserResponseDto, role: AlbumUserRole) => {
    try {
      await updateAlbumUser({ id: album.id, userId: user.id, updateAlbumUserDto: { role } });
      const message = $t('user_role_set', {
        values: { user: user.name, role: role == AlbumUserRole.Viewer ? $t('role_viewer') : $t('role_editor') },
      });
      toastManager.success(message);
      onClose(true);
    } catch (error) {
      handleError(error, $t('errors.unable_to_change_album_user_role'));
    }
  };
</script>

<Modal icon={false} title={$t('options')} size="small" {onClose}>
  <ModalBody>
    <section class="immich-scrollbar max-h-100 overflow-y-auto pb-4">
      <!-- pizcloud -->
      {#each userRows as { user, role, displayName, displayEmail } (user.id)}
        <div class="flex w-full place-items-center justify-between gap-4 p-5 rounded-xl transition-colors">
          <div class="flex place-items-center gap-4">
            <UserAvatar {user} size="md" />
            <div class="flex flex-col">
              <p class="font-medium">{displayName}</p>
              {#if displayEmail}
                <Text color="muted" size="tiny">{displayEmail}</Text>
              {/if}
              <Text color="muted" size="tiny">
                {#if role === 'owner'}
                  {$t('owner')}
                {:else if role === AlbumUserRole.Viewer}
                  {$t('role_viewer')}
                {:else}
                  {$t('role_editor')}
                {/if}
                {#if user.id in contributorCounts}
                  <span>-</span>
                  {$t('items_count', { values: { count: contributorCounts[user.id] } })}
                {/if}
              </Text>
            </div>
          </div>

          <div id="icon-{user.id}" class="flex place-items-center">
            {#if isOwned}
              <ButtonContextMenu icon={mdiDotsVertical} size="medium" title={$t('options')}>
                {#if role === AlbumUserRole.Viewer}
                  <MenuOption onClick={() => handleChangeRole(user, AlbumUserRole.Editor)} text={$t('allow_edits')} />
                {:else}
                  <MenuOption
                    onClick={() => handleChangeRole(user, AlbumUserRole.Viewer)}
                    text={$t('disallow_edits')}
                  />
                {/if}
                <MenuOption onClick={() => handleRemoveUser(user)} text={$t('remove')} />
              </ButtonContextMenu>
            {:else if user.id == currentUser?.id}
              <Button shape="round" variant="ghost" leadingIcon={undefined} onclick={() => handleRemoveUser(user)}
                >{$t('leave')}</Button
              >
            {/if}
          </div>
        </div>
      {/each}
      <!-- Old list: always render full emails and no masking -->
      <!--
      {#each [{ user: album.owner, role: 'owner' }, ...album.albumUsers] as { user, role } (user.id)}
        <div class="flex w-full place-items-center justify-between gap-4 p-5 rounded-xl transition-colors">
          <div class="flex place-items-center gap-4">
            <UserAvatar {user} size="md" />
            <div class="flex flex-col">
              <p class="font-medium">{user.name}</p>
              <Text color="muted" size="tiny">{user.email}</Text>
              <Text color="muted" size="tiny">
                {#if role === 'owner'}
                  {$t('owner')}
                {:else if role === AlbumUserRole.Viewer}
                  {$t('role_viewer')}
                {:else}
                  {$t('role_editor')}
                {/if}
                {#if user.id in contributorCounts}
                  <span>-</span>
                  {$t('items_count', { values: { count: contributorCounts[user.id] } })}
                {/if}
              </Text>
            </div>
          </div>

          <div id="icon-{user.id}" class="flex place-items-center">
            {#if isOwned}
              <ButtonContextMenu icon={mdiDotsVertical} size="medium" title={$t('options')}>
                {#if role === AlbumUserRole.Viewer}
                  <MenuOption onClick={() => handleChangeRole(user, AlbumUserRole.Editor)} text={$t('allow_edits')} />
                {:else}
                  <MenuOption
                    onClick={() => handleChangeRole(user, AlbumUserRole.Viewer)}
                    text={$t('disallow_edits')}
                  />
                {/if}
                <MenuOption onClick={() => handleRemoveUser(user)} text={$t('remove')} />
              </ButtonContextMenu>
            {:else if user.id == currentUser?.id}
              <Button shape="round" variant="ghost" leadingIcon={undefined} onclick={() => handleRemoveUser(user)}
                >{$t('leave')}</Button
              >
            {/if}
          </div>
        </div>
      {/each}
      -->
      <!-- #pizcloud -->
    </section>
  </ModalBody>
</Modal>
