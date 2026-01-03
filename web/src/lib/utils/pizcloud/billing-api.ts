import { PUBLIC_PIZCLOUD_SERVER_URL } from '$env/static/public';
import type { BankCode, BillingOrder, BillingOrderStatus, BillingProduct } from '$lib/types/pizcloud/billing';

const baseUrl = (PUBLIC_PIZCLOUD_SERVER_URL || '').replace(/\/+$/, '');

type ApiError = { message?: string; error?: string; statusCode?: number };

async function readError(res: Response): Promise<string> {
  const contentType = res.headers.get('content-type') || '';
  try {
    if (contentType.includes('application/json')) {
      const data = (await res.json()) as ApiError;
      return data.message || data.error || `HTTP ${res.status}`;
    }
    const text = await res.text();
    return text || `HTTP ${res.status}`;
  } catch {
    return `HTTP ${res.status}`;
  }
}

// =========================
// normalize product price
// =========================
function normalizeProduct(p: BillingProduct): BillingProduct {
  if (typeof (p as any).priceVnd === 'number') return p;
  return { ...p, priceVnd: p.priceUsd };
}

export async function getBillingProducts(fetchFn: typeof fetch): Promise<BillingProduct[]> {
  const res = await fetchFn(`${baseUrl}/billing/products`, { credentials: 'include' });
  if (!res.ok) throw new Error(await readError(res));
  const data = (await res.json()) as BillingProduct[];
  return data.map(normalizeProduct);
}

export async function createBankTransferOrder(
  fetchFn: typeof fetch,
  input: { productId: string; bankCode: BankCode },
): Promise<BillingOrder> {
  const res = await fetchFn(`${baseUrl}/billing/orders`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ productId: input.productId, paymentMethod: 'BANK_TRANSFER', bankCode: input.bankCode }),
  });

  if (!res.ok) throw new Error(await readError(res));
  return (await res.json()) as BillingOrder;
}

export async function getBillingOrder(fetchFn: typeof fetch, orderId: string): Promise<BillingOrder> {
  const res = await fetchFn(`${baseUrl}/billing/orders/${orderId}`, { credentials: 'include' });
  if (!res.ok) throw new Error(await readError(res));
  return (await res.json()) as BillingOrder;
}

// =========================
// list order history
// GET /billing/orders?limit=20&status=PENDING
// =========================
export async function listBillingOrders(
  fetchFn: typeof fetch,
  input?: { limit?: number; status?: BillingOrderStatus },
): Promise<BillingOrder[]> {
  const qs = new URLSearchParams();
  if (input?.limit) qs.set('limit', String(input.limit));
  if (input?.status) qs.set('status', input.status);

  const url = qs.toString() ? `${baseUrl}/billing/orders?${qs.toString()}` : `${baseUrl}/billing/orders`;

  const res = await fetchFn(url, { credentials: 'include' });
  if (!res.ok) throw new Error(await readError(res));
  return (await res.json()) as BillingOrder[];
}

// =========================
// cancel pending order
// POST /billing/orders/:id/cancel
// =========================
export async function cancelBillingOrder(fetchFn: typeof fetch, orderId: string): Promise<BillingOrder> {
  const res = await fetchFn(`${baseUrl}/billing/orders/${orderId}/cancel`, {
    method: 'POST',
    credentials: 'include',
  });

  if (!res.ok) throw new Error(await readError(res));
  return (await res.json()) as BillingOrder;
}