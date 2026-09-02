# ReefCapture

Demo project for Coral Gardeners.

A diver captures a reef photo on iPhone and records an observation **while offline**. The photo is stored locally first, then uploaded when the network is back. The API persists it, runs a fake AI job, and a scientist validates the result in a web dashboard.

This is a **reliable offline architecture**, not a production product. Capture never depends on connectivity. Uploads are queued, retried, crash-safe, and idempotent. Auth is hardcoded. Classification is mocked.

## Architecture

```
iOS (SwiftUI)  --upload JPEG -->  NestJS API :3000  <--JWT-->  Vue dashboard :5173
    SwiftData local queue         SQLite + /uploads
                                  fake AI job (~5s)
```

Offline-first flow:

1. The diver picks a photo. It is copied into the sandbox (`Documents/observations/`) and saved in SwiftData with status `PENDING`. The UI never waits on the network.

2. `UploadQueue` drains pending observations one at a time (`POST /photos`) with a JWT and an `Idempotency-Key`. Interrupted uploads (`UPLOADING` after a crash) are reset to `PENDING` on launch.

3. The API writes the JPEG, creates a SQLite row + a processing job, and returns `{ photoId, jobId, status: "PROCESSING" }`. After ~5 seconds the job becomes `COMPLETED` with a fake classification (`healthy_coral`, 92%). The iOS app polls `GET /jobs/:jobId` in the background. If the app is killed during PROCESSING, polling resumes on the next launch.

4. The scientist signs in to the dashboard, sees photos move from `PROCESSING` to `COMPLETED`, and approves or rejects them (optimistic concurrency via `version`). A stale `version` returns `409`.

## Why Idempotency-Key?

A network retry must not create a second photo. The same authenticated user sending the same key gets the original result back.

```
POST /photos  Idempotency-Key: ABC123   →  creates photo + job
POST /photos  Idempotency-Key: ABC123   →  same photoId, same jobId, no extra row
```

Keys are scoped per user: `ABC123` from two accounts can be two photos.

## Structure

```
ReefCapture/
├── ios/        iPhone app (SwiftUI, SwiftData, iOS 17+)
├── backend/    NestJS API + SQLite
└── web/        Scientist dashboard (Vue 3 + Vite)
    ├── src/api.ts              HTTP only
    ├── src/stores/             Pinia (auth, photos)
    ├── src/router/             /login, /photos, /photos/:id
    ├── src/views/              LoginView, DashboardView
    └── src/components/         PhotoTable, PhotoDetail
```

The Vue app is a small official stack: **View → Store → API**. Components do not call `fetch`. Two routes plus `:id` so a refresh keeps the selected photo. No extra layers.

## Demo accounts

| Role      | Email                    | Password   |
|-----------|--------------------------|------------|
| Diver     | `diver@example.com`      | `password` |
| Scientist | `scientist@example.com`  | `password` |

A diver only sees their own photos. A scientist sees everyone.

## Prerequisites

- Node.js 22+ (native SQLite via `node:sqlite`)
- Xcode 26+ (iOS app, Swift 6)
- npm

## Run the project

### 1. API

```bash
cd backend
npm install
npm run start:dev
```

