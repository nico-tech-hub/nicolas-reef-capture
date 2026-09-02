import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  HttpCode,
  NotFoundException,
  Param,
  Post,
  Req,
  StreamableFile,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { createReadStream, existsSync, readFileSync, statSync } from 'fs';
import { memoryStorage } from 'multer';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AuthUser } from '../auth/auth.service';
import { PhotosService } from './photos.service';

/// objective: handle the photos API
/// upload a photo
/// list photos
/// get a photo file
/// validate a photo
/// retry a photo
/// delete a photo
/// all routes are protected by the JwtAuthGuard
@Controller('photos')
@UseGuards(JwtAuthGuard)
export class PhotosController {
  constructor(private readonly photosService: PhotosService) {}

  /// POST - upload a photo
  /// create a new photo record in the database
  /// return the photo id and job id
  @Post()
  @UseInterceptors(FileInterceptor('file', { storage: memoryStorage() })) // use the FileInterceptor to handle the file upload
  upload(
    @UploadedFile() file: Express.Multer.File, // the uploaded file
    @Headers('idempotency-key') idempotencyKey: string | undefined, // the idempotency key
    @Req() request: { user: AuthUser }, // the user making the request
  ) {
    return this.photosService.create(request.user.sub, file, idempotencyKey); // create the photo record in the database and return the photo id and job id
  }

  /// GET - list photos
  /// return the list of photos for the user
  @Get()
  list(@Req() request: { user: AuthUser }) {
    return this.photosService.list(request.user.sub, request.user.role); // return the list of photos for the user
  }

  /// GET - get a photo file
  /// return the photo file
  @Get(':id/file')
  file(@Param('id') id: string) {
    const photo = this.photosService.getOrThrow(id); // get the photo from the database
    if (!existsSync(photo.file_path) || statSync(photo.file_path).size < 2) {
      throw new NotFoundException('Photo file not found');
    }
    const soi = readFileSync(photo.file_path).subarray(0, 2);
    if (soi[0] !== 0xff || soi[1] !== 0xd8) {
      throw new NotFoundException('Photo file not found');
    }
    return new StreamableFile(createReadStream(photo.file_path), { // create a streamable file from the photo file path
      type: 'image/jpeg', // set the content type to image/jpeg
      disposition: `inline; filename="${photo.original_name}"`, // set the disposition to inline and the filename to the original name of the photo
    }); // return the streamable file
  }

  /// POST - validate a photo
  /// validate the photo
  /// return the photo id and job id
  @Post(':id/validate')
  validate( // validate the photo
    @Param('id') id: string, // the photo id
    @Body() body: { version?: number; approved?: boolean }, // the body of the request
    @Req() request: { user: AuthUser }, // the user making the request
  ) {
    return this.photosService.validate(id, body.version ?? 0, Boolean(body.approved)); // validate the photo and return the photo id and job id
  }

  /// POST - retry a photo
  /// retry the photo
  /// return the photo id and job id
  @Post(':id/retry')
  retry( // retry the photo
    @Param('id') id: string, // the photo id
    @Req() request: { user: AuthUser }, // the user making the request
  ) {
    return this.photosService.retry(id); // retry the photo and return the photo id and job id
  }

  /// DELETE - delete a photo
  /// delete the photo
  /// return the photo id and job id
  @Delete(':id')
  @HttpCode(204)
  remove(@Param('id') id: string, @Req() request: { user: AuthUser }) {
    this.photosService.remove(id, request.user); // delete the photo and return the photo id and job id   
  }
}
