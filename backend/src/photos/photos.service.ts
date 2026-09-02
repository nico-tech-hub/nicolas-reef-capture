import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  OnModuleDestroy,
} from '@nestjs/common';
import { randomUUID } from 'crypto';
import { existsSync, unlinkSync, writeFileSync } from 'fs';
import { join } from 'path';
import { AuthUser } from '../auth/auth.service';
import { USERS } from '../auth/users';
import { Database, PhotoRow } from '../database';

export type PhotoDto = {
  id: string;
  userId: string;
  userEmail: string;
  originalName: string;
  status: string;
  processingStatus: string;
  validationStatus: string;
  retryCount: number;
  version: number;
  classification: string | null;
  confidence: number | null;
  createdAt: string;
};

export type UploadResult = {
  photoId: string;
  jobId: string;
  status: string;
};

export type JobDto = {
  jobId: string;
  photoId: string;
  status: string;
  classification: string | null;
  confidence: number | null;
};

/// objective: handle the photos service
/// create a photo record in the database
/// list photos
/// get a photo
/// validate a photo
/// retry a photo
/// delete a photo
/// all routes are protected by the JwtAuthGuard
@Injectable()
export class PhotosService implements OnModuleDestroy {
  private readonly timeouts = new Set<ReturnType<typeof setTimeout>>();

  constructor(private readonly database: Database) {}

  /// POST - create a photo record in the database
  /// return the photo id and job id
  /// if the idempotency key is provided, check if the photo record already exists
  /// if the file is not provided, throw a BadRequestException
  /// generate a random photo id and job id
  /// join the upload directory and the photo id
  /// write the file to the upload directory
  /// insert the photo record into the database
  /// schedule the completion of the photo
  /// return the photo id and job id
  create(userId: string, file: Express.Multer.File | undefined, idempotencyKey?: string): UploadResult {
    if (idempotencyKey) { // if the idempotency key is provided, check if the photo record already exists
      const existing = this.database.getPhotoByIdempotencyKey(userId, idempotencyKey);
      if (existing) {
        return this.toUploadResult(existing); // return the photo id and job id
      }
    }

    if (!file) { // if the file is not provided, throw a BadRequestException
      throw new BadRequestException('file is required');
    }

    const photoId = randomUUID(); // generate a random photo id
    const jobId = randomUUID(); // generate a random job id
    const filePath = join(this.database.uploadDir, `${photoId}.jpg`); // join the upload directory and the photo id
    writeFileSync(filePath, file.buffer); // write the file to the upload directory

    this.database.insertPhoto({ // insert the photo record into the database
      id: photoId,
      user_id: userId,
      file_path: filePath,
      original_name: file.originalname || 'photo.jpg',
      status: 'UPLOADED',
      processing_status: 'PROCESSING',
      validation_status: 'PENDING',
      retry_count: 0,
      version: 1,
      idempotency_key: idempotencyKey ?? null,
      job_id: jobId,
      classification: null,
      confidence: null,
      created_at: new Date().toISOString(),
    });

    this.scheduleCompletion(photoId); // schedule the completion of the photo
    return this.toUploadResult(this.getOrThrow(photoId)); // return the photo id and job id
  }
  
  /// GET - list photos
  /// return the list of photos for the user
  /// if the user is a scientist, return all photos
  /// if the user is a diver, return only the photos for the user
  /// return the list of photos for the user
  list(userId: string, role: string): PhotoDto[] {
    const rows = role === 'scientist' ? this.database.listPhotos() : this.database.listPhotos(userId);
    return rows.map((row) => this.toDto(row));
  }

  /// GET - get a photo
  /// return the photo for the given id
  /// if the photo is not found, throw a NotFoundException
  /// return the photo for the given id
  getOrThrow(id: string): PhotoRow {
    const photo = this.database.getPhoto(id);
    if (!photo) {
      throw new NotFoundException('Photo not found');
    }
    return photo;
  }

  /// GET - get a job
  /// return the job for the given id
  /// if the job is not found, throw a NotFoundException
  /// if the user is not a scientist, check if the job is for the user
  /// if the job is not found, throw a NotFoundException
  /// if the job id is not found, throw a NotFoundException
  /// return the job id, photo id, status, classification, and confidence
  getJob(jobId: string, user: AuthUser): JobDto {
    const photo = this.database.getPhotoByJobId(jobId);
    if (!photo || (user.role !== 'scientist' && photo.user_id !== user.sub)) {
      throw new NotFoundException('Job not found');
    }
    if (!photo.job_id) {
      throw new NotFoundException('Job not found');
    }
    return {
      jobId: photo.job_id,
      photoId: photo.id,
      status: photo.processing_status,
      classification: photo.classification,
      confidence: photo.confidence,
    };
  }

