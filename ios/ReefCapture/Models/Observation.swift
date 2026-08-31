import Foundation  // provides the Foundation framework for the app
import SwiftData // provides the SwiftData framework for the app

/// Enum for the upload status of the observation
/// did the picture get uploaded to the server?
enum UploadStatus: String, Codable {
    case pending
    case uploading
    case uploaded
    case failed
}

/// Enum for the processing status of the observation
/// is the picture being processed by the server?
enum ProcessingStatus: String, Codable {
    case none
    case processing
    case completed
    case failed
}

/// Model for the observation, using SwiftData
@Model
final class Observation { // final class for the observation, avoiding inheritance
    var id: UUID
    var localFilePath: String
    var createdAt: Date
    var uploadStatus: UploadStatus
    var processingStatus: ProcessingStatus
    var retryCount: Int
    var serverId: String?
    var jobId: String?
    var version: Int
    var idempotencyKey: UUID

    init(id: UUID = UUID(), localFilePath: String = "") { // initializer for the observation
        self.id = id
        self.localFilePath = localFilePath
        self.createdAt = Date()
        self.uploadStatus = .pending
        self.processingStatus = .none
        self.retryCount = 0
        self.serverId = nil
        self.jobId = nil
        self.version = 1
        self.idempotencyKey = UUID()
    }

    /// Combined status shown in the UI.
    /// Derived from upload + processing, not stored separately.
    var displayStatus: String {
        switch (uploadStatus, processingStatus) {
        case (.pending, _):
            return "PENDING"
        case (.uploading, _):
            return "UPLOADING"
        case (.failed, _):
            return "FAILED"
        case (.uploaded, .none):
            return "UPLOADED"
        case (.uploaded, .processing):
            return "PROCESSING"
        case (.uploaded, .completed):
            return "COMPLETED"
        case (.uploaded, .failed):
            return "FAILED"
        }
    }
}
