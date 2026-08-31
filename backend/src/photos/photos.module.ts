import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { Database } from '../database';
import { PhotosController } from './photos.controller';
import { PhotosService } from './photos.service';

@Module({
  imports: [AuthModule],
  controllers: [PhotosController],
  providers: [PhotosService, Database],
})
export class PhotosModule {}
