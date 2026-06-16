import Foundation

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // URLSession converts httpBody to httpBodyStream; reconstruct it here so tests can inspect it.
        var mutableRequest = request
        if mutableRequest.httpBody == nil, let stream = mutableRequest.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: bufferSize)
                if count > 0 { data.append(&buffer, count: count) }
            }
            stream.close()
            mutableRequest.httpBody = data
        }
        Self.lastRequest = mutableRequest

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        // Pass the mutableRequest (with httpBody reconstructed) to the handler.
        do {
            let (response, data) = try handler(mutableRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
