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
    expect(response.body.status).toBe('UPLOADED');
    expect(response.body.jobId).toBeNull();

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
});
