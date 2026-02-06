import { Controller, Get, Param, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Endpoint, HistoryBuilder } from 'src/decorators';
import { AlbumTransferResponseDto } from 'src/dtos/album-transfer.dto';
import { AuthDto } from 'src/dtos/auth.dto';
import { ApiTag, Permission } from 'src/enum';
import { Auth, Authenticated } from 'src/middleware/auth.guard';
import { AlbumService } from 'src/services/album.service';
import { UUIDParamDto } from 'src/validation';

@ApiTags(ApiTag.Albums)
@Controller('album-transfers')
export class AlbumTransferController {
  constructor(private service: AlbumService) {}

  @Get('incoming')
  @Authenticated({ permission: Permission.AlbumRead })
  @Endpoint({
    summary: 'List incoming album ownership transfers',
    description: 'Retrieve pending ownership transfer requests for the authenticated user.',
    history: new HistoryBuilder().added('v1').beta('v1').stable('v2'),
  })
  getIncomingTransfers(@Auth() auth: AuthDto): Promise<AlbumTransferResponseDto[]> {
    return this.service.getIncomingTransfers(auth);
  }

  @Post(':id/accept')
  @Authenticated({ permission: Permission.AlbumRead })
  @Endpoint({
    summary: 'Accept album ownership transfer',
    description: 'Accept a pending album ownership transfer request.',
    history: new HistoryBuilder().added('v1').beta('v1').stable('v2'),
  })
  acceptTransfer(@Auth() auth: AuthDto, @Param() { id }: UUIDParamDto): Promise<AlbumTransferResponseDto> {
    return this.service.acceptOwnershipTransfer(auth, id);
  }

  @Post(':id/decline')
  @Authenticated({ permission: Permission.AlbumRead })
  @Endpoint({
    summary: 'Decline album ownership transfer',
    description: 'Decline a pending album ownership transfer request.',
    history: new HistoryBuilder().added('v1').beta('v1').stable('v2'),
  })
  declineTransfer(@Auth() auth: AuthDto, @Param() { id }: UUIDParamDto): Promise<AlbumTransferResponseDto> {
    return this.service.declineOwnershipTransfer(auth, id);
  }
}
