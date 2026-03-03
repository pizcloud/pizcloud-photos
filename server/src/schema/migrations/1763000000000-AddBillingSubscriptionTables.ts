import { Kysely, sql } from 'kysely';

export async function up(db: Kysely<any>): Promise<void> {
  await sql`
    CREATE TABLE "billing_subscription_state" (
      "userId" uuid NOT NULL,
      "userEmail" character varying NOT NULL,
      "platform" character varying NOT NULL DEFAULT 'unknown',
      "productId" character varying NOT NULL,
      "planCode" character varying NOT NULL,
      "storageLimitGb" integer NOT NULL,
      "mlTier" character varying,
      "seats" integer,
      "shareEnabled" boolean,
      "period" character varying,
      "purchaseToken" character varying,
      "expiresAtMs" bigint,
      "status" character varying NOT NULL,
      "cancelAtPeriodEnd" boolean NOT NULL DEFAULT false,
      "lastEventTimeMs" bigint NOT NULL,
      "lastEventId" character varying,
      "effectiveQuotaBytes" bigint,
      "createdAt" timestamp with time zone NOT NULL DEFAULT now(),
      "updatedAt" timestamp with time zone NOT NULL DEFAULT now(),
      "updateId" uuid NOT NULL DEFAULT immich_uuid_v7(),
      CONSTRAINT "billing_subscription_state_pkey" PRIMARY KEY ("userId"),
      CONSTRAINT "billing_subscription_state_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "user" ("id") ON UPDATE CASCADE ON DELETE CASCADE
    );
  `.execute(db);

  await sql`
    CREATE UNIQUE INDEX "billing_subscription_state_purchaseToken_uidx"
      ON "billing_subscription_state" ("purchaseToken")
      WHERE ("purchaseToken" IS NOT NULL);
  `.execute(db);
  await sql`
    CREATE INDEX "billing_subscription_state_status_expiresAtMs_idx"
      ON "billing_subscription_state" ("status", "expiresAtMs");
  `.execute(db);
  await sql`
    CREATE INDEX "billing_subscription_state_expiresAtMs_idx"
      ON "billing_subscription_state" ("expiresAtMs");
  `.execute(db);
  await sql`
    CREATE INDEX "billing_subscription_state_updateId_idx"
      ON "billing_subscription_state" ("updateId");
  `.execute(db);

  await sql`
    CREATE OR REPLACE TRIGGER "billing_subscription_state_updatedAt"
    BEFORE UPDATE ON "billing_subscription_state"
    FOR EACH ROW
    EXECUTE FUNCTION updated_at();
  `.execute(db);

  await sql`
    CREATE TABLE "billing_subscription_event" (
      "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
      "userId" uuid NOT NULL,
      "providerEventId" character varying NOT NULL,
      "platform" character varying NOT NULL DEFAULT 'unknown',
      "eventType" character varying NOT NULL,
      "eventTimeMs" bigint NOT NULL,
      "payload" jsonb NOT NULL,
      "processResult" character varying,
      "createdAt" timestamp with time zone NOT NULL DEFAULT now(),
      "updatedAt" timestamp with time zone NOT NULL DEFAULT now(),
      "updateId" uuid NOT NULL DEFAULT immich_uuid_v7(),
      CONSTRAINT "billing_subscription_event_pkey" PRIMARY KEY ("id"),
      CONSTRAINT "billing_subscription_event_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "user" ("id") ON UPDATE CASCADE ON DELETE CASCADE
    );
  `.execute(db);

  await sql`
    CREATE UNIQUE INDEX "billing_subscription_event_providerEventId_uidx"
      ON "billing_subscription_event" ("providerEventId");
  `.execute(db);
  await sql`
    CREATE INDEX "billing_subscription_event_userId_eventTimeMs_idx"
      ON "billing_subscription_event" ("userId", "eventTimeMs");
  `.execute(db);
  await sql`
    CREATE INDEX "billing_subscription_event_updateId_idx"
      ON "billing_subscription_event" ("updateId");
  `.execute(db);

  await sql`
    CREATE OR REPLACE TRIGGER "billing_subscription_event_updatedAt"
    BEFORE UPDATE ON "billing_subscription_event"
    FOR EACH ROW
    EXECUTE FUNCTION updated_at();
  `.execute(db);
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`DROP TRIGGER IF EXISTS "billing_subscription_event_updatedAt" ON "billing_subscription_event";`.execute(db);
  await sql`DROP TABLE IF EXISTS "billing_subscription_event";`.execute(db);

  await sql`DROP TRIGGER IF EXISTS "billing_subscription_state_updatedAt" ON "billing_subscription_state";`.execute(db);
  await sql`DROP TABLE IF EXISTS "billing_subscription_state";`.execute(db);
}
