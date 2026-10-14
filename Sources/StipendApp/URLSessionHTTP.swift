import Foundation
import StipendCore

/// 拒绝重定向，避免令牌被送到 api2.cursor.sh 以外的主机。
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
        return HTTPResponse(statusCode: http.statusCode, data: data)
    }
}
