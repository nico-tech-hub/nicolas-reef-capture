import Foundation // for Foundation types like String, Int, etc.

/// A Data Transfer Object (DTO) for the photo upload response from the NestJS API
struct PhotoUploadDTO: Decodable {
    let photoId: String // the photo id
    let jobId: String? // the job id
    let status: String // the status
}

/// A mapper for the photo upload response from the NestJS API
enum PhotoAPIMapper {
    /// maps the data to the upload response
    static func uploadResponse(from data: Data) throws -> UploadResponse {
        let dto = try JSONDecoder().decode(PhotoUploadDTO.self, from: data)
        return UploadResponse(serverId: dto.photoId, jobId: dto.jobId)
    }
}

/// The ReefCaptureAPI is the API for the app, using the NestJS API
final class ReefCaptureAPI: PhotoUploading {
    
    private let baseURL: URL
    private let email: String
    private let password: String
    private let session: URLSession
    private var accessToken: String?

    /// initializes the API with the base URL, email, password, and session
    init(
        baseURL: URL = URL(string: "http://127.0.0.1:3000")!,
        email: String = "diver@example.com",
        password: String = "password",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.email = email
        self.password = password
        self.session = session
    }

    /// uploads the photo to the API
    func uploadPhoto(filePath: String, idempotencyKey: UUID) async throws -> UploadResponse {
        let token = try await validToken()
        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let boundary = UUID().uuidString

        var request = URLRequest(url: baseURL.appendingPathComponent("photos"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            fieldName: "file",
            fileName: "\(idempotencyKey.uuidString).jpg",
            fileData: fileData,
            boundary: boundary
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UploadError.network
        }
        return try PhotoAPIMapper.uploadResponse(from: data)
    }

    /// gets the valid token for the API
    private func validToken() async throws -> String {
        if let existing = accessToken {
            return existing
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UploadError.network
        }

        let payload = try JSONDecoder().decode(LoginDTO.self, from: data)
        accessToken = payload.accessToken
        return payload.accessToken
    }

    /// A DTO for the login response from the NestJS API
    private struct LoginDTO: Decodable {
        let accessToken: String
    }

    /// creates the multipart body for the photo upload request
    private static func multipartBody(fieldName: String, fileName: String, fileData: Data, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!) // add the boundary
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!) // add the field name and file name
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!) // add the content type
        body.append(fileData) // add the file data
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!) // add the boundary
        return body
    }
} // end of ReefCaptureAPI
