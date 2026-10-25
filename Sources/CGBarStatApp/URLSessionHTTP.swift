import Foundation
import CGBarStatCore

/// 拒绝 URLSession 自动重定向，避免令牌被送到允许名单以外的主机。
final class RefuseRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct URLSessionHTTP: HTTPSending {
    let session: URLSession

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.transport
        }
        let location = http.value(forHTTPHeaderField: "Location").flatMap { URL(string: $0, relativeTo: request.url)?.absoluteURL }
        return HTTPResponse(statusCode: http.statusCode, data: data, location: location)
    }
}
