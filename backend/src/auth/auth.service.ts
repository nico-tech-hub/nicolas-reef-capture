import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { USERS } from './users';

export type AuthUser = {
  sub: string;
  email: string;
  role: 'diver' | 'scientist';
};

@Injectable()
export class AuthService {
  constructor(private readonly jwtService: JwtService) {}

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
