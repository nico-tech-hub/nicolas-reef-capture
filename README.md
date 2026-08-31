# ReefCapture

Demo project for Coral Gardeners.

A diver (gardener) captures a reef photo on iPhone and records an observation **while offline**. The photo is stored locally first, then uploaded when the network is back. The API persists it, and a scientist validates it in a web dashboard.

The goal of this project is to propose a **reliable offline architecture**: capture must never depend on connectivity, uploads must be queued, retried, and crash-safe, and the same observation must not be sent twice.

This is **not** a production product. Auth is intentionally hardcoded, classification is mocked, and the iOS app talks to a fake API by default.


## Architecture

```
iOS (SwiftUI)  --upload JPEG -->  NestJS API :3000  <--JWT-->  Vue dashboard :5173
    SwiftData local queue         SQLite + /uploads
```

Offline-first flow:

1. The diver picks a photo in the iOS app. It is copied into the sandbox (`Documents/observations/`) and saved in SwiftData with status `PENDING`. The UI never waits on the network

2. `UploadQueue` drains pending observations one at a time (`POST /photos`) with a JWT and an idempotency key. Interrupted uploads (`UPLOADING` after a crash) are reset to `PENDING` on launch.

3. The API writes the JPEG to disk, creates a SQLite row, and returns a `photoId`. Classification (`healthy_coral`, 92%) is **mocked**.

4. The scientist signs in to the dashboard, sees all photos, and approves or rejects them (optimistic concurrency via `version`).

## Structure

```
ReefCapture/
├── ios/        iPhone app (SwiftUI, SwiftData, iOS 17+)
├── backend/    NestJS API + SQLite
└── web/        Scientist dashboard (Vue 3 + Vite)
```

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

Optional env vars: `DATABASE_PATH`, `UPLOAD_DIR`, `JWT_SECRET` (default `reefcapture-dev-secret`).

### 2. Dashboard

```bash
cd web
npm install
npm run dev
```

Open [http://127.0.0.1:5173](http://127.0.0.1:5173). Vite proxies `/auth` and `/photos` to the API.

Sign in with `scientist@example.com` / `password`.

### 3. iOS app

Open `ios/ReefCapture.xcodeproj` in Xcode and run on the **simulator**.

By default, `ContentView` uses `FakePhotoAPI` (1s delay, no network). To talk to the real API, inject `ReefCaptureAPI()` instead:

```swift
ContentView(api: ReefCaptureAPI())
```

`ReefCaptureAPI` connects to `http://127.0.0.1:3000` as `diver@example.com`. On a physical iPhone, replace that URL with your Mac's LAN IP.

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`ios/project.yml`). After changing sources, regenerate with `xcodegen generate` in `ios/`.

## API

All `/photos` routes require `Authorization: Bearer <token>`.

| Method | Route | Description |
|--------|-------|-------------|
| `POST` | `/auth/login` | `{ email, password }` → `{ accessToken }` |
| `POST` | `/photos` | multipart `file` + `Idempotency-Key` header |
| `GET` | `/photos` | list (filtered by role) |
| `GET` | `/photos/:id/file` | JPEG |
| `POST` | `/photos/:id/validate` | `{ version, approved }` — `409` if the version is stale |
| `POST` | `/photos/:id/retry` | retry processing (mock) |

Upload response:

```json
{ "photoId": "...", "jobId": null, "status": "UPLOADED" }
```

## Statuses

**iOS** (`Observation.displayStatus`), derived from upload + processing:

`PENDING` → `UPLOADING` → `UPLOADED` / `FAILED` (Retry button)

**API / dashboard**:

- `processingStatus`: mocked as `COMPLETED` on upload
- `validationStatus`: `PENDING` → `APPROVED` or `REJECTED`
- `version`: incremented on each validation (conflict if two scientists validate the same version)

## Tests

```bash
# API
cd backend && npm test

# iOS (from the ios folder, or via Xcode)
xcodebuild test -scheme ReefCapture -destination 'platform=iOS Simulator,name=iPhone 16'
```

iOS tests cover the `Observation` model, `PhotoStore`, `UploadQueue`, and API mapping.

## Prototype limits

- Accounts and passwords are plaintext in `backend/src/auth/users.ts`
- No real ML model: classification and confidence are hardcoded
- `Idempotency-Key` is sent but not yet deduplicated on the server
- Open CORS, dev JWT, single SQLite file
- The iOS app is not wired to the real API by default
