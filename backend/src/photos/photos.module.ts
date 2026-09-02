import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { Database } from '../database';
import { JobsController } from './jobs.controller';
import { PhotosController } from './photos.controller';
import { PhotosService } from './photos.service';

@Module({
  imports: [AuthModule],
  controllers: [PhotosController, JobsController],
  providers: [PhotosService, Database],
})
export class PhotosModule {}
