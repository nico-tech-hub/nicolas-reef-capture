import Foundation // for Foundation types like String, Int, etc.

/// A response from the photo upload API
struct UploadResponse: Equatable {
    let serverId: String // the server id
    let jobId: String? // the job id
}

/// An error from the photo upload API
enum UploadError: Error {
    case network // the network error
}

/// A protocol for the photo upload API
protocol PhotoUploading: Sendable {
    func uploadPhoto(filePath: String, idempotencyKey: UUID) async throws -> UploadResponse
    let serverId: String
    let jobId: String?
}

/// An error from the photo upload API
enum UploadError: Error {
    case network // the network error
}

/// A protocol for the photo upload API
protocol PhotoUploading: Sendable {
    func uploadPhoto(filePath: String, idempotencyKey: UUID) async throws -> UploadResponse
} // end of PhotoUploading
