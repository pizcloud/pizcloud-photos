import { ApiProperty } from '@nestjs/swagger'; // pizcloud
import { ArrayMaxSize, ArrayNotEmpty, IsEmail, IsNotEmpty } from 'class-validator';
import { UserResponseDto } from 'src/dtos/user.dto';
import { PartnerDirection } from 'src/repositories/partner.repository';
import { ValidateEnum, ValidateUUID } from 'src/validation';

export class PartnerCreateDto {
  @ValidateUUID()
  sharedWithId!: string;
}

export class PartnerUpdateDto {
  @IsNotEmpty()
  inTimeline!: boolean;
}

export class PartnerSearchDto {
  @ValidateEnum({ enum: PartnerDirection, name: 'PartnerDirection' })
  direction!: PartnerDirection;
}

export class PartnerResponseDto extends UserResponseDto {
  inTimeline?: boolean;
}

// pizcloud: New DTOs for resolving partner share emails without exposing all users.
export class PartnerResolveEmailsDto {
  @ArrayNotEmpty()
  @ArrayMaxSize(50)
  @IsEmail({ require_tld: false }, { each: true })
  emails!: string[];
}

export class PartnerResolveEmailsResponseDto {
  @ApiProperty({ type: [String] })
  userIds!: string[];

  @ApiProperty({ type: [String] })
  missingEmails!: string[];
}
// #pizcloud
