import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { PassportModule } from '@nestjs/passport';
import { InternalJwtStrategy } from './internal-jwt.strategy';
import { InternalKeyService } from './internal-key.service';

@Module({
  imports: [ConfigModule, PassportModule],
  providers: [InternalKeyService, InternalJwtStrategy],
  exports: [PassportModule],
})
export class InternalAuthModule { }