  /// POST - validate a photo
  /// validate the photo
  /// return the photo id and job id
  /// if the photo is not found, throw a NotFoundException
  /// if the photo version is not the same as the version provided, throw a ConflictException
  /// update the photo version to the next version
  /// update the photo validation status to APPROVED or REJECTED
  /// return the photo id and job id
  validate(id: string, version: number, approved: boolean): PhotoDto {
    const photo = this.getOrThrow(id);
    if (photo.version !== version) {
      throw new ConflictException('Conflict: this result has been modified by another user. Please refresh.');
    }

    this.database.updatePhoto(id, {
      version: photo.version + 1,
      validation_status: approved ? 'APPROVED' : 'REJECTED',
    });
    return this.toDto(this.getOrThrow(id));
  }

  /// POST - retry a photo
  /// retry the photo
  /// return the photo id and job id
  /// if the photo is not found, throw a NotFoundException
  /// generate a new job id
  /// update the photo status to PROCESSING
  /// update the photo validation status to PENDING
  /// update the photo job id
  /// update the photo classification to null
  /// update the photo confidence to null
  /// schedule the completion of the photo
  /// return the photo id and job id
  retry(id: string): PhotoDto {
    const photo = this.getOrThrow(id);
    const jobId = randomUUID();
    this.database.updatePhoto(id, {
      retry_count: photo.retry_count + 1,
      processing_status: 'PROCESSING',
      validation_status: 'PENDING',
      job_id: jobId,
      classification: null,
      confidence: null,
    });
    this.scheduleCompletion(id);
    return this.toDto(this.getOrThrow(id));
  }

  /// DELETE - delete a photo
  /// delete the photo
  /// return the photo id and job id
  /// if the photo is not found, throw a NotFoundException
  /// if the user is not a scientist, check if the photo is for the user
  /// delete the photo
  /// delete the file
  remove(id: string, user: AuthUser): void {
    const photo = this.database.getPhoto(id);
    if (!photo) {
      throw new NotFoundException('Photo not found');
    }
    if (user.role !== 'scientist' && photo.user_id !== user.sub) {
      throw new ForbiddenException('You can only delete your own photos');
    }

    this.database.deletePhoto(id);
    if (existsSync(photo.file_path)) {
      unlinkSync(photo.file_path);
    }
  }

  /// onModuleDestroy - clear the timeouts
  /// clear the timeouts
  onModuleDestroy(): void {
    for (const timeout of this.timeouts) {
      clearTimeout(timeout);
    }
    this.timeouts.clear();
  }

  /// SIMULATE - schedule the completion of the photo by a job manager (fake AI processing)
  /// set a timeout to the processing delay
  /// if the photo is not found, return
  /// if the photo is not processing, return
  /// update the photo status to COMPLETED
  /// update the photo classification to healthy_coral
  /// update the photo confidence to 0.92
  private scheduleCompletion(photoId: string): void { /// objective: schedule the completion of the photo
    const timeout = setTimeout(() => {
      this.timeouts.delete(timeout);
      const photo = this.database.getPhoto(photoId); // get the photo from the database
      if (!photo || photo.processing_status !== 'PROCESSING') { // if the photo is not found or not processing, return
        return;
      }
      this.database.updatePhoto(photoId, { // update the photo in the database
        processing_status: 'COMPLETED',
        classification: 'healthy_coral',
        confidence: 0.92,
      });
    }, this.processingDelayMs());
    this.timeouts.add(timeout);
  }

  /// GET - processing delay milliseconds
  /// return the processing delay milliseconds
  /// if the processing delay milliseconds is not a number, return 5000
  /// return the processing delay milliseconds
  private processingDelayMs(): number {
    const parsed = Number(process.env.PROCESSING_DELAY_MS);
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : 5000;
  }

  /// TO UPLOAD RESULT - convert a photo row to an upload result
  /// return the photo id and job id
  /// return the photo id and job id
  private toUploadResult(row: PhotoRow): UploadResult {
    return { /// objective: convert a photo row to an upload result
      photoId: row.id,
      jobId: row.job_id ?? '',
      status: row.processing_status,
    };
  }

  /// TO DTO - convert a photo row to a photo dto
  /// return the photo id and job id
  private toDto(row: PhotoRow): PhotoDto {
    const user = USERS.find((candidate) => candidate.id === row.user_id);
    return {
      id: row.id,
      userId: row.user_id,
      userEmail: user?.email ?? row.user_id,
      originalName: row.original_name,
      status: row.status,
      processingStatus: row.processing_status,
      validationStatus: row.validation_status,
      retryCount: row.retry_count,
      version: row.version,
      classification: row.classification,
      confidence: row.confidence,
      createdAt: row.created_at,
    };
  }
}
