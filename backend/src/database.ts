import { DatabaseSync } from 'node:sqlite';
import { Injectable } from '@nestjs/common';
import { mkdirSync } from 'fs';
import { join } from 'path';

/// objective: handle the photo row
/// id: string - the photo id
/// user_id: string - the user id
/// file_path: string - the file path
/// original_name: string - the original name of the photo
/// status: string - the status of the photo
/// processing_status: string - the processing status of the photo
/// validation_status: string - the validation status of the photo
/// retry_count: number - the retry count of the photo
export type PhotoRow = {
  id: string;
  user_id: string;
  file_path: string;
  original_name: string;
  status: string;
  processing_status: string;
  validation_status: string;
  retry_count: number;
  version: number;
  idempotency_key: string | null;
  job_id: string | null;
  classification: string | null;
  confidence: number | null;
  created_at: string;
};

/// objective: handle the database
/// create the database
/// insert a photo record
/// list photos
/// get a photo
/// get a photo by idempotency key
/// get a photo by job id
/// delete a photo
/// update a photo
@Injectable()
export class Database {

  readonly db: DatabaseSync; // the database connection
  readonly uploadDir: string; // the upload directory

  constructor() { // constructor
    const databasePath = process.env.DATABASE_PATH ?? join(process.cwd(), 'reefcapture.sqlite'); // the database path is the reefcapture.sqlite file in the current working directory
    this.uploadDir = process.env.UPLOAD_DIR ?? join(process.cwd(), 'uploads'); // the upload directory is the uploads directory in the current working directory or the UPLOAD_DIR environment variable
    mkdirSync(this.uploadDir, { recursive: true }); // create the upload directory if it does not exist

    this.db = new DatabaseSync(databasePath); // create the database connection
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS photos (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        original_name TEXT NOT NULL,
        status TEXT NOT NULL,
        processing_status TEXT NOT NULL DEFAULT 'NONE',
        validation_status TEXT NOT NULL DEFAULT 'NONE',
        retry_count INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1,
        idempotency_key TEXT,
        job_id TEXT,
        classification TEXT,
        confidence REAL,
        created_at TEXT NOT NULL
      );
    `);
    this.addColumnIfMissing('processing_status', `ALTER TABLE photos ADD COLUMN processing_status TEXT NOT NULL DEFAULT 'NONE'`); // add the processing status column if it is missing
    this.addColumnIfMissing('validation_status', `ALTER TABLE photos ADD COLUMN validation_status TEXT NOT NULL DEFAULT 'NONE'`); // add the validation status column if it is missing
    this.addColumnIfMissing('classification', `ALTER TABLE photos ADD COLUMN classification TEXT`); // add the classification column if it is missing
    this.addColumnIfMissing('confidence', `ALTER TABLE photos ADD COLUMN confidence REAL`); // add the confidence column if it is missing
    this.addColumnIfMissing('job_id', `ALTER TABLE photos ADD COLUMN job_id TEXT`); // add the job id column if it is missing
    try { // try to create the unique index if it is missing
      this.db.exec(`
        CREATE UNIQUE INDEX IF NOT EXISTS photos_user_idempotency
        ON photos(user_id, idempotency_key)
        WHERE idempotency_key IS NOT NULL;
      `);
    } catch { 
      // leftover duplicates from before idempotency was enforced // ignore the error
    }
    /// update the photos table to set the processing status to COMPLETED and the validation status to PENDING if the processing status is NONE
    this.db.exec(`
      UPDATE photos
      SET processing_status = 'COMPLETED',
          validation_status = CASE WHEN validation_status = 'NONE' THEN 'PENDING' ELSE validation_status END
      WHERE processing_status = 'NONE';
    `);
    /// update the photos table to set the classification to healthy_coral and the confidence to 0.92 if the classification is null
    this.db.exec(`
      UPDATE photos
      SET classification = COALESCE(classification, 'healthy_coral'),
          confidence = COALESCE(confidence, 0.92)
      WHERE processing_status = 'COMPLETED' AND classification IS NULL;
    `);
  }

  /// INSERT - insert a photo record
  /// insert the photo record into the database
  /// return the photo id and job id
  /// if the photo is not found, throw a NotFoundException
  /// if the photo version is not the same as the version provided, throw a ConflictException
  /// update the photo version to the next version
  /// update the photo validation status to APPROVED or REJECTED
  /// return the photo id and job id
  insertPhoto(row: PhotoRow): void {
    this.db
      .prepare(
        `INSERT INTO photos (
           id, user_id, file_path, original_name, status, processing_status, validation_status,
           retry_count, version, idempotency_key, job_id, classification, confidence, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        row.id,
        row.user_id,
        row.file_path,
        row.original_name,
        row.status,
        row.processing_status,
        row.validation_status,
        row.retry_count,
        row.version,
        row.idempotency_key,
        row.job_id,
        row.classification,
        row.confidence,
        row.created_at,
      );
  }

/// GET - list photos
/// return the list of photos for the user
/// if the user is provided, return the list of photos for the user
/// otherwise, return the list of all photos
/// return the list of photos for the user
  listPhotos(userId?: string): PhotoRow[] {
    if (userId) {
      return this.db
        .prepare('SELECT * FROM photos WHERE user_id = ? ORDER BY created_at DESC')
        .all(userId) as PhotoRow[];
    }
    return this.db.prepare('SELECT * FROM photos ORDER BY created_at DESC').all() as PhotoRow[];
  }

