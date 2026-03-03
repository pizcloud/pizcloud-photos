import { UpdatedAtTrigger, UpdateIdColumn } from 'src/decorators';
import { UserTable } from 'src/schema/tables/user.table';
import {
  Column,
  CreateDateColumn,
  ForeignKeyColumn,
  Generated,
  Index,
  PrimaryGeneratedColumn,
  Table,
  Timestamp,
  UpdateDateColumn,
} from 'src/sql-tools';

@Table('billing_subscription_event')
@UpdatedAtTrigger('billing_subscription_event_updatedAt')
@Index({ columns: ['providerEventId'], unique: true })
@Index({ columns: ['userId', 'eventTimeMs'] })
export class BillingSubscriptionEventTable {
  @PrimaryGeneratedColumn('uuid')
  id!: Generated<string>;

  @ForeignKeyColumn(() => UserTable, {
    onDelete: 'CASCADE',
    onUpdate: 'CASCADE',
  })
  userId!: string;

  @Column({ type: 'character varying' })
  providerEventId!: string;

  @Column({ type: 'character varying', default: 'unknown' })
  platform!: Generated<string>;

  @Column({ type: 'character varying' })
  eventType!: string;

  @Column({ type: 'bigint' })
  eventTimeMs!: number;

  @Column({ type: 'jsonb' })
  payload!: Record<string, unknown>;

  @Column({ type: 'character varying', nullable: true })
  processResult!: string | null;

  @CreateDateColumn()
  createdAt!: Generated<Timestamp>;

  @UpdateDateColumn()
  updatedAt!: Generated<Timestamp>;

  @UpdateIdColumn({ index: true })
  updateId!: Generated<string>;
}
