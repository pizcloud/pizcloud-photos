import { UpdatedAtTrigger, UpdateIdColumn } from 'src/decorators';
import { AlbumTransferStatus } from 'src/enum';
import { album_transfer_status_enum } from 'src/schema/enums';
import { AlbumTable } from 'src/schema/tables/album.table';
import { UserTable } from 'src/schema/tables/user.table';
import {
  Column,
  CreateDateColumn,
  ForeignKeyColumn,
  Index,
  PrimaryGeneratedColumn,
  Table,
  Timestamp,
  UpdateDateColumn,
} from 'src/sql-tools';

@Table('album_transfer')
@UpdatedAtTrigger('album_transfer_updatedAt')
@Index({ columns: ['albumId'], unique: true, where: "(\"status\" = 'pending')" })
@Index({ columns: ['toUserId', 'status'] })
export class AlbumTransferTable {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @ForeignKeyColumn(() => AlbumTable, { onDelete: 'CASCADE', onUpdate: 'CASCADE' })
  albumId!: string;

  @ForeignKeyColumn(() => UserTable, { onDelete: 'CASCADE', onUpdate: 'CASCADE' })
  fromUserId!: string;

  @ForeignKeyColumn(() => UserTable, { onDelete: 'CASCADE', onUpdate: 'CASCADE' })
  toUserId!: string;

  @Column({ enum: album_transfer_status_enum, default: AlbumTransferStatus.Pending })
  status!: AlbumTransferStatus;

  @CreateDateColumn()
  createdAt!: Timestamp;

  @UpdateDateColumn()
  updatedAt!: Timestamp;

  @Column({ type: 'timestamp with time zone', nullable: true })
  respondedAt!: Timestamp | null;

  @UpdateIdColumn({ index: true })
  updateId!: string;
}
