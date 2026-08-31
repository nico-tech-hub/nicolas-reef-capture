import { Module } from '@nestjs/common';
import { AuthModule } from './auth/auth.module';
import { PhotosModule } from './photos/photos.module';

@Module({
  imports: [AuthModule, PhotosModule],
})
export class AppModule {}
