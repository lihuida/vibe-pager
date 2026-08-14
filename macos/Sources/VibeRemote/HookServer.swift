import Foundation
import Network

final class HookServer {
    private var listener: NWListener?
    private weak var store: AppStore?

    init(store: AppStore) {
        self.store = store
    }

    func start(port: UInt16) {
        stop()
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                let store = self?.store
                Task { @MainActor in
                    switch state {
                    case .ready:
                        store?.serverOk = true
                        store?.serverError = ""
                    case let .failed(error):
                        store?.serverOk = false
                        store?.serverError = "本机接收服务启动失败：\(error.localizedDescription)"
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        } catch {
            let store = self.store
            Task { @MainActor in
                store?.serverOk = false
                store?.serverError = "无法监听 127.0.0.1:\(port)"
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            var next = buffer
            if let data { next.append(data) }
            if let request = HTTPRequest.parse(next) {
                self?.respond(connection, request: request)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self?.receive(connection, buffer: next)
        }
    }

    private func respond(_ connection: NWConnection, request: HTTPRequest) {
        if request.path == "/health" {
            send(connection, status: 200, body: "ok")
            return
        }
        if request.method == "POST", request.path == "/hook" {
            handleHook(request)
            send(connection, status: 204, body: "")
            return
        }
        send(connection, status: 404, body: "not found")
    }

    private func handleHook(_ request: HTTPRequest) {
        let store = self.store
        let source = request.headers["x-vibe-source"] ?? "agent"
        let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        Task { @MainActor in
            await store?.handleIncoming(source: source, body: body)
        }
    }

    private func send(_ connection: NWConnection, status: Int, body: String) {
        let reason = status == 200 ? "OK" : (status == 204 ? "No Content" : "Not Found")
        var header = "HTTP/1.1 \(status) \(reason)\r\nConnection: close\r\n"
        let data = Data(body.utf8)
        if status != 204 {
            header += "Content-Type: text/plain; charset=utf-8\r\nContent-Length: \(data.count)\r\n"
        }
        header += "\r\n"
        var payload = Data(header.utf8)
        payload.append(data)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        guard let headerEnd = raw.range(of: "\r\n\r\n") else { return nil }
        let headerBlob = String(raw[raw.startIndex..<headerEnd.lowerBound])
        let lines = headerBlob.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.first else { return nil }
        let parts = start.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2 {
                headers[pair[0].lowercased()] = pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
        let bodyStart = headerEnd.upperBound
        let bodyData = Data(raw[bodyStart...].utf8)
        if let length = headers["content-length"].flatMap(Int.init), bodyData.count < length {
            return nil
        }
        let path = String(parts[1]).split(separator: "?").first.map(String.init) ?? String(parts[1])
        return HTTPRequest(method: String(parts[0]), path: path, headers: headers, body: bodyData)
    }
}
