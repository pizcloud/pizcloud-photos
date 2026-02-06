import { Kysely, sql } from 'kysely';

export async function up(db: Kysely<any>): Promise<void> {
  await sql`CREATE TYPE "album_transfer_status_enum" AS ENUM ('pending', 'accepted', 'declined', 'canceled');`.execute(
    db,
  );

  await sql`CREATE TABLE "album_transfer" (
  "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
  "albumId" uuid NOT NULL,
  "fromUserId" uuid NOT NULL,
  "toUserId" uuid NOT NULL,
  "status" album_transfer_status_enum NOT NULL DEFAULT 'pending',
  "createdAt" timestamp with time zone NOT NULL DEFAULT now(),
  "updatedAt" timestamp with time zone NOT NULL DEFAULT now(),
  "respondedAt" timestamp with time zone,
  "updateId" uuid NOT NULL DEFAULT immich_uuid_v7(),
  CONSTRAINT "album_transfer_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "album_transfer_albumId_fkey" FOREIGN KEY ("albumId") REFERENCES "album" ("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "album_transfer_fromUserId_fkey" FOREIGN KEY ("fromUserId") REFERENCES "user" ("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "album_transfer_toUserId_fkey" FOREIGN KEY ("toUserId") REFERENCES "user" ("id") ON UPDATE CASCADE ON DELETE CASCADE
);`.execute(db);

  await sql`CREATE UNIQUE INDEX "album_transfer_albumId_pending_idx" ON "album_transfer" ("albumId") WHERE ("status" = 'pending');`.execute(
    db,
  );
  await sql`CREATE INDEX "album_transfer_toUserId_status_idx" ON "album_transfer" ("toUserId", "status");`.execute(
    db,
  );

  await sql`CREATE OR REPLACE TRIGGER "album_transfer_updatedAt"
  BEFORE UPDATE ON "album_transfer"
  FOR EACH ROW
  EXECUTE FUNCTION updated_at();`.execute(db);
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`DROP TRIGGER IF EXISTS "album_transfer_updatedAt" ON "album_transfer";`.execute(db);
  await sql`DROP TABLE "album_transfer";`.execute(db);
  await sql`DROP TYPE "album_transfer_status_enum";`.execute(db);
}
