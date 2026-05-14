<script lang="ts">
  import { goto } from '$app/navigation';
  import {
    createSupportTicket,
    getSupportTickets,
    type SupportTicketCategory,
    type SupportTicketPriority,
    type SupportTicketStatus,
    type SupportTicketSummary,
    SupportTicketApiError,
    SUPPORT_TICKET_ATTACHMENT_MAX_BYTES,
  } from '$lib/services/pizcloud/support-ticket.service';
  import { handleError } from '$lib/utils/handle-error';
  import { toastManager } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  let loading = $state(true);
  let loadingMore = $state(false);
  let error = $state('');

  let items = $state<SupportTicketSummary[]>([]);
  let page = $state(1);
  let limit = $state(20);
  let total = $state(0);
  let selectedStatus = $state<'all' | SupportTicketStatus>('all');

  let subject = $state('');
  let category = $state<SupportTicketCategory>('bug');
  let priority = $state<SupportTicketPriority>('normal');
  let message = $state('');
  let attachments = $state.raw<File[]>([]);
  let submitting = $state(false);

  const categoryOptions: SupportTicketCategory[] = ['bug', 'billing', 'account', 'feature', 'other'];
  const priorityOptions: SupportTicketPriority[] = ['low', 'normal', 'high', 'urgent'];

  const statusOptions: Array<'all' | SupportTicketStatus> = [
    'all',
    'open',
    'in_progress',
    'waiting_user',
    'resolved',
    'closed',
  ];

  const canLoadMore = $derived(items.length < total);

  const statusLabel = (status: 'all' | SupportTicketStatus) => {
    switch (status) {
      case 'open':
        return $t('support_ticket.status_open');
      case 'in_progress':
        return $t('support_ticket.status_in_progress');
      case 'waiting_user':
        return $t('support_ticket.status_waiting_user');
      case 'resolved':
        return $t('support_ticket.status_resolved');
      case 'closed':
        return $t('support_ticket.status_closed');
      default:
        return $t('support_ticket.status_all');
    }
  };

  const categoryLabel = (value: SupportTicketCategory) => {
    switch (value) {
      case 'bug':
        return $t('support_ticket.category_bug');
      case 'billing':
        return $t('support_ticket.category_billing');
      case 'account':
        return $t('support_ticket.category_account');
      case 'feature':
        return $t('support_ticket.category_feature');
      default:
        return $t('support_ticket.category_other');
    }
  };

  const priorityLabel = (value: SupportTicketPriority) => {
    switch (value) {
      case 'low':
        return $t('support_ticket.priority_low');
      case 'high':
        return $t('support_ticket.priority_high');
      case 'urgent':
        return $t('support_ticket.priority_urgent');
      default:
        return $t('support_ticket.priority_normal');
    }
  };

  const mapApiError = (error: unknown) => {
    if (error instanceof SupportTicketApiError) {
      const code = (error.code || '').toUpperCase();
      switch (code) {
        case 'ATTACHMENT_TOO_LARGE':
          return $t('support_ticket.error_attachment_too_large');
        case 'SUBJECT_REQUIRED':
          return $t('support_ticket.error_subject_required');
        case 'MESSAGE_REQUIRED':
          return $t('support_ticket.error_message_required');
        default:
          return error.message || $t('support_ticket.load_error');
      }
    }

    return $t('support_ticket.load_error');
  };

  const formatDateTime = (value?: string) => {
    if (!value) {
      return '';
    }

    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return value;
    }

    return date.toLocaleString('vi-VN');
  };

  const fileSizeLabel = (bytes: number) => {
    if (bytes < 1024) {
      return `${bytes} B`;
    }

    const kb = bytes / 1024;
    if (kb < 1024) {
      return `${kb.toFixed(1)} KB`;
    }

    return `${(kb / 1024).toFixed(1)} MB`;
  };

  const resetComposer = () => {
    subject = '';
    category = 'bug';
    priority = 'normal';
    message = '';
    attachments = [];
  };

  const loadTickets = async ({ reset = false } = {}) => {
    if (reset) {
      page = 1;
      items = [];
    }

    if (page === 1) {
      loading = true;
    } else {
      loadingMore = true;
    }

    error = '';

    try {
      const data = await getSupportTickets({
        page,
        limit,
        status: selectedStatus,
      });

      total = data.pagination.total;
      limit = data.pagination.limit;

      if (page === 1) {
        items = data.items;
      } else {
        items = [...items, ...data.items];
      }
    } catch (errorValue) {
      error = mapApiError(errorValue);
      handleError(errorValue, error, { preferServerMessage: false });
    } finally {
      loading = false;
      loadingMore = false;
    }
  };

  const changeStatus = async (status: 'all' | SupportTicketStatus) => {
    if (selectedStatus === status) {
      return;
    }

    selectedStatus = status;
    page = 1;
    await loadTickets({ reset: true });
  };

  const loadMore = async () => {
    if (!canLoadMore || loadingMore) {
      return;
    }

    page += 1;
    await loadTickets();
  };

  const onSelectFiles = (event: Event) => {
    const target = event.currentTarget as HTMLInputElement;
    const selectedFiles = Array.from(target.files ?? []);
    target.value = '';

    if (selectedFiles.length === 0) {
      return;
    }

    const existingNames = new Set(attachments.map((file) => `${file.name}:${file.size}`));
    const nextFiles = [...attachments];

    for (const file of selectedFiles) {
      if (file.size > SUPPORT_TICKET_ATTACHMENT_MAX_BYTES) {
        toastManager.warning($t('support_ticket.error_attachment_too_large'));
        continue;
      }

      const fingerprint = `${file.name}:${file.size}`;
      if (existingNames.has(fingerprint)) {
        continue;
      }

      existingNames.add(fingerprint);
      nextFiles.push(file);
    }

    attachments = nextFiles;
  };

  const removeAttachment = (index: number) => {
    attachments = attachments.filter((_, idx) => idx !== index);
  };

  const submit = async () => {
    const normalizedSubject = subject.trim();
    const normalizedMessage = message.trim();

    if (!normalizedSubject) {
      toastManager.warning($t('support_ticket.error_subject_required'));
      return;
    }

    if (!normalizedMessage) {
      toastManager.warning($t('support_ticket.error_message_required'));
      return;
    }

    submitting = true;
    try {
      const attachmentPayload = $state.snapshot(attachments);
      const detail = await createSupportTicket({
        subject: normalizedSubject,
        category,
        priority,
        message: normalizedMessage,
        attachments: attachmentPayload,
      });

      toastManager.success($t('support_ticket.create_success'));
      resetComposer();
      await goto(`/pizcloud/support/${detail.ticket.id}`);
    } catch (errorValue) {
      const message = mapApiError(errorValue);
      handleError(errorValue, message, { preferServerMessage: false });
    } finally {
      submitting = false;
    }
  };

  onMount(() => {
    void loadTickets({ reset: true });
  });
