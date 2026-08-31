import {
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Post,
  Req,
  StreamableFile,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { createReadStream } from 'fs';
import { memoryStorage } from 'multer';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/auth.service';
import { PhotosService } from './photos.service';

@Controller('photos')
@UseGuards(JwtAuthGuard)
export class PhotosController {
  constructor(private readonly photosService: PhotosService) {}

  @Post()
  @UseInterceptors(FileInterceptor('file', { storage: memoryStorage() }))
  upload(
    @UploadedFile() file: Express.Multer.File,
    @Headers('idempotency-key') idempotencyKey: string | undefined,
    @Req() request: { user: AuthUser },
  ) {
    return this.photosService.create(request.user.sub, file, idempotencyKey);
  }

  @Get()
  list(@Req() request: { user: AuthUser }) {
    return this.photosService.list(request.user.sub, request.user.role);
  }

  @Get(':id/file')
  file(@Param('id') id: string) {
    const photo = this.photosService.getOrThrow(id);
    return new StreamableFile(createReadStream(photo.file_path), {
      type: 'image/jpeg',
      disposition: `inline; filename="${photo.original_name}"`,
    });
  }

  @Post(':id/validate')
  validate(
    @Param('id') id: string,
    @Body() body: { version?: number; approved?: boolean },
  ) {
    return this.photosService.validate(id, body.version ?? 0, Boolean(body.approved));
  }

  @Post(':id/retry')
  retry(@Param('id') id: string) {
    return this.photosService.retry(id);
  }
}
