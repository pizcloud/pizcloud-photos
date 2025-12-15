<!-- web/src/routes/(user)/pizcloud/withdrawals/+page.svelte -->
<script lang="ts">
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import ShortcutsModal from '$lib/modals/ShortcutsModal.svelte';
  import { Container, IconButton, modalManager } from '@immich/ui';
  import { mdiKeyboard } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  import UserWithdrawals from '$lib/components/pizcloud/user-withdrawals/user-withdrawals.svelte';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();
</script>

<UserPageLayout title={data.meta.title}>
  {#snippet buttons()}
    <IconButton
      shape="round"
      color="secondary"
      variant="ghost"
      icon={mdiKeyboard}
      aria-label={$t('show_keyboard_shortcuts')}
      onclick={() => modalManager.show(ShortcutsModal, {})}
    />
  {/snippet}

  <Container size="medium" center>
    <UserWithdrawals userEmail={data.userEmail ?? ''} />
  </Container>
</UserPageLayout>
