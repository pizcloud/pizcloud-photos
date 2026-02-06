import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { User } from 'src/database';
import { UserResponseDto, mapUser } from 'src/dtos/user.dto';
import { AlbumTransferStatus } from 'src/enum';
import { ValidateUUID } from 'src/validation';

export class AlbumTransferRequestDto {
  @ValidateUUID()
  toUserId!: string;
}

export class AlbumTransferResponseDto {
  id!: string;
  albumId!: string;
  albumName!: string;
  fromUserId!: string;
  toUserId!: string;

  createdAt!: Date;
  updatedAt!: Date;
  respondedAt?: Date | null;

  @ApiProperty({ enum: AlbumTransferStatus })
  status!: AlbumTransferStatus;

  @Type(() => UserResponseDto)
  fromUser!: UserResponseDto;

  @Type(() => UserResponseDto)
  toUser!: UserResponseDto;

  @ApiProperty({ type: 'integer' })
  assetCount!: number;

  @ApiProperty({ type: 'integer' })
  totalBytes!: number;
}

export type MapAlbumTransferDto = {
  id: string;
  albumId: string;
  albumName: string;
  fromUserId: string;
  toUserId: string;
  respondedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  status: AlbumTransferStatus;
  fromUser: User;
  toUser: User;
  assetCount: number;
  totalBytes: number;
};

export const mapAlbumTransfer = (entity: MapAlbumTransferDto): AlbumTransferResponseDto => ({
  id: entity.id,
  albumId: entity.albumId,
  albumName: entity.albumName,
  fromUserId: entity.fromUserId,
  toUserId: entity.toUserId,
  respondedAt: entity.respondedAt,
  createdAt: entity.createdAt,
  updatedAt: entity.updatedAt,
  status: entity.status,
  fromUser: mapUser(entity.fromUser),
  toUser: mapUser(entity.toUser),
  assetCount: entity.assetCount,
  totalBytes: entity.totalBytes,
});
