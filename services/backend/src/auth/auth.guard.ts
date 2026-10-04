import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import * as jwt from 'jsonwebtoken';
import { AuthPrincipal } from './auth.types';

export interface AuthenticatedRequest extends Request {
  user: AuthPrincipal;
}

@Injectable()
export class JwtAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest & { headers: Record<string, string | string[] | undefined> }>();
    const authorization = request.headers.authorization;
    const raw = Array.isArray(authorization) ? authorization[0] : authorization;
    if (!raw?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Bearer token required');
    }

    const secret = process.env.JWT_HS256_SECRET;
    if (!secret) throw new UnauthorizedException('JWT configuration missing');

    try {
      const payload = jwt.verify(raw.slice(7), secret, {
        algorithms: ['HS256'],
      }) as jwt.JwtPayload;
      if (typeof payload.sub !== 'string' || typeof payload.role !== 'string') {
        throw new Error('Invalid token payload');
      }
      request.user = {
        user_id: payload.sub,
        role: payload.role as AuthPrincipal['role'],
        driver_id: typeof payload.driver_id === 'string' ? payload.driver_id : undefined,
      };
      return true;
    } catch {
      throw new UnauthorizedException('Invalid or expired access token');
    }
  }
}
