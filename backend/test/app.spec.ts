import { mkdtempSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';

describe('Auth + Photos', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const root = mkdtempSync(join(tmpdir(), 'reefcapture-'));
    process.env.DATABASE_PATH = join(root, 'test.sqlite');
    process.env.UPLOAD_DIR = join(root, 'uploads');
    process.env.JWT_SECRET = 'test-secret';
    process.env.PROCESSING_DELAY_MS = '80';

    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleRef.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  async function login(email = 'diver@example.com', password = 'password') {
    const response = await request(app.getHttpServer()).post('/auth/login').send({ email, password });
    return response;
  }

  it('returns a JWT for valid credentials', async () => {
    const response = await login();

    expect(response.status).toBe(200);
    expect(response.body.accessToken).toEqual(expect.any(String));
  });

  it('rejects invalid credentials', async () => {
    const response = await login('diver@example.com', 'wrong');

    expect(response.status).toBe(401);
  });

  it('rejects photo upload without a token', async () => {
    const response = await request(app.getHttpServer())
      .post('/photos')
      .attach('file', Buffer.from('fake-jpeg'), 'coral.jpg');

    expect(response.status).toBe(401);
  });

  it('stores an authenticated photo upload and returns photoId', async () => {
    const token = (await login()).body.accessToken as string;

    const response = await request(app.getHttpServer())
      .post('/photos')
      .set('Authorization', `Bearer ${token}`)
      .set('Idempotency-Key', '11111111-1111-1111-1111-111111111111')
      .attach('file', Buffer.from('fake-jpeg'), 'coral.jpg');

    expect(response.status).toBe(201);
    expect(response.body.photoId).toEqual(expect.any(String));
    expect(response.body.jobId).toEqual(expect.any(String));
    expect(response.body.status).toBe('PROCESSING');

    const list = await request(app.getHttpServer()).get('/photos').set('Authorization', `Bearer ${token}`);

    expect(list.status).toBe(200);
    expect(list.body).toHaveLength(1);
    expect(list.body[0].id).toBe(response.body.photoId);
    expect(list.body[0].userId).toBe('user-diver');
    expect(list.body[0].validationStatus).toBe('PENDING');
  });

  it('increments version on validation and returns 409 on stale version', async () => {
    const diverToken = (await login()).body.accessToken as string;
    const uploaded = await request(app.getHttpServer())
      .post('/photos')
      .set('Authorization', `Bearer ${diverToken}`)
      .attach('file', Buffer.from('fake-jpeg'), 'coral.jpg');

    const scientistToken = (await login('scientist@example.com')).body.accessToken as string;
    const photoId = uploaded.body.photoId as string;

    const approved = await request(app.getHttpServer())
      .post(`/photos/${photoId}/validate`)
      .set('Authorization', `Bearer ${scientistToken}`)
      .send({ version: 1, approved: true });

    expect(approved.status).toBe(201);
    expect(approved.body.version).toBe(2);
    expect(approved.body.validationStatus).toBe('APPROVED');

    const conflict = await request(app.getHttpServer())
      .post(`/photos/${photoId}/validate`)
      .set('Authorization', `Bearer ${scientistToken}`)
      .send({ version: 1, approved: false });

    expect(conflict.status).toBe(409);
  });

  it('does not create a duplicate photo for the same Idempotency-Key', async () => {
    const token = (await login()).body.accessToken as string;

    const first = await request(app.getHttpServer())
      .post('/photos')
      .set('Authorization', `Bearer ${token}`)
      .set('Idempotency-Key', 'ABC123')
      .attach('file', Buffer.from('first-jpeg'), 'coral.jpg');

    const afterFirst = await request(app.getHttpServer())
      .get('/photos')
      .set('Authorization', `Bearer ${token}`);
    const countAfterFirst = afterFirst.body.length as number;

    const second = await request(app.getHttpServer())
      .post('/photos')
      .set('Authorization', `Bearer ${token}`)
      .set('Idempotency-Key', 'ABC123')
      .attach('file', Buffer.from('retry-jpeg'), 'coral-retry.jpg');

    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    expect(second.body.photoId).toBe(first.body.photoId);
    expect(second.body.jobId).toBe(first.body.jobId);
    expect(['PROCESSING', 'COMPLETED']).toContain(second.body.status);

    const afterSecond = await request(app.getHttpServer())
      .get('/photos')
      .set('Authorization', `Bearer ${token}`);
    expect(afterSecond.body).toHaveLength(countAfterFirst);
  });

  it('scopes Idempotency-Key per user', async () => {
    const diverToken = (await login()).body.accessToken as string;
    const scientistToken = (await login('scientist@example.com')).body.accessToken as string;

    const diverUpload = await request(app.getHttpServer())
      .post('/photos')
      .set('Authorization', `Bearer ${diverToken}`)
      .set('Idempotency-Key', 'SHARED-KEY')
      .attach('file', Buffer.from('diver-jpeg'), 'diver.jpg');

    const scientistUpload = await request(app.getHttpServer())
      .post('/photos')
      .set('Authorization', `Bearer ${scientistToken}`)
      .set('Idempotency-Key', 'SHARED-KEY')
      .attach('file', Buffer.from('scientist-jpeg'), 'scientist.jpg');

    expect(diverUpload.body.photoId).not.toBe(scientistUpload.body.photoId);
  });

  it('completes a processing job with a fake classification', async () => {
    const token = (await login()).body.accessToken as string;

    const uploaded = await request(app.getHttpServer())
      .post('/photos')
      .set('Authorization', `Bearer ${token}`)
      .set('Idempotency-Key', 'JOB-FLOW')
      .attach('file', Buffer.from('fake-jpeg'), 'coral.jpg');

    expect(uploaded.body.status).toBe('PROCESSING');
    expect(uploaded.body.jobId).toEqual(expect.any(String));

    const whileProcessing = await request(app.getHttpServer())
      .get(`/jobs/${uploaded.body.jobId as string}`)
      .set('Authorization', `Bearer ${token}`);

    expect(whileProcessing.status).toBe(200);
    expect(whileProcessing.body.photoId).toBe(uploaded.body.photoId);
    expect(['PROCESSING', 'COMPLETED']).toContain(whileProcessing.body.status);

    await new Promise((resolve) => setTimeout(resolve, 200));

    const completed = await request(app.getHttpServer())
      .get(`/jobs/${uploaded.body.jobId as string}`)
      .set('Authorization', `Bearer ${token}`);

    expect(completed.status).toBe(200);
    expect(completed.body.status).toBe('COMPLETED');
    expect(completed.body.classification).toBe('healthy_coral');
    expect(completed.body.confidence).toBe(0.92);

    const list = await request(app.getHttpServer()).get('/photos').set('Authorization', `Bearer ${token}`);
    const photo = list.body.find((item: { id: string }) => item.id === uploaded.body.photoId);

    expect(photo.processingStatus).toBe('COMPLETED');
    expect(photo.classification).toBe('healthy_coral');
    expect(photo.confidence).toBe(0.92);
  });

  it('retries processing without duplicating the photo row', async () => {
    const token = (await login()).body.accessToken as string;
    const scientistToken = (await login('scientist@example.com')).body.accessToken as string;

    const uploaded = await request(app.getHttpServer())
      .post('/photos')
      .set('Authorization', `Bearer ${token}`)
      .attach('file', Buffer.from('fake-jpeg'), 'coral.jpg');

    await new Promise((resolve) => setTimeout(resolve, 200));

    const retried = await request(app.getHttpServer())
      .post(`/photos/${uploaded.body.photoId as string}/retry`)
      .set('Authorization', `Bearer ${scientistToken}`);

    expect(retried.status).toBe(201);
    expect(retried.body.id).toBe(uploaded.body.photoId);
    expect(retried.body.retryCount).toBe(1);
    expect(retried.body.processingStatus).toBe('PROCESSING');

    const list = await request(app.getHttpServer())
      .get('/photos')
      .set('Authorization', `Bearer ${scientistToken}`);
    const matches = list.body.filter((item: { id: string }) => item.id === uploaded.body.photoId);
    expect(matches).toHaveLength(1);
  });

  it('deletes a photo and treats a second delete as safe', async () => {
    const token = (await login()).body.accessToken as string;
    const uploaded = await request(app.getHttpServer())
      .post('/photos')
      .set('Authorization', `Bearer ${token}`)
      .attach('file', Buffer.from('fake-jpeg'), 'coral.jpg');

    const photoId = uploaded.body.photoId as string;

    const deleted = await request(app.getHttpServer())
      .delete(`/photos/${photoId}`)
      .set('Authorization', `Bearer ${token}`);

    expect(deleted.status).toBe(204);

    const list = await request(app.getHttpServer()).get('/photos').set('Authorization', `Bearer ${token}`);
    expect(list.body.find((item: { id: string }) => item.id === photoId)).toBeUndefined();

    const file = await request(app.getHttpServer())
      .get(`/photos/${photoId}/file`)
      .set('Authorization', `Bearer ${token}`);
    expect(file.status).toBe(404);

    const again = await request(app.getHttpServer())
      .delete(`/photos/${photoId}`)
      .set('Authorization', `Bearer ${token}`);

    expect(again.status).not.toBe(500);
    expect([204, 404]).toContain(again.status);
  });

  it('forbids a diver from deleting another user photo', async () => {
    const scientistToken = (await login('scientist@example.com')).body.accessToken as string;
    const uploaded = await request(app.getHttpServer())
      .post('/photos')
      .set('Authorization', `Bearer ${scientistToken}`)
      .attach('file', Buffer.from('scientist-jpeg'), 'scientist.jpg');

    const diverToken = (await login()).body.accessToken as string;
    const forbidden = await request(app.getHttpServer())
      .delete(`/photos/${uploaded.body.photoId as string}`)
      .set('Authorization', `Bearer ${diverToken}`);

    expect(forbidden.status).toBe(403);
  });
});
