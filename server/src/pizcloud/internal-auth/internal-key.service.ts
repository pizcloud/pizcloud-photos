import { Injectable } from '@nestjs/common';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { INTERNAL_JWT_PUBLIC_KEY_PATH } from 'src/constants';

@Injectable()
export class InternalKeyService {
  public readonly publicKey: string;

  constructor() {
    const publicKeyPath = INTERNAL_JWT_PUBLIC_KEY_PATH;
    if (!publicKeyPath) {
      throw new Error('JWT public key is not configured');
    }
    this.publicKey = readFileSync(resolve(publicKeyPath), 'utf-8');
  }
}
