import Foundation // for Foundation types like String, Int, etc.

/// Mocks the NestJS API
/// The 1-second delay is intentional: to see UPLOADING in the UI.
struct FakePhotoAPI: PhotoUploading {
    let delayNanoseconds: UInt64 // the delay in nanoseconds

    /// initializes the API with the delay in nanoseconds
    init(delayNanoseconds: UInt64 = 1_000_000_000) { // 1 second delay
        self.delayNanoseconds = delayNanoseconds
    }

    /// uploads the photo to the API
    func uploadPhoto(filePath: String, idempotencyKey: UUID) async throws -> UploadResponse {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let prefix = String(idempotencyKey.uuidString.prefix(8))
        return UploadResponse(
            serverId: "srv-\(prefix)",
            jobId: "job-\(prefix)"
        )
    }

    /// Preview/tests skip the 5s fake AI delay and complete immediately.
    func fetchJobStatus(jobId: String) async throws -> JobStatus {
        JobStatus(
            jobId: jobId,
            status: "COMPLETED",
            classification: "healthy_coral",
            confidence: 0.92
        )
    }

    /// Preview/tests: remote delete is a no-op success.
    func deletePhoto(serverId: String) async throws {}
}
