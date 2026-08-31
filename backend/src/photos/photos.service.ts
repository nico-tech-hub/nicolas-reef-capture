import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { writeFileSync } from 'fs';
import { join } from 'path';
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

@Injectable()
export class PhotosService {
  constructor(private readonly database: Database) {}

  create(userId: string, file: Express.Multer.File | undefined, idempotencyKey?: string) {
    if (!file) {
      throw new BadRequestException('file is required');
    }

    const photoId = randomUUID();
    const filePath = join(this.database.uploadDir, `${photoId}.jpg`);
    writeFileSync(filePath, file.buffer);

    this.database.insertPhoto({
      id: photoId,
      user_id: userId,
      file_path: filePath,
      original_name: file.originalname || 'photo.jpg',
      status: 'UPLOADED',
      processing_status: 'COMPLETED',
      validation_status: 'PENDING',
      retry_count: 0,
      version: 1,
      idempotency_key: idempotencyKey ?? null,
      classification: 'healthy_coral',
      confidence: 0.92,
      created_at: new Date().toISOString(),
    });

    return {
      photoId,
      jobId: null,
      status: 'UPLOADED',
    };
  }

  list(userId: string, role: string): PhotoDto[] {
    const rows = role === 'scientist' ? this.database.listPhotos() : this.database.listPhotos(userId);
    return rows.map((row) => this.toDto(row));
  }

  getOrThrow(id: string): PhotoRow {
    const photo = this.database.getPhoto(id);
    if (!photo) {
      throw new NotFoundException('Photo not found');
    }
    return photo;
  }

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

  retry(id: string): PhotoDto {
    const photo = this.getOrThrow(id);
    this.database.updatePhoto(id, {
      retry_count: photo.retry_count + 1,
      processing_status: 'COMPLETED',
      validation_status: 'PENDING',
    });
    return this.toDto(this.getOrThrow(id));
  }

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
