import { Module } from '@nestjs/common';
import { InternalAuthModule } from '../internal-auth/internal-auth.module';

@Module({
  imports: [InternalAuthModule],
  controllers: [],
})
export class InternalModule { }
