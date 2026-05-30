import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { attachClientTelemetryHeaders, redactForTelemetry } from './client-telemetry';

const telemetryEnabledStorageKey = 'pizcloud.telemetry.enabled';

describe('client telemetry redaction', () => {
  it('redacts sensitive fields by key path', () => {
    const payload = redactForTelemetry({
      email: 'alice@example.com',
      purchaseToken: 'purchase-token-1234567890',
      orderId: 'order-id-1234567890',
      nested: {
        authorization: 'Bearer abcdefghijklmnopqrst',
      },
    }) as Record<string, unknown>;

    expect(payload.email).toBe('a***@example.com');
    expect(payload.purchaseToken).not.toBe('purchase-token-1234567890');
    expect(payload.orderId).not.toBe('order-id-1234567890');
    expect((payload.nested as Record<string, unknown>).authorization).toBe('Bea***st');
  });

  it('redacts email and bearer token in free-form strings', () => {
    const payload = redactForTelemetry({
      error:
        'failed for user bob@example.com with Bearer super-secret-token and jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signedpayload',
    }) as Record<string, unknown>;

    const error = payload.error as string;
    expect(error).not.toContain('bob@example.com');
    expect(error).toContain('b***@example.com');
    expect(error).not.toContain('super-secret-token');
    expect(error).toContain('Bearer ***');
    expect(error).not.toContain('eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signedpayload');
    expect(error).toContain('***.***.***');
  });
});

describe('client telemetry headers', () => {
  beforeEach(() => {
    globalThis.localStorage.clear();
    globalThis.sessionStorage.clear();
  });

  afterEach(() => {
    globalThis.localStorage.removeItem(telemetryEnabledStorageKey);
  });

  it('adds correlation headers and normalizes client event name', () => {
    const init = attachClientTelemetryHeaders({ headers: new Headers() }, 'support.ticket.reply invalid/name');
    const headers = new Headers(init?.headers);

    expect(headers.get('x-request-id')).toBeTruthy();
    expect(headers.get('x-correlation-id')).toBeTruthy();
    expect(headers.get('x-client-event-id')).toBeTruthy();
    expect(headers.get('x-client-session-id')).toBeTruthy();
    expect(headers.get('x-client-event-name')).toBe('support.ticket.reply_invalid_name');
  });

  it('does not override existing telemetry headers', () => {
    const existingHeaders = new Headers({
      'x-request-id': 'req_keep',
      'x-correlation-id': 'cid_keep',
      'x-client-event-id': 'evt_keep',
      'x-client-session-id': 'sid_keep',
      'x-client-event-name': 'existing.event',
    });

    const init = attachClientTelemetryHeaders({ headers: existingHeaders }, 'auth.login.submit');
    const headers = new Headers(init?.headers);

    expect(headers.get('x-request-id')).toBe('req_keep');
    expect(headers.get('x-correlation-id')).toBe('cid_keep');
    expect(headers.get('x-client-event-id')).toBe('evt_keep');
    expect(headers.get('x-client-session-id')).toBe('sid_keep');
    expect(headers.get('x-client-event-name')).toBe('existing.event');
  });

  it('skips telemetry headers when runtime override disables telemetry', () => {
    globalThis.localStorage.setItem(telemetryEnabledStorageKey, 'false');

    const init = attachClientTelemetryHeaders({ headers: { accept: 'application/json' } }, 'auth.login.submit');
    const headers = new Headers(init?.headers);

    expect(headers.get('accept')).toBe('application/json');
    expect(headers.has('x-request-id')).toBe(false);
    expect(headers.has('x-correlation-id')).toBe(false);
    expect(headers.has('x-client-event-id')).toBe(false);
    expect(headers.has('x-client-session-id')).toBe(false);
    expect(headers.has('x-client-event-name')).toBe(false);
  });
});
