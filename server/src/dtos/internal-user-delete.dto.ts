import { ApiProperty } from '@nestjs/swagger';
import { UserStatus } from 'src/enum';
import { ValidateDate, ValidateEnum, ValidateString, ValidateUUID } from 'src/validation';

export class InternalUserSelfDeleteRequestDto {
  @ValidateUUID({ description: 'Idempotency and trace id from account-server' })
  requestId!: string;

  @ValidateString({ description: 'Stable cross-service user identifier (mapped to photos user.oauthId)' })
  oauthId!: string;

  @ValidateString({ optional: true, nullable: true, description: 'Deletion reason for audit' })
  reason?: string | null;

  @ValidateDate({ optional: true, nullable: true, format: 'date-time', description: 'Request time from account-server' })
  requestedAt?: Date | null;
}

export enum InternalUserSelfDeleteResult {
  Deleted = 'deleted',
  AlreadyDeleted = 'already_deleted',
}

export class InternalUserSelfDeleteUserDto {
  @ApiProperty({ format: 'uuid' })
  id!: string;

  @ApiProperty()
  oauthId!: string;

  @ValidateEnum({ enum: UserStatus, name: 'UserStatus' })
  status!: UserStatus;

  @ApiProperty({ format: 'date-time', nullable: true })
  deletedAt!: Date | null;
}

export class InternalUserSelfDeleteResponseDto {
  @ApiProperty({ example: true })
  ok!: true;

  @ValidateUUID({ description: 'Echo of request id' })
  requestId!: string;

  @ValidateEnum({ enum: InternalUserSelfDeleteResult, name: 'InternalUserSelfDeleteResult' })
  result!: InternalUserSelfDeleteResult;

  @ApiProperty({ type: InternalUserSelfDeleteUserDto })
  user!: InternalUserSelfDeleteUserDto;
}
