<script lang="ts">
  import { goto } from '$app/navigation';
  import {
    getSupportTicketDetail,
    replySupportTicket,
    updateSupportTicketStatus,
    type SupportTicketDetail,
    type SupportTicketPriority,
    type SupportTicketStatus,
    SupportTicketApiError,
    SUPPORT_TICKET_ATTACHMENT_MAX_BYTES,
  } from '$lib/services/pizcloud/support-ticket.service';
  import { handleError } from '$lib/utils/handle-error';
  import { toastManager } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  interface Props {
    ticketId: string;
  }

  let { ticketId }: Props = $props();

  let loading = $state(true);
  let actionLoading = $state(false);
  let error = $state('');
  let detail = $state<SupportTicketDetail | null>(null);

  let replyMessage = $state('');
  let replyAttachments = $state<File[]>([]);

  const isClosed = $derived(detail?.ticket.status === 'closed');

  const statusLabel = (status: SupportTicketStatus) => {
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

  const categoryLabel = (value: string) => {
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

  const mapApiError = (errorValue: unknown) => {
    if (errorValue instanceof SupportTicketApiError) {
      const code = (errorValue.code || '').toUpperCase();
      switch (code) {
        case 'ATTACHMENT_TOO_LARGE':
          return $t('support_ticket.error_attachment_too_large');
        case 'MESSAGE_REQUIRED':
          return $t('support_ticket.error_message_required');
        case 'TICKET_NOT_FOUND':
          return $t('support_ticket.error_ticket_not_found');
        default:
          return errorValue.message || $t('support_ticket.load_error');
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

  const loadDetail = async () => {
    loading = true;
    error = '';

    try {
      detail = await getSupportTicketDetail(ticketId);
    } catch (errorValue) {
      error = mapApiError(errorValue);
      handleError(errorValue, error, { preferServerMessage: false });
    } finally {
      loading = false;
    }
  };

  const onSelectReplyFiles = (event: Event) => {
    const target = event.currentTarget as HTMLInputElement;
    const selectedFiles = Array.from(target.files ?? []);
    target.value = '';

    if (selectedFiles.length === 0) {
      return;
    }

    const nextFiles = [...replyAttachments];
    const existing = new Set(nextFiles.map((file) => `${file.name}:${file.size}`));

    for (const file of selectedFiles) {
      if (file.size > SUPPORT_TICKET_ATTACHMENT_MAX_BYTES) {
        toastManager.warning($t('support_ticket.error_attachment_too_large'));
        continue;
      }

      const fingerprint = `${file.name}:${file.size}`;
      if (existing.has(fingerprint)) {
        continue;
      }

      existing.add(fingerprint);
      nextFiles.push(file);
    }

    replyAttachments = nextFiles;
  };

  const removeReplyAttachment = (index: number) => {
    replyAttachments = replyAttachments.filter((_, idx) => idx !== index);
  };

  const sendReply = async () => {
    const normalizedMessage = replyMessage.trim();
    if (!normalizedMessage) {
      toastManager.warning($t('support_ticket.error_message_required'));
      return;
    }

    if (!detail) {
      return;
    }

    actionLoading = true;
    try {
      detail = await replySupportTicket({
        ticketId: detail.ticket.id,
        message: normalizedMessage,
        attachments: replyAttachments,
      });
      replyMessage = '';
      replyAttachments = [];
      toastManager.success($t('support_ticket.reply_success'));
    } catch (errorValue) {
      const message = mapApiError(errorValue);
      handleError(errorValue, message, { preferServerMessage: false });
    } finally {
      actionLoading = false;
    }
  };

  const toggleStatus = async () => {
    if (!detail) {
      return;
    }

    actionLoading = true;

    try {
      const targetStatus: SupportTicketStatus = detail.ticket.status === 'closed' ? 'open' : 'closed';
      await updateSupportTicketStatus(detail.ticket.id, targetStatus);
      await loadDetail();
      toastManager.success(
        targetStatus === 'closed' ? $t('support_ticket.close_success') : $t('support_ticket.reopen_success'),
      );
    } catch (errorValue) {
      const message = mapApiError(errorValue);
      handleError(errorValue, message, { preferServerMessage: false });
    } finally {
      actionLoading = false;
    }
  };

  onMount(() => {
    void loadDetail();
  });
</script>

<section class="support-ticket-detail">
  <div class="support-ticket-detail__back-row">
    <button type="button" onclick={() => goto('/pizcloud/support')}>← {$t('back')}</button>
  </div>

  {#if loading}
    <div class="support-ticket-detail__state">{$t('loading')}...</div>
  {:else if error}
    <div class="support-ticket-detail__state">
      <p>{error}</p>
      <button type="button" onclick={loadDetail}>{$t('retry')}</button>
    </div>
  {:else if !detail}
    <div class="support-ticket-detail__state">{$t('support_ticket.error_ticket_not_found')}</div>
  {:else}
    <article class="support-ticket-detail__header-card">
      <div class="support-ticket-detail__header-row">
        <h1>{detail.ticket.subject}</h1>
        <span class={`status status--${detail.ticket.status}`}>{statusLabel(detail.ticket.status)}</span>
      </div>

      <div class="support-ticket-detail__meta">
        <span>{categoryLabel(detail.ticket.category)}</span>
        <span>{priorityLabel(detail.ticket.priority)}</span>
      </div>

      <div class="support-ticket-detail__updated-row">
        <small>
          {$t('support_ticket.updated_at', { values: { date: formatDateTime(detail.ticket.updatedAt || detail.ticket.createdAt) } })}
        </small>

        <button type="button" onclick={toggleStatus} disabled={actionLoading}>
          {#if isClosed}
            {$t('support_ticket.reopen')}
          {:else}
            {$t('support_ticket.close')}
          {/if}
        </button>
      </div>
    </article>

    <section class="support-ticket-detail__messages-card">
      {#if detail.messages.length === 0}
        <p class="support-ticket-detail__state">{$t('support_ticket.load_error')}</p>
      {:else}
        <ul>
          {#each detail.messages as item (item.id)}
            <li class:item--user={item.senderType === 'user'}>
              <div class="message-head">
                <strong>{item.senderType === 'user' ? $t('support_ticket.sender_you') : $t('support_ticket.sender_support')}</strong>
                {#if item.createdAt}
                  <small>{formatDateTime(item.createdAt)}</small>
                {/if}
              </div>
              <p>{item.message}</p>
              {#if item.attachments.length > 0}
                <ul class="message-attachments">
                  {#each item.attachments as attachment}
                    <li>
                      <span>{attachment.fileName}</span>
                      <small>{fileSizeLabel(attachment.size)}</small>
                    </li>
                  {/each}
                </ul>
              {/if}
            </li>
          {/each}
        </ul>
      {/if}
    </section>

    {#if !isClosed}
      <section class="support-ticket-detail__reply-card">
        <label>
          <span>{$t('support_ticket.reply_placeholder')}</span>
          <textarea bind:value={replyMessage} rows="4" maxlength="4000"></textarea>
        </label>

        <div class="support-ticket-detail__reply-actions">
          <label class="attach" for="support-ticket-reply-file-input">{$t('support_ticket.add_attachment')}</label>
          <input id="support-ticket-reply-file-input" type="file" multiple onchange={onSelectReplyFiles} />
          <button type="button" class="primary" onclick={sendReply} disabled={actionLoading}>
            {#if actionLoading}
              {$t('loading')}...
            {:else}
              {$t('support_ticket.send_reply')}
            {/if}
          </button>
        </div>

        {#if replyAttachments.length > 0}
          <ul class="support-ticket-detail__reply-attachments">
            {#each replyAttachments as file, index}
              <li>
                <span>{file.name}</span>
                <button type="button" onclick={() => removeReplyAttachment(index)}>×</button>
              </li>
            {/each}
          </ul>
        {/if}
      </section>
    {/if}
  {/if}
</section>

<style>
  .support-ticket-detail {
    display: grid;
    gap: 1rem;
    padding-block: 1.25rem 2rem;
  }

  .support-ticket-detail__back-row button {
    border: 1px solid var(--immich-border-subtle, #d1d5db);
    border-radius: 999px;
    background: transparent;
    color: inherit;
    padding: 0.3rem 0.75rem;
    cursor: pointer;
  }

  .support-ticket-detail__header-card,
  .support-ticket-detail__messages-card,
  .support-ticket-detail__reply-card {
    border: 1px solid var(--immich-border-subtle, #e2e8f0);
    border-radius: 1rem;
    padding: 1rem;
    background: var(--immich-bg-subtle, #fff);
  }

  .support-ticket-detail__header-row {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 0.8rem;
  }

  .support-ticket-detail__header-row h1 {
    margin: 0;
    font-size: 1.35rem;
  }

  .support-ticket-detail__meta {
    margin-top: 0.5rem;
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem;
  }

  .support-ticket-detail__meta span {
    border-radius: 999px;
    background: var(--immich-bg-muted, #f3f4f6);
    font-size: 0.74rem;
    padding: 0.2rem 0.55rem;
  }

  .support-ticket-detail__updated-row {
    margin-top: 0.7rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 0.7rem;
  }

  .support-ticket-detail__updated-row small {
    color: var(--immich-fg-subtle, #6b7280);
  }

  .support-ticket-detail__updated-row button {
    border: 1px solid var(--immich-border-subtle, #d1d5db);
    border-radius: 999px;
    background: transparent;
    color: inherit;
    padding: 0.35rem 0.8rem;
    cursor: pointer;
  }

  .support-ticket-detail__updated-row button:disabled {
    cursor: not-allowed;
    opacity: 0.65;
  }

  .support-ticket-detail__messages-card ul {
    margin: 0;
    padding: 0;
    list-style: none;
    display: grid;
    gap: 0.8rem;
  }

  .support-ticket-detail__messages-card li {
    border: 1px solid var(--immich-border-subtle, #e5e7eb);
    border-radius: 0.75rem;
    padding: 0.7rem;
    background: var(--immich-bg-muted, #f8fafc);
  }

  .support-ticket-detail__messages-card li.item--user {
    background: #dbeafe;
  }

  .message-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 0.5rem;
  }

  .message-head small {
    color: var(--immich-fg-subtle, #6b7280);
  }

  .support-ticket-detail__messages-card p {
    margin: 0.45rem 0 0;
    white-space: pre-wrap;
  }

  .message-attachments {
    margin: 0.6rem 0 0;
    padding: 0;
    list-style: none;
    display: grid;
    gap: 0.3rem;
  }

  .message-attachments li {
    border: 0;
    background: transparent;
    padding: 0;
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 0.82rem;
  }

  .support-ticket-detail__reply-card {
    display: grid;
    gap: 0.75rem;
  }

  .support-ticket-detail__reply-card label {
    display: grid;
    gap: 0.35rem;
    font-size: 0.85rem;
  }

  .support-ticket-detail__reply-card textarea {
    border: 1px solid var(--immich-border-subtle, #d1d5db);
    border-radius: 0.7rem;
    background: transparent;
    color: inherit;
    padding: 0.6rem 0.7rem;
    font: inherit;
    resize: vertical;
  }

  .support-ticket-detail__reply-actions {
    display: flex;
    align-items: center;
    gap: 0.7rem;
  }

  .support-ticket-detail__reply-actions input[type='file'] {
    display: none;
  }

  .support-ticket-detail__reply-actions .attach {
    border: 1px solid var(--immich-border-subtle, #d1d5db);
    border-radius: 999px;
    padding: 0.35rem 0.75rem;
    cursor: pointer;
  }

  .support-ticket-detail__reply-actions .primary {
    margin-inline-start: auto;
    border: 0;
    border-radius: 999px;
    background: var(--immich-primary, #2563eb);
    color: #fff;
    padding: 0.42rem 0.95rem;
    cursor: pointer;
  }

  .support-ticket-detail__reply-actions .primary:disabled {
    cursor: not-allowed;
    opacity: 0.65;
  }

  .support-ticket-detail__reply-attachments {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 0.35rem;
  }

  .support-ticket-detail__reply-attachments li {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border: 1px solid var(--immich-border-subtle, #e5e7eb);
    border-radius: 0.55rem;
    padding: 0.35rem 0.55rem;
  }

  .support-ticket-detail__reply-attachments button {
    border: 0;
    background: transparent;
    color: inherit;
    cursor: pointer;
    font-size: 1rem;
  }

  .support-ticket-detail__state {
    border: 1px dashed var(--immich-border-subtle, #d1d5db);
    border-radius: 0.75rem;
    padding: 1rem;
    color: var(--immich-fg-subtle, #6b7280);
  }

  .support-ticket-detail__state button {
    margin-top: 0.5rem;
    border: 1px solid var(--immich-border-subtle, #d1d5db);
    border-radius: 999px;
    background: transparent;
    color: inherit;
    padding: 0.35rem 0.75rem;
    cursor: pointer;
  }

  .status {
    border-radius: 999px;
    padding: 0.2rem 0.55rem;
    font-size: 0.72rem;
    white-space: nowrap;
    font-weight: 600;
  }

  .status--open {
    background: #dbeafe;
    color: #1d4ed8;
  }

  .status--in_progress {
    background: #dbeafe;
    color: #1e40af;
  }

  .status--waiting_user {
    background: #fef3c7;
    color: #92400e;
  }

  .status--resolved {
    background: #dcfce7;
    color: #166534;
  }

  .status--closed {
    background: #e5e7eb;
    color: #374151;
  }
</style>
