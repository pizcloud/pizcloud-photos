import { UpdatedAtTrigger, UpdateIdColumn } from 'src/decorators';
import { UserTable } from 'src/schema/tables/user.table';
import {
  Column,
  CreateDateColumn,
  ForeignKeyColumn,
  Generated,
  Index,
  Table,
  Timestamp,
  UpdateDateColumn,
} from 'src/sql-tools';

@Table('billing_subscription_state')
@UpdatedAtTrigger('billing_subscription_state_updatedAt')
@Index({ columns: ['userId'], unique: true })
@Index({ columns: ['status', 'expiresAtMs'] })
@Index({ columns: ['expiresAtMs'] })
@Index({ columns: ['purchaseToken'], unique: true, where: '("purchaseToken" IS NOT NULL)' })
export class BillingSubscriptionStateTable {
  @ForeignKeyColumn(() => UserTable, {
    onDelete: 'CASCADE',
    onUpdate: 'CASCADE',
    primary: true,
    index: false,
  })
  userId!: string;

  @Column({ type: 'character varying' })
  userEmail!: string;

  @Column({ type: 'character varying', default: 'unknown' })
  platform!: Generated<string>;

  @Column({ type: 'character varying' })
  productId!: string;

  @Column({ type: 'character varying' })
  planCode!: string;

  @Column({ type: 'integer' })
  storageLimitGb!: number;

  @Column({ type: 'character varying', nullable: true })
  mlTier!: string | null;

  @Column({ type: 'integer', nullable: true })
  seats!: number | null;

  @Column({ type: 'boolean', nullable: true })
  shareEnabled!: boolean | null;

  @Column({ type: 'character varying', nullable: true })
  period!: string | null;

  @Column({ type: 'character varying', nullable: true })
  purchaseToken!: string | null;

  @Column({ type: 'bigint', nullable: true })
  expiresAtMs!: number | null;

  @Column({ type: 'character varying' })
  status!: string;

  @Column({ type: 'boolean', default: false })
  cancelAtPeriodEnd!: Generated<boolean>;

  @Column({ type: 'bigint' })
  lastEventTimeMs!: number;

  @Column({ type: 'character varying', nullable: true })
  lastEventId!: string | null;

  @Column({ type: 'bigint', nullable: true })
  effectiveQuotaBytes!: number | null;

  @CreateDateColumn()
  createdAt!: Generated<Timestamp>;

  @UpdateDateColumn()
  updatedAt!: Generated<Timestamp>;

  @UpdateIdColumn({ index: true })
  updateId!: Generated<string>;
}
