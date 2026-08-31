import { DatabaseSync } from 'node:sqlite';
import { Injectable } from '@nestjs/common';
import { mkdirSync } from 'fs';
import { join } from 'path';

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
  classification: string | null;
  confidence: number | null;
  created_at: string;
};

@Injectable()
export class Database {
  readonly db: DatabaseSync;
  readonly uploadDir: string;

  constructor() {
    const databasePath = process.env.DATABASE_PATH ?? join(process.cwd(), 'reefcapture.sqlite');
    this.uploadDir = process.env.UPLOAD_DIR ?? join(process.cwd(), 'uploads');
    mkdirSync(this.uploadDir, { recursive: true });

    this.db = new DatabaseSync(databasePath);
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
        classification TEXT,
        confidence REAL,
        created_at TEXT NOT NULL
      );
    `);
    this.addColumnIfMissing('processing_status', `ALTER TABLE photos ADD COLUMN processing_status TEXT NOT NULL DEFAULT 'NONE'`);
    this.addColumnIfMissing('validation_status', `ALTER TABLE photos ADD COLUMN validation_status TEXT NOT NULL DEFAULT 'NONE'`);
    this.addColumnIfMissing('classification', `ALTER TABLE photos ADD COLUMN classification TEXT`);
    this.addColumnIfMissing('confidence', `ALTER TABLE photos ADD COLUMN confidence REAL`);
    this.db.exec(`
      UPDATE photos
      SET processing_status = CASE WHEN processing_status = 'NONE' THEN 'COMPLETED' ELSE processing_status END,
          validation_status = CASE WHEN validation_status = 'NONE' THEN 'PENDING' ELSE validation_status END,
          classification = COALESCE(classification, 'healthy_coral'),
          confidence = COALESCE(confidence, 0.92)
    `);
  }

  insertPhoto(row: PhotoRow): void {
    this.db
      .prepare(
        `INSERT INTO photos (
           id, user_id, file_path, original_name, status, processing_status, validation_status,
           retry_count, version, idempotency_key, classification, confidence, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
        row.classification,
        row.confidence,
        row.created_at,
      );
  }

  listPhotos(userId?: string): PhotoRow[] {
    if (userId) {
      return this.db
        .prepare('SELECT * FROM photos WHERE user_id = ? ORDER BY created_at DESC')
        .all(userId) as PhotoRow[];
    }
    return this.db.prepare('SELECT * FROM photos ORDER BY created_at DESC').all() as PhotoRow[];
  }

  getPhoto(id: string): PhotoRow | undefined {
    return this.db.prepare('SELECT * FROM photos WHERE id = ?').get(id) as PhotoRow | undefined;
  }

  updatePhoto(
    id: string,
    fields: {
      version?: number;
      validation_status?: string;
      retry_count?: number;
      processing_status?: string;
    },
  ): void {
    const current = this.getPhoto(id);
    if (!current) {
      return;
    }
    this.db
      .prepare(
        `UPDATE photos
         SET version = ?, validation_status = ?, retry_count = ?, processing_status = ?
         WHERE id = ?`,
      )
      .run(
        fields.version ?? current.version,
        fields.validation_status ?? current.validation_status,
        fields.retry_count ?? current.retry_count,
        fields.processing_status ?? current.processing_status,
        id,
      );
  }

  private addColumnIfMissing(name: string, sql: string): void {
    const columns = this.db.prepare('PRAGMA table_info(photos)').all() as { name: string }[];
    if (!columns.some((column) => column.name === name)) {
      this.db.exec(sql);
    }
  }
}
