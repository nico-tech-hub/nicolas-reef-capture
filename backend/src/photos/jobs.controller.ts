import { Controller, Get, Param, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/auth.service';
import { PhotosService } from './photos.service';

@Controller('jobs')
@UseGuards(JwtAuthGuard)
export class JobsController {
  constructor(private readonly photosService: PhotosService) {}

  @Get(':jobId')
  getJob(@Param('jobId') jobId: string, @Req() request: { user: AuthUser }) {
    return this.photosService.getJob(jobId, request.user);
  }
}
