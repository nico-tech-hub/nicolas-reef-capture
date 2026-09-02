import Foundation // for Foundation types like String, Int, etc.

/// A response from the photo upload API
struct UploadResponse: Equatable {
    let serverId: String // the server id
    let jobId: String? // the job id
}

/// A processing job returned by GET /jobs/:id
struct JobStatus: Equatable, Sendable {
    let jobId: String
    let status: String
    let classification: String?
    let confidence: Double?
}

/// An error from the photo upload API
enum UploadError: Error {
    case network // the network error
}

/// A protocol for the photo upload API
protocol PhotoUploading: Sendable {
    func uploadPhoto(filePath: String, idempotencyKey: UUID) async throws -> UploadResponse
    func fetchJobStatus(jobId: String) async throws -> JobStatus
    func deletePhoto(serverId: String) async throws
} // end of PhotoUploading