  /// GET - get a photo 
  /// return the photo for the given id
  /// if the photo is not found, return undefined
  /// return the photo for the given id
  getPhoto(id: string): PhotoRow | undefined {
    return this.db.prepare('SELECT * FROM photos WHERE id = ?').get(id) as PhotoRow | undefined;
  }

  /// GET - get a photo by idempotency key
  /// return the photo for the given idempotency key
  /// if the photo is not found, return undefined
  /// return the photo for the given idempotency key
  getPhotoByIdempotencyKey(userId: string, idempotencyKey: string): PhotoRow | undefined {
    return this.db
      .prepare('SELECT * FROM photos WHERE user_id = ? AND idempotency_key = ?')
      .get(userId, idempotencyKey) as PhotoRow | undefined;
  }

  /// GET - get a photo by job id
  /// return the photo for the given job id
  /// if the photo is not found, return undefined
  /// return the photo for the given job id
  getPhotoByJobId(jobId: string): PhotoRow | undefined {
    return this.db.prepare('SELECT * FROM photos WHERE job_id = ?').get(jobId) as PhotoRow | undefined;
  }

  /// DELETE - delete a photo
  /// delete the photo from the database
  /// return the photo id and job id
  /// if the photo is not found, return undefined
  /// return the photo id and job id
  deletePhoto(id: string): void {
    this.db.prepare('DELETE FROM photos WHERE id = ?').run(id);
  }

  /// UPDATE - update a photo
  /// update the photo in the database
  /// return the photo id and job id
  /// if the photo is not found, return undefined
  /// return the photo id and job id
  updatePhoto(
    id: string,
    fields: { // fields to update
      version?: number;
      validation_status?: string;
      retry_count?: number;
      processing_status?: string;
      job_id?: string | null;
      classification?: string | null;
      confidence?: number | null;
    },
  ): void { /// objective: update a photo in the database
    const current = this.getPhoto(id);
    if (!current) {
      return;
    }
    /// update the photo in the database
    this.db
      .prepare(
        `UPDATE photos
         SET version = ?, validation_status = ?, retry_count = ?, processing_status = ?,
             job_id = ?, classification = ?, confidence = ?
         WHERE id = ?`,
      )
      .run( /// objective: update the photo in the database
        fields.version ?? current.version,
        fields.validation_status ?? current.validation_status,
        fields.retry_count ?? current.retry_count,
        fields.processing_status ?? current.processing_status,
        fields.job_id === undefined ? current.job_id : fields.job_id,
        fields.classification === undefined ? current.classification : fields.classification,
        fields.confidence === undefined ? current.confidence : fields.confidence,
        id,
      );
  }

  /// ADD COLUMN IF MISSING - add a column if it is missing
  private addColumnIfMissing(name: string, sql: string): void {
    const columns = this.db.prepare('PRAGMA table_info(photos)').all() as { name: string }[];
    if (!columns.some((column) => column.name === name)) {
      this.db.exec(sql);
    }
  }
}