</script>

<section class="support-ticket">
  <header class="support-ticket__header">
    <h1>{$t('support_ticket.title')}</h1>
  </header>

  <article class="support-ticket__composer">
    <h2>{$t('support_ticket.create')}</h2>
    <p>{$t('support_ticket.create_description')}</p>

    <div class="support-ticket__field-grid">
      <label>
        <span>{$t('support_ticket.subject')}</span>
        <input bind:value={subject} maxlength="120" placeholder={$t('support_ticket.subject_hint')} />
      </label>

      <label>
        <span>{$t('support_ticket.category')}</span>
        <select bind:value={category}>
          {#each categoryOptions as option}
            <option value={option}>{categoryLabel(option)}</option>
          {/each}
        </select>
      </label>

      <label>
        <span>{$t('support_ticket.priority')}</span>
        <select bind:value={priority}>
          {#each priorityOptions as option}
            <option value={option}>{priorityLabel(option)}</option>
          {/each}
        </select>
      </label>
    </div>

    <label class="support-ticket__message-field">
      <span>{$t('support_ticket.message')}</span>
      <textarea bind:value={message} maxlength="4000" rows="5" placeholder={$t('support_ticket.message_hint')}></textarea>
    </label>

    <div class="support-ticket__attach-row">
      <label class="support-ticket__attach-button" for="support-ticket-file-input">{$t('support_ticket.add_attachment')}</label>
      <input id="support-ticket-file-input" type="file" multiple onchange={onSelectFiles} />
      <small>{$t('support_ticket.attachment_limit')}</small>
    </div>

    {#if attachments.length > 0}
      <ul class="support-ticket__attachments">
        {#each attachments as file, index}
          <li>
            <div>
              <strong>{file.name}</strong>
              <small>{fileSizeLabel(file.size)}</small>
            </div>
            <button type="button" onclick={() => removeAttachment(index)}>×</button>
          </li>
        {/each}
      </ul>
    {/if}

    <div class="support-ticket__composer-actions">
      <button type="button" class="support-ticket__primary" onclick={submit} disabled={submitting}>
        {#if submitting}
          {$t('loading')}...
        {:else}
          {$t('support_ticket.submit')}
        {/if}
      </button>
    </div>
  </article>

  <section class="support-ticket__list-card">
    <div class="support-ticket__filters">
      {#each statusOptions as status}
        <button
          type="button"
          class:active={selectedStatus === status}
          onclick={() => changeStatus(status)}
          disabled={loading}
        >
          {statusLabel(status)}
        </button>
      {/each}
    </div>

    {#if loading}
      <div class="support-ticket__empty">{$t('loading')}...</div>
    {:else if error}
      <div class="support-ticket__empty">
        <p>{error}</p>
        <button type="button" onclick={() => loadTickets({ reset: true })}>{$t('retry')}</button>
      </div>
    {:else if items.length === 0}
      <div class="support-ticket__empty">{$t('support_ticket.empty')}</div>
    {:else}
      <ul class="support-ticket__list">
        {#each items as ticket (ticket.id)}
          <li>
            <a href={`/pizcloud/support/${ticket.id}`}>
              <div class="support-ticket__ticket-head">
                <h3>{ticket.subject}</h3>
                <span class={`status status--${ticket.status}`}>{statusLabel(ticket.status)}</span>
              </div>

              <div class="support-ticket__ticket-meta">
                <span>{categoryLabel(ticket.category)}</span>
                <span>{priorityLabel(ticket.priority)}</span>
                {#if ticket.attachments.length > 0}
                  <span>{$t('support_ticket.attachment_count', { values: { count: ticket.attachments.length } })}</span>
                {/if}
              </div>

              {#if ticket.latestMessage}
                <p>{ticket.latestMessage}</p>
              {/if}

              <div class="support-ticket__ticket-foot">
                <small>
                  {$t('support_ticket.updated_at', { values: { date: formatDateTime(ticket.updatedAt || ticket.createdAt) } })}
                </small>
                {#if ticket.unreadCount > 0}
                  <span class="support-ticket__unread">
                    {$t('support_ticket.unread_count', { values: { count: ticket.unreadCount } })}
                  </span>
                {/if}
              </div>
            </a>
          </li>
        {/each}
      </ul>

      {#if canLoadMore}
        <div class="support-ticket__load-more">
          <button type="button" onclick={loadMore} disabled={loadingMore}>
            {#if loadingMore}
              {$t('loading')}...
            {:else}
              {$t('support_ticket.load_more')}
            {/if}
          </button>
        </div>
      {/if}
    {/if}
  </section>
</section>

<style>
  .support-ticket {
    --st-bg: var(--immich-bg-elevated, #ffffff);
    --st-bg-soft: var(--immich-bg-subtle, #f8fafc);
    --st-bg-muted: var(--immich-bg-muted, #f1f5f9);
    --st-border: var(--immich-border-subtle, #e2e8f0);
    --st-text: var(--immich-fg, inherit);
    --st-text-muted: var(--immich-fg-muted, #64748b);
    --st-accent: var(--immich-accent, #2563eb);
    --st-accent-strong: var(--immich-accent-strong, #1d4ed8);
    --st-shadow: 0 8px 22px rgba(15, 23, 42, 0.06);
    display: grid;
    gap: 1.2rem;
    padding-block: 1.35rem 2.25rem;
  }

  .support-ticket__header h1 {
    font-size: 1.65rem;
    font-weight: 650;
    color: var(--st-text);
    margin: 0;
  }

  .support-ticket__composer,
  .support-ticket__list-card {
    border: 1px solid var(--st-border);
    border-radius: 1rem;
    padding: 1.1rem;
    background: var(--st-bg);
    box-shadow: var(--st-shadow);
  }

  .support-ticket__composer h2 {
    margin: 0 0 0.25rem;
    font-size: 1.18rem;
    font-weight: 620;
  }

  .support-ticket__composer p {
    margin: 0 0 1rem;
    color: var(--st-text-muted);
    font-size: 0.92rem;
  }

  .support-ticket__field-grid {
    display: grid;
    gap: 0.75rem;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    margin-bottom: 0.75rem;
  }

  label {
    display: grid;
    gap: 0.38rem;
    font-size: 0.84rem;
    color: var(--st-text-muted);
    font-weight: 520;
  }

  input,
  select,
  textarea {
    border: 1px solid var(--st-border);
    border-radius: 0.65rem;
    padding: 0.64rem 0.72rem;
    background: var(--st-bg-soft);
    color: var(--st-text);
    font: inherit;
    transition:
      border-color 0.15s ease,
      box-shadow 0.15s ease;
  }

  input:focus,
  select:focus,
  textarea:focus {
    outline: none;
    border-color: var(--st-accent);
    box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.16);
  }

  textarea {
    resize: vertical;
  }

  .support-ticket__attach-row {
    display: flex;
    gap: 0.75rem;
    align-items: center;
    margin-top: 0.75rem;
  }

  .support-ticket__attach-row input[type='file'] {
    display: none;
  }

  .support-ticket__attach-button {
    display: inline-flex;
    border: 1px solid var(--st-border);
    border-radius: 999px;
    padding: 0.42rem 0.85rem;
    cursor: pointer;
    font-size: 0.84rem;
    font-weight: 540;
    color: var(--st-text);
    background: var(--st-bg-soft);
    transition: background-color 0.15s ease;
  }

  .support-ticket__attach-button:hover {
    background: var(--st-bg-muted);
  }

  .support-ticket__attach-row small {
    color: var(--st-text-muted);
  }

  .support-ticket__attachments {
    list-style: none;
    margin: 0.75rem 0 0;
    padding: 0;
    display: grid;
    gap: 0.35rem;
  }

  .support-ticket__attachments li {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border: 1px solid var(--st-border);
    border-radius: 0.6rem;
    padding: 0.45rem 0.6rem;
    background: var(--st-bg-soft);
  }

  .support-ticket__attachments strong {
    font-size: 0.85rem;
  }

  .support-ticket__attachments small {
    display: block;
    color: var(--st-text-muted);
  }

  .support-ticket__attachments button {
    border: 0;
    background: transparent;
    font-size: 1.1rem;
    cursor: pointer;
    color: inherit;
  }

  .support-ticket__composer-actions {
    margin-top: 1rem;
    display: flex;
    justify-content: flex-end;
  }

  .support-ticket__primary {
    border: 0;
    border-radius: 999px;
    padding: 0.58rem 1.05rem;
    background: var(--st-accent);
    color: #fff;
    cursor: pointer;
    font-weight: 560;
    transition:
      background-color 0.15s ease,
      transform 0.05s ease;
  }

  .support-ticket__primary:hover {
    background: var(--st-accent-strong);
  }

  .support-ticket__primary:active {
    transform: translateY(1px);
  }

  .support-ticket__primary:disabled {
    cursor: not-allowed;
    opacity: 0.7;
  }

  .support-ticket__filters {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-bottom: 0.75rem;
  }

  .support-ticket__filters button {
    border: 1px solid var(--st-border);
    border-radius: 999px;
    padding: 0.37rem 0.78rem;
    background: var(--st-bg-soft);
    cursor: pointer;
    color: var(--st-text);
    transition:
      background-color 0.15s ease,
      border-color 0.15s ease;
  }

  .support-ticket__filters button:hover:not(.active) {
    background: var(--st-bg-muted);
  }

  .support-ticket__filters button.active {
    background: var(--st-accent);
    color: #fff;
    border-color: transparent;
  }

  .support-ticket__list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 0.75rem;
  }

  .support-ticket__list li a {
    display: block;
    border: 1px solid var(--st-border);
    border-radius: 0.8rem;
    padding: 0.85rem;
    color: var(--st-text);
    text-decoration: none;
    background: var(--st-bg-soft);
    transition:
      transform 0.09s ease,
      border-color 0.15s ease,
      box-shadow 0.15s ease;
  }

  .support-ticket__list li a:hover {
    transform: translateY(-1px);
    border-color: rgba(37, 99, 235, 0.45);
    box-shadow: 0 8px 20px rgba(15, 23, 42, 0.08);
  }

  .support-ticket__ticket-head {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 0.6rem;
  }

  .support-ticket__ticket-head h3 {
    margin: 0;
    font-size: 1rem;
  }

  .support-ticket__ticket-meta {
    margin-top: 0.45rem;
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
  }

  .support-ticket__ticket-meta span {
    font-size: 0.72rem;
    border-radius: 999px;
    background: var(--st-bg-muted);
    padding: 0.2rem 0.55rem;
    color: var(--st-text-muted);
  }

  .support-ticket__list p {
    margin: 0.6rem 0 0;
    color: var(--st-text-muted);
    font-size: 0.88rem;
    line-height: 1.35;
  }

  .support-ticket__ticket-foot {
    margin-top: 0.65rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 0.5rem;
  }

  .support-ticket__ticket-foot small {
    color: var(--st-text-muted);
  }

  .support-ticket__unread {
    border-radius: 999px;
    background: var(--st-accent);
    color: white;
    font-size: 0.72rem;
    padding: 0.2rem 0.5rem;
  }

  .status {
    border-radius: 999px;
    padding: 0.2rem 0.55rem;
    font-size: 0.72rem;
    white-space: nowrap;
    font-weight: 600;
  }

  .status--open {
    background: rgba(59, 130, 246, 0.18);
    color: #2563eb;
  }

  .status--in_progress {
    background: rgba(30, 64, 175, 0.18);
    color: #1e40af;
  }

  .status--waiting_user {
    background: rgba(245, 158, 11, 0.2);
    color: #92400e;
  }

  .status--resolved {
    background: rgba(34, 197, 94, 0.2);
    color: #166534;
  }

  .status--closed {
    background: rgba(148, 163, 184, 0.2);
    color: #475569;
  }

  .support-ticket__empty {
    border: 1px dashed var(--st-border);
    border-radius: 0.75rem;
    padding: 1.1rem;
    color: var(--st-text-muted);
    background: var(--st-bg-soft);
  }

  .support-ticket__empty button {
    margin-top: 0.5rem;
    border: 1px solid var(--st-border);
    border-radius: 999px;
    background: var(--st-bg-muted);
    padding: 0.35rem 0.75rem;
    cursor: pointer;
    color: var(--st-text);
  }

  .support-ticket__load-more {
    margin-top: 0.8rem;
    display: flex;
    justify-content: center;
  }

  .support-ticket__load-more button {
    border: 1px solid var(--st-border);
    border-radius: 999px;
    background: var(--st-bg-soft);
    padding: 0.4rem 1rem;
    cursor: pointer;
    color: var(--st-text);
  }

  .support-ticket__load-more button:disabled {
    cursor: not-allowed;
    opacity: 0.65;
  }

  @media (max-width: 720px) {
    .support-ticket {
      gap: 1rem;
      padding-block: 1rem 2rem;
    }

    .support-ticket__composer,
    .support-ticket__list-card {
      padding: 0.9rem;
    }

    .support-ticket__header h1 {
      font-size: 1.45rem;
    }
  }
</style>
