import { Injectable } from '@nestjs/common';
import { Insertable, Kysely, Selectable, Updateable } from 'kysely';
import { InjectKysely } from 'nestjs-kysely';
import { DB } from 'src/schema';
import { BillingSubscriptionEventTable } from 'src/schema/tables/billing-subscription-event.table';
import { BillingSubscriptionStateTable } from 'src/schema/tables/billing-subscription-state.table';

export type BillingSubscriptionStateRecord = Selectable<BillingSubscriptionStateTable>;
export type BillingSubscriptionEventRecord = Selectable<BillingSubscriptionEventTable>;

@Injectable()
export class BillingSubscriptionRepository {
  constructor(@InjectKysely() private db: Kysely<DB>) {}

  getStateByUserId(userId: string): Promise<BillingSubscriptionStateRecord | undefined> {
    return this.db.selectFrom('billing_subscription_state').selectAll().where('userId', '=', userId).executeTakeFirst();
  }

  async upsertState(
    state: Insertable<BillingSubscriptionStateTable>,
  ): Promise<BillingSubscriptionStateRecord | undefined> {
    const { userId, ...rest } = state;
    await this.db
      .insertInto('billing_subscription_state')
      .values(state)
      .onConflict((oc) => oc.column('userId').doUpdateSet(rest))
      .execute();

    return this.getStateByUserId(userId);
  }

  async updateState(
    userId: string,
    patch: Updateable<BillingSubscriptionStateTable>,
  ): Promise<BillingSubscriptionStateRecord | undefined> {
    await this.db.updateTable('billing_subscription_state').set(patch).where('userId', '=', userId).execute();
    return this.getStateByUserId(userId);
  }

  async insertEventIfNotExists(event: Insertable<BillingSubscriptionEventTable>): Promise<boolean> {
    const inserted = await this.db
      .insertInto('billing_subscription_event')
      .values(event)
      .onConflict((oc) => oc.column('providerEventId').doNothing())
      .returning('id')
      .executeTakeFirst();

    return !!inserted;
  }

  async updateEventProcessResult(providerEventId: string, processResult: string): Promise<void> {
    await this.db
      .updateTable('billing_subscription_event')
      .set({ processResult })
      .where('providerEventId', '=', providerEventId)
      .execute();
  }

  findStatesDueForExpiry(nowMs: number, limit = 200): Promise<BillingSubscriptionStateRecord[]> {
    return this.db
      .selectFrom('billing_subscription_state')
      .selectAll()
      .where('cancelAtPeriodEnd', '=', true)
      .where('expiresAtMs', 'is not', null)
      .where('expiresAtMs', '<=', nowMs)
      .where('status', 'in', ['active', 'canceled', 'grace_period', 'on_hold'])
      .orderBy('expiresAtMs', 'asc')
      .limit(limit)
      .execute();
  }
}
