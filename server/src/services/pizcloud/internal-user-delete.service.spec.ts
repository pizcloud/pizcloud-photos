import { ConflictException, NotFoundException } from '@nestjs/common';
import { InternalUserSelfDeleteResult } from 'src/dtos/internal-user-delete.dto';
import { UserStatus } from 'src/enum';
import { InternalUserDeleteService } from 'src/services/pizcloud/internal-user-delete.service';
import { factory } from 'test/small.factory';
import { newTestService, ServiceMocks } from 'test/utils';
import { describe, expect } from 'vitest';

describe(InternalUserDeleteService.name, () => {
  let sut: InternalUserDeleteService;
  let mocks: ServiceMocks;

  const activeUser = factory.userAdmin({
    id: 'active-user-id',
    oauthId: 'oauth-active-user',
    email: 'active@example.com',
    isAdmin: false,
    status: UserStatus.Active,
    deletedAt: null,
  });

  const deletedUser = factory.userAdmin({
    id: 'deleted-user-id',
    oauthId: 'oauth-deleted-user',
    email: 'deleted@example.com',
    isAdmin: false,
    status: UserStatus.Deleted,
    deletedAt: new Date('2026-05-10T03:30:00.000Z'),
  });

  const adminUser = factory.userAdmin({
    id: 'admin-user-id',
    oauthId: 'oauth-admin-user',
    email: 'admin@example.com',
    isAdmin: true,
    status: UserStatus.Active,
    deletedAt: null,
  });

  beforeEach(() => {
    ({ sut, mocks } = newTestService(InternalUserDeleteService));

    mocks.user.getByOAuthIdWithDeleted.mockImplementation((oauthId: string) => {
      const map = new Map<string, typeof activeUser>([
        [activeUser.oauthId, activeUser],
        [deletedUser.oauthId, deletedUser],
        [adminUser.oauthId, adminUser],
      ]);
      return Promise.resolve(map.get(oauthId));
    });
  });

  it('should throw if user is missing', async () => {
    await expect(
      sut.selfDelete({
        requestId: factory.uuid(),
        oauthId: 'missing-oauth-id',
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('should reject admin self-delete requests', async () => {
    await expect(
      sut.selfDelete({
        requestId: factory.uuid(),
        oauthId: adminUser.oauthId,
      }),
    ).rejects.toBeInstanceOf(ConflictException);

    expect(mocks.album.softDeleteAll).not.toHaveBeenCalled();
    expect(mocks.user.update).not.toHaveBeenCalled();
  });

  it('should be idempotent for already-deleted users', async () => {
    const response = await sut.selfDelete({
      requestId: factory.uuid(),
      oauthId: deletedUser.oauthId,
    });

    expect(response.ok).toBe(true);
    expect(response.result).toBe(InternalUserSelfDeleteResult.AlreadyDeleted);
    expect(response.user.id).toBe(deletedUser.id);
    expect(response.user.deletedAt?.toISOString()).toBe(deletedUser.deletedAt?.toISOString());

    expect(mocks.album.softDeleteAll).not.toHaveBeenCalled();
    expect(mocks.user.update).not.toHaveBeenCalled();
    expect(mocks.event.emit).not.toHaveBeenCalled();
  });

  it('should soft-delete user and owned albums when active', async () => {
    const deletedAt = new Date('2026-05-11T01:00:00.000Z');
    const updatedUser = factory.userAdmin({
      ...activeUser,
      status: UserStatus.Deleted,
      deletedAt,
    });
    mocks.user.update.mockResolvedValue(updatedUser);

    const response = await sut.selfDelete({
      requestId: factory.uuid(),
      oauthId: activeUser.oauthId,
      reason: 'user_self_service',
      requestedAt: new Date('2026-05-11T00:59:59.000Z'),
    });

    expect(mocks.album.softDeleteAll).toHaveBeenCalledWith(activeUser.id);
    expect(mocks.user.update).toHaveBeenCalledWith(activeUser.id, {
      status: UserStatus.Deleted,
      deletedAt: expect.any(Date),
    });
    expect(mocks.event.emit).toHaveBeenCalledWith('UserTrash', updatedUser);

    expect(response.ok).toBe(true);
    expect(response.result).toBe(InternalUserSelfDeleteResult.Deleted);
    expect(response.user.id).toBe(activeUser.id);
    expect(response.user.status).toBe(UserStatus.Deleted);
  });
});
