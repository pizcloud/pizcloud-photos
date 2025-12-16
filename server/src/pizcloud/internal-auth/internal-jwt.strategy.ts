import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { INTERNAL_JWT_AUDIENCE, INTERNAL_JWT_ISSUER } from 'src/constants';
import { InternalKeyService } from './internal-key.service';

export type InternalJwtPayload = {
  sub: string;
  svc: string;
  scope?: string[];
  jti: string;
  iat: number;
  exp: number;
  iss: string;
  aud: string | string[];
};

@Injectable()
export class InternalJwtStrategy extends PassportStrategy(Strategy, 'internal-jwt') {
  constructor(keys: InternalKeyService,) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,

      secretOrKey: keys.publicKey,

      algorithms: ['RS256'],
      issuer: INTERNAL_JWT_ISSUER,
      audience: INTERNAL_JWT_AUDIENCE,
    });
  }

  validate(payload: InternalJwtPayload) {
    if (payload?.svc !== INTERNAL_JWT_ISSUER) {
      throw new UnauthorizedException('Invalid internal token (svc)');
    }
    return payload;
  }
}
