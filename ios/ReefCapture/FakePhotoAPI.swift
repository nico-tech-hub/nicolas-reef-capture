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
        return UploadResponse(  // return the upload response
            serverId: "srv-\(String(idempotencyKey.uuidString.prefix(8)))", // the server id is a prefix of the idempotency key
            jobId: nil
        )
    }
}