Listens on [http://127.0.0.1:3000](http://127.0.0.1:3000).  
Local database: `backend/reefcapture.sqlite`. Files: `backend/uploads/`.

Optional env vars: `DATABASE_PATH`, `UPLOAD_DIR`, `JWT_SECRET` (default `reefcapture-dev-secret`), `PROCESSING_DELAY_MS` (default `5000`; tests use `80`).

### 2. Dashboard

```bash
cd web
npm install
npm run dev
```

Open [http://127.0.0.1:5173](http://127.0.0.1:5173) (redirects to `/photos` or `/login`). Vite proxies `/auth`, `/photos`, and `/jobs` to the API.

Sign in with `scientist@example.com` / `password`.

### 3. iOS app

Open `ios/ReefCapture.xcodeproj` in Xcode and run on the **simulator**.

The app uses `ReefCaptureAPI()` (real API at `http://127.0.0.1:3000` as `diver@example.com`). On a physical iPhone, replace that URL with your Mac's LAN IP.

`FakePhotoAPI` is kept for SwiftUI Previews and unit tests (no network).

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`ios/project.yml`). After changing sources, regenerate with `xcodegen generate` in `ios/`.

## API

All `/photos` and `/jobs` routes require `Authorization: Bearer <token>`.

| Method | Route | Description |
|--------|-------|-------------|
| `POST` | `/auth/login` | `{ email, password }` → `{ accessToken }` |
| `POST` | `/photos` | multipart `file` + `Idempotency-Key` header. Same key → original photo, no duplicate |
| `GET` | `/photos` | list (filtered by role) |
| `GET` | `/photos/:id/file` | JPEG |
| `DELETE` | `/photos/:id` | remove row + JPEG. Diver: own photos only. Scientist: any. Missing photo → `404` |
| `GET` | `/jobs/:jobId` | poll fake AI job (`PROCESSING` then `COMPLETED`) |
| `POST` | `/photos/:id/validate` | `{ version, approved }` — `409` if the version is stale |
| `POST` | `/photos/:id/retry` | new processing job on the same photo row |

Upload response:

```json
{ "photoId": "...", "jobId": "...", "status": "PROCESSING" }
```

Job response:

```json
{ "jobId": "...", "photoId": "...", "status": "COMPLETED", "classification": "healthy_coral", "confidence": 0.92 }
```

## Statuses

**iOS** (`Observation.displayStatus`), derived from upload + processing:

`PENDING` → `UPLOADING` → `PROCESSING` → `COMPLETED`  
or `FAILED` (Retry button) if the upload itself fails.

Swipe left on a row to delete it. The SwiftData row and local JPEG are removed immediately (user intent, including offline). If the observation already has a `serverId`, the app then calls `DELETE /photos/:id`. A network failure is ignored: the local copy stays gone, so the user never sees a row they thought they deleted. The server copy may remain until a later successful delete (or a scientist deletes it). HTTP `404` is treated as success (already gone). Observations that were never uploaded (`PENDING`) are local-only deletes.

**API / dashboard**:

- `processingStatus`: `PROCESSING` → `COMPLETED` (fake AI after `PROCESSING_DELAY_MS`)
- `validationStatus`: `PENDING` → `APPROVED` or `REJECTED`
- `version`: incremented on each validation (`409` if two scientists validate the same version)

## Tests

This project is built **TDD-first**: a failing test describes the next behavior, then the smallest amount of code makes it pass. Do not add a feature (queue retry, idempotency, jobs, validation conflict) without a test that would have failed before the change.

**Red → green → refactor**

1. **Red** — write a test for one behavior. Run it. It must fail for the right reason.
2. **Green** — implement only what that test needs.
3. **Refactor** — clean names and duplication while tests stay green.

Keep the loop small. If the test is hard to write, the design is probably too coupled. Introduce a seam (`PhotoUploading`, in-memory SwiftData, temp SQLite) and test through that.

```bash
# API
cd backend && npm test

# iOS (from the ios folder, or via Xcode ⌘U)
xcodebuild test -scheme ReefCapture -destination 'platform=iOS Simulator,name=iPhone 16'
```

Covered: `PENDING` observation, upload queue, failed retry without duplication, same `Idempotency-Key` does not duplicate, job becomes `COMPLETED`, validation increments `version` and returns `409`, `DELETE /photos/:id` removes the photo and a second delete is not a 500.

## Interview concepts

- Offline-first local store + upload queue
- Idempotency keys (network retry ≠ duplicate row)
- Job IDs (API returns immediately, client polls)
- HTTP 409 / optimistic concurrency (`version`)
- Protocol-based DI (`PhotoUploading`) so the queue is unit-tested without HTTP
- Local delete first, then best-effort remote delete

## Prototype limits

- Accounts and passwords are plaintext in `backend/src/auth/users.ts`
- No real ML model: `setTimeout` then hardcoded `healthy_coral` / 0.92
- Open CORS, dev JWT, single SQLite file
- Jobs live on the photo row (one current `jobId` per photo). In-flight jobs are lost if the API process dies
