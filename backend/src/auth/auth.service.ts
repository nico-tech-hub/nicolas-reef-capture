import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { USERS } from './users';


export type AuthUser = {
  sub: string; // subject for the JWT token, we use user.id 
  email: string; // email
  role: 'diver' | 'scientist'; // role
};

/// objective: authenticate the user
/// return the access token
/// if the credentials are invalid, throw a UnauthorizedException
@Injectable()
export class AuthService {
  constructor(private readonly jwtService: JwtService) {}

  /// POST - login
  login(email: string, password: string): { accessToken: string } {
    const user = USERS.find((candidate) => candidate.email === email && candidate.password === password);
    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const payload: AuthUser = {
      sub: user.id,
      email: user.email,
      role: user.role,
    };

    return { accessToken: this.jwtService.sign(payload) };
  }
}
