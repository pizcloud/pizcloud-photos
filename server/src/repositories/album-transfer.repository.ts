import { Injectable } from '@nestjs/common';
import { ExpressionBuilder, Insertable, Kysely, NotNull, Selectable, sql, Updateable } from 'kysely';
import { jsonObjectFrom } from 'kysely/helpers/postgres';
import { InjectKysely } from 'nestjs-kysely';
import { columns, User } from 'src/database';
import { DummyValue, GenerateSql } from 'src/decorators';
import { AlbumTransferStatus, AlbumUserRole } from 'src/enum';
import { DB } from 'src/schema';
import { AlbumTransferTable } from 'src/schema/tables/album-transfer.table';

export type AlbumTransferEntity = Selectable<AlbumTransferTable> & {
  albumName: string;
  fromUser: User;
  toUser: User;
};

const withFromUser = (eb: ExpressionBuilder<DB, 'album_transfer'>) => {
  return jsonObjectFrom(
    eb
      .selectFrom('user as fromUser')
      .select(columns.user)
      .whereRef('fromUser.id', '=', 'album_transfer.fromUserId')
      .where('fromUser.deletedAt', 'is', null),
  ).as('fromUser');
};

const withToUser = (eb: ExpressionBuilder<DB, 'album_transfer'>) => {
  return jsonObjectFrom(
    eb
      .selectFrom('user as toUser')
      .select(columns.user)
      .whereRef('toUser.id', '=', 'album_transfer.toUserId')
      .where('toUser.deletedAt', 'is', null),
  ).as('toUser');
};

@Injectable()
export class AlbumTransferRepository {
  constructor(@InjectKysely() private db: Kysely<DB>) {}

  @GenerateSql({ params: [DummyValue.UUID] })
  getById(id: string): Promise<AlbumTransferEntity | undefined> {
    return this.builder().where('album_transfer.id', '=', id).executeTakeFirst();
  }

  @GenerateSql({ params: [DummyValue.UUID] })
  getPendingByAlbumId(albumId: string): Promise<AlbumTransferEntity | undefined> {
    return this.builder()
      .where('album_transfer.albumId', '=', albumId)
      .where('album_transfer.status', '=', AlbumTransferStatus.Pending)
      .executeTakeFirst();
  }

  @GenerateSql({ params: [DummyValue.UUID] })
  getIncoming(userId: string): Promise<AlbumTransferEntity[]> {
    return this.builder()
      .where('album_transfer.toUserId', '=', userId)
      .where('album_transfer.status', '=', AlbumTransferStatus.Pending)
      .orderBy('album_transfer.createdAt', 'desc')
      .execute();
  }

  create(values: Insertable<AlbumTransferTable>): Promise<AlbumTransferEntity> {
    return this.db.transaction().execute(async (tx) => {
      const created = await tx.insertInto('album_transfer').values(values).returning('id').executeTakeFirstOrThrow();
      return this.builder(tx).where('album_transfer.id', '=', created.id).executeTakeFirstOrThrow();
    });
  }

  async updateStatus(id: string, values: Updateable<AlbumTransferTable>): Promise<AlbumTransferEntity | undefined> {
    await this.db.updateTable('album_transfer').set(values).where('id', '=', id).execute();
    return this.getById(id);
  }

  @GenerateSql({ params: [DummyValue.UUID, DummyValue.UUID, DummyValue.UUID] })
  async hasOwnershipTransferConflict(albumId: string, fromUserId: string, toUserId: string): Promise<boolean> {
    const conflict = await this.db
      .selectFrom('asset as source')
      .innerJoin('album_asset', 'album_asset.assetId', 'source.id')
      .innerJoin(
        'asset as target',
        (join) =>
          join
            .on('target.ownerId', '=', toUserId)
            .onRef('target.checksum', '=', 'source.checksum')
            .on((eb) =>
              eb.or([
                eb.and([eb('source.libraryId', 'is', null), eb('target.libraryId', 'is', null)]),
                eb.and([
                  eb('source.libraryId', 'is not', null),
                  eb('target.libraryId', '=', eb.ref('source.libraryId')),
                ]),
              ]),
            ),
      )
      .select('source.id')
      .where('album_asset.albumId', '=', albumId)
      .where('source.ownerId', '=', fromUserId)
      .limit(1)
      .executeTakeFirst();

    return !!conflict;
  }

