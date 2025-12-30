<script lang="ts">
  import {
    addPartnerSharedEmail,
    getPartnerSharedEmails,
    removePartnerSharedEmail,
  } from '$lib/services/pizcloud/partner-share-email.service';
  // pizcloud
  import { resolvePartnerShareEmails } from '$lib/services/pizcloud/partner-share-resolve.service'; // pizcloud
  import { handleError } from '$lib/utils/handle-error';
  import { getPartners, PartnerDirection, type UserResponseDto } from '@immich/sdk';
  import { Button, Icon, Input, Modal, ModalBody, ModalFooter, toastManager } from '@immich/ui';
  import { mdiCheck, mdiDeleteOutline, mdiPlus } from '@mdi/js';
  // pizcloud
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  interface Props {
    user: UserResponseDto;
    onClose: (userIds?: string[]) => void; // pizcloud
  }

  let { user, onClose }: Props = $props();
  // pizcloud
  type SharedEmailDto = { email: string; createdAt: string };

  let sharedEmails: SharedEmailDto[] = $state([]);
  let selectedEmails: Record<string, boolean> = $state({});
  let emailInput = $state('');
  let existingPartnerIds = new Set<string>();
  let existingPartnerEmails = new Set<string>();
  let loading = $state(true);
  let isSubmitting = $state(false);

  const syncSelectedFromPartners = () => {
    if (sharedEmails.length === 0) {
      return;
    }
    for (const item of sharedEmails) {
      const normalized = normalizeEmail(item.email);
      if (existingPartnerEmails.has(normalized)) {
        selectedEmails[normalized] = true;
      }
    }
  };
  // #pizcloud

  // pizcloud
  onMount(async () => {
    try {
      const partners = await getPartners({ direction: PartnerDirection.SharedBy });
      existingPartnerIds = new Set(partners.map((partner) => partner.id));
      existingPartnerEmails = new Set(partners.map((partner) => normalizeEmail(partner.email)));
      sharedEmails = await getPartnerSharedEmails();
      syncSelectedFromPartners();
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    } finally {
      loading = false;
    }
  });

  const normalizeEmail = (value: string) => value.trim().toLowerCase();
  const selectedEmailList = () => Object.keys(selectedEmails).filter((email) => selectedEmails[email]);

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
      await addPartnerSharedEmail(email);
      selectedEmails[email] = true;
      emailInput = '';
      sharedEmails = await getPartnerSharedEmails();
      syncSelectedFromPartners();
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
      await removePartnerSharedEmail(email);
      delete selectedEmails[normalizeEmail(email)];
      sharedEmails = await getPartnerSharedEmails();
      syncSelectedFromPartners();
      toastManager.success($t('success'));
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    } finally {
      isSubmitting = false;
    }
  };
  // Old behavior: no preselect for already-shared partners.
  // const syncSelectedFromPartners = () => {};
  // Old behavior: remove only from email list without selection updates.
  // const onRemoveEmail = async (email: string) => {
  //   await removePartnerSharedEmail(email);
  // };

  const onShareSelected = async () => {
    const selected = selectedEmailList();
    if (selected.length === 0) {
      return;
    }

    try {
      isSubmitting = true;
      const resolution = await resolvePartnerShareEmails(selected);
      const uniqueUserIds = [...new Set(resolution.userIds)];
      const userIdsToAdd = uniqueUserIds.filter((id) => id !== user.id && !existingPartnerIds.has(id));

      if (resolution.missingEmails.length > 0) {
        const preview = resolution.missingEmails.slice(0, 3).join(', ');
        const suffix = resolution.missingEmails.length > 3 ? '...' : '';
        toastManager.info(`Not found in Pizcloud: ${preview}${suffix}`);
      }

      if (userIdsToAdd.length === 0) {
        toastManager.info('No new users to add from selected emails.');
        return;
      }

      onClose(userIdsToAdd);
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    } finally {
      isSubmitting = false;
    }
  };
  // #pizcloud
</script>

<Modal icon={false} title={$t('add_partner')} {onClose} size="small">
  <ModalBody>
    <!-- pizcloud -->
    <div class="mb-3 flex items-center gap-2">
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

    <div class="immich-scrollbar max-h-75 overflow-y-auto">
      {#if loading}
        <p class="py-5 text-sm">{$t('loading')}</p>
      {:else if sharedEmails.length === 0}
        <p class="py-5 text-sm">{$t('partner_page_no_more_users')}</p>
      {:else}
        {#each sharedEmails as item (item.email)}
          {@const normalizedEmail = normalizeEmail(item.email)}
          {@const isSelected = selectedEmails[normalizedEmail]}
          <div
            class="flex w-full place-items-center gap-4 px-5 py-4 transition-all hover:bg-gray-200 dark:hover:bg-gray-700 rounded-xl"
          >
            <button
              type="button"
              onclick={() => toggleSelected(item.email)}
              class="flex h-10 w-10 place-content-center place-items-center rounded-full border text-lg"
            >
              {#if isSelected}
                <Icon icon={mdiCheck} size="18" />
              {/if}
            </button>

            <div class="text-start grow">
              <p class="text-immich-fg dark:text-immich-dark-fg">
                {item.email}
              </p>
              {#if item.createdAt}
                <p class="text-xs text-immich-fg/70 dark:text-immich-dark-fg/70">
                  {item.createdAt}
                </p>
              {/if}
            </div>

            <Button
              shape="round"
              size="small"
              color="secondary"
              variant="ghost"
              leadingIcon={mdiDeleteOutline}
              onclick={() => onRemoveEmail(item.email)}
            >
              {$t('remove')}
            </Button>
          </div>
        {/each}
      {/if}
    </div>

    <ModalFooter>
      {#if selectedEmailList().length > 0}
        <Button shape="round" fullWidth onclick={onShareSelected} disabled={isSubmitting}>{$t('share')}</Button>
      {/if}
    </ModalFooter>

    <!-- Old UI: show all system users -->
    <!--
    <div class="immich-scrollbar max-h-75 overflow-y-auto">
      {#if availableUsers.length > 0}
        {#each availableUsers as user (user.id)}
          <button
            type="button"
            onclick={() => selectUser(user)}
            class="flex w-full place-items-center gap-4 px-5 py-4 transition-all hover:bg-gray-200 dark:hover:bg-gray-700 rounded-xl"
          >
            {#if selectedUsers.includes(user)}
              <span
                class="flex h-12 w-12 place-content-center place-items-center rounded-full border bg-immich-primary text-3xl text-white dark:border-immich-dark-gray dark:bg-immich-dark-primary dark:text-immich-dark-bg"
                >✓</span
              >
            {:else}
              <UserAvatar {user} size="lg" />
            {/if}

            <div class="text-start">
              <p class="text-immich-fg dark:text-immich-dark-fg">
                {user.name}
              </p>
              <p class="text-xs">
                {user.email}
              </p>
            </div>
          </button>
        {/each}
      {:else}
        <p class="py-5 text-sm">
          {$t('photo_shared_all_users')}
        </p>
      {/if}

      <ModalFooter>
        {#if selectedUsers.length > 0}
          <Button shape="round" fullWidth onclick={() => onClose(selectedUsers)}>{$t('add')}</Button>
        {/if}
      </ModalFooter>
    </div>
    -->
    <!-- #pizcloud -->
  </ModalBody>
</Modal>
