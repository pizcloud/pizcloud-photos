import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class InternalJwtGuard extends AuthGuard('internal-jwt') { }