  async applyTransfer(options: {
    transferId: string;
    albumId: string;
    fromUserId: string;
    toUserId: string;
    movedBytes: number;
  }): Promise<void> {
    const { transferId, albumId, fromUserId, toUserId, movedBytes } = options;

    await this.db.transaction().execute(async (tx) => {
      const updated = await tx
        .updateTable('album_transfer')
        .set({ status: AlbumTransferStatus.Accepted, respondedAt: new Date() })
        .where('id', '=', transferId)
        .where('status', '=', AlbumTransferStatus.Pending)
        .executeTakeFirst();

      if (Number(updated.numUpdatedRows) === 0) {
        throw new Error('Transfer is no longer pending');
      }

      await tx.updateTable('album').set({ ownerId: toUserId }).where('id', '=', albumId).execute();

      await tx.deleteFrom('album_user').where('albumId', '=', albumId).where('userId', '=', toUserId).execute();

      const existingOldOwner = await tx
        .selectFrom('album_user')
        .select('userId')
        .where('albumId', '=', albumId)
        .where('userId', '=', fromUserId)
        .executeTakeFirst();

      if (existingOldOwner) {
        await tx
          .updateTable('album_user')
          .set({ role: AlbumUserRole.Editor })
          .where('albumId', '=', albumId)
          .where('userId', '=', fromUserId)
          .execute();
      } else {
        await tx
          .insertInto('album_user')
          .values({ albumId, userId: fromUserId, role: AlbumUserRole.Editor })
          .execute();
      }

      const movedAssetsQuery = tx
        .selectFrom('album_asset')
        .innerJoin('asset', 'asset.id', 'album_asset.assetId')
        .select('asset.id')
        .where('album_asset.albumId', '=', albumId)
        .where('asset.ownerId', '=', fromUserId);

      // Clear user-scoped metadata before changing ownership to avoid cross-user leaks.
      await tx.deleteFrom('tag_asset').where('assetId', 'in', movedAssetsQuery).execute();
      await tx.updateTable('asset_face').set({ personId: null }).where('assetId', 'in', movedAssetsQuery).execute();

      await tx
        .updateTable('asset')
        .set({ ownerId: toUserId })
        .where('id', 'in', movedAssetsQuery)
        .execute();

      // pizcloud - Bump album asset updateId so the new owner receives album-to-asset links in incremental sync.
      await tx
        .updateTable('album_asset')
        .set({ updatedAt: new Date() })
        .where('albumId', '=', albumId)
        .execute();
      // #pizcloud

      if (movedBytes !== 0) {
        await tx
          .updateTable('user')
          .set({
            quotaUsageInBytes: sql`"quotaUsageInBytes" - ${movedBytes}`,
            updatedAt: new Date(),
          })
          .where('id', '=', fromUserId)
          .execute();

        await tx
          .updateTable('user')
          .set({
            quotaUsageInBytes: sql`"quotaUsageInBytes" + ${movedBytes}`,
            updatedAt: new Date(),
          })
          .where('id', '=', toUserId)
          .execute();
      }
    });
  }

  private builder(db: Kysely<DB> = this.db) {
    return db
      .selectFrom('album_transfer')
      .innerJoin('album', 'album.id', 'album_transfer.albumId')
      .selectAll('album_transfer')
      .select('album.albumName as albumName')
      .select(withFromUser)
      .select(withToUser)
      .$narrowType<{ fromUser: NotNull; toUser: NotNull }>();
  }
}
