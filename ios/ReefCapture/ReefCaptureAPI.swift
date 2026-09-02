import Foundation // for Foundation types like String, Int, etc.

/// A Data Transfer Object (DTO) for the photo upload response from the NestJS API
struct PhotoUploadDTO: Decodable {
    let photoId: String // the photo id
    let jobId: String? // the job id
    let status: String // the status
}

/// A DTO for GET /jobs/:id
struct JobStatusDTO: Decodable {
    let jobId: String
    let photoId: String
    let status: String
    let classification: String?
    let confidence: Double?
}

/// A mapper for the photo upload response from the NestJS API
enum PhotoAPIMapper {
    /// maps the data to the upload response
    static func uploadResponse(from data: Data) throws -> UploadResponse {
        let dto = try JSONDecoder().decode(PhotoUploadDTO.self, from: data) // decode the JSON data to the PhotoUploadDTO
        return UploadResponse(serverId: dto.photoId, jobId: dto.jobId) // return the UploadResponse, with the server id and the job id
    }

    /// maps the data to a processing job
    static func jobStatus(from data: Data) throws -> JobStatus {
        let dto = try JSONDecoder().decode(JobStatusDTO.self, from: data)
        return JobStatus(
            jobId: dto.jobId,
            status: dto.status,
            classification: dto.classification,
            confidence: dto.confidence
        )
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
        let token = try await validToken() // get the valid token for the API
        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath)) // get the file data from the file path
        let boundary = UUID().uuidString // get the boundary for the multipart body

        var request = URLRequest(url: baseURL.appendingPathComponent("photos")) // create the request URL
        request.httpMethod = "POST" // set the HTTP method to POST
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") // set the authorization header for the request
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key") // set the idempotency key for the request
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type") // set the content type for the request
        request.httpBody = Self.multipartBody( // create the multipart body for the request
            fieldName: "file", // set the field name for the request
            fileName: "\(idempotencyKey.uuidString).jpg", // set the file name for the request
            fileData: fileData, // set the file data for the request
            boundary: boundary // set the boundary for the request
        )

        let (data, response) = try await session.data(for: request) // send the request and get the response
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { // check if the response is successful
            throw UploadError.network // throw an error if the response is not successful
        }
        return try PhotoAPIMapper.uploadResponse(from: data) // return the upload response
    }

    /// polls a processing job
    func fetchJobStatus(jobId: String) async throws -> JobStatus {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("jobs").appendingPathComponent(jobId))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UploadError.network
        }
        return try PhotoAPIMapper.jobStatus(from: data)
    }

    /// Deletes a photo on the server. HTTP 404 is treated as success (already gone).
    func deletePhoto(serverId: String) async throws {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("photos").appendingPathComponent(serverId))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UploadError.network
        }
        if http.statusCode == 404 {
            return
        }
        guard (200...299).contains(http.statusCode) else {
            throw UploadError.network
        }
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
