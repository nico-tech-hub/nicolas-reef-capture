import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AuthUser } from './auth.service';

/// objective: protect the routes by validating the JWT token
/// if the token is missing or invalid, throw a UnauthorizedException
/// if the token is valid, set the user in the request
/// return true if the token is valid, false otherwise
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwtService: JwtService) {} // inject the JwtService

  canActivate(context: ExecutionContext): boolean { /// objective: validate the JWT token
    const request = context.switchToHttp().getRequest<{ headers: { authorization?: string }; user?: AuthUser }>(); // get the request from the context
    const header = request.headers.authorization ?? ''; // get the authorization header from the request
    const token = header.startsWith('Bearer ') ? header.slice(7) : ''; // get the token from the authorization header
    if (!token) {
      throw new UnauthorizedException();
    }
    try {
      request.user = this.jwtService.verify<AuthUser>(token); // verify the token and set the user in the request
      return true; // return true if the token is valid
    } catch {
      throw new UnauthorizedException();
    }
  }
}
