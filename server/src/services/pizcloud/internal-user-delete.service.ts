import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import {
  InternalUserSelfDeleteRequestDto,
  InternalUserSelfDeleteResponseDto,
  InternalUserSelfDeleteResult,
} from 'src/dtos/internal-user-delete.dto';
import { UserStatus } from 'src/enum';
import { BaseService } from 'src/services/base.service';

@Injectable()
export class InternalUserDeleteService extends BaseService {
  async selfDelete(dto: InternalUserSelfDeleteRequestDto): Promise<InternalUserSelfDeleteResponseDto> {
    const user = await this.userRepository.getByOAuthIdWithDeleted(dto.oauthId);
    console.log('useruseruser', user);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (user.isAdmin) {
      throw new ConflictException('Cannot self-delete an admin account');
    }

    if (user.deletedAt) {
      this.logger.log(`Internal user self-delete already applied requestId=${dto.requestId}, userId=${user.id}`);
      return {
        ok: true,
        requestId: dto.requestId,
        result: InternalUserSelfDeleteResult.AlreadyDeleted,
        user: {
          id: user.id,
          oauthId: user.oauthId,
          status: user.status as UserStatus,
          deletedAt: user.deletedAt,
        },
      };
    }

    this.logger.log(`Internal user self-delete requestId=${dto.requestId}, userId=${user.id}`);

    await this.albumRepository.softDeleteAll(user.id);
    const updatedUser = await this.userRepository.update(user.id, {
      status: UserStatus.Deleted,
      deletedAt: new Date(),
    });

    await this.eventRepository.emit('UserTrash', updatedUser);

    return {
      ok: true,
      requestId: dto.requestId,
      result: InternalUserSelfDeleteResult.Deleted,
      user: {
        id: updatedUser.id,
        oauthId: updatedUser.oauthId,
        status: updatedUser.status as UserStatus,
        deletedAt: updatedUser.deletedAt,
      },
    };
  }
}
