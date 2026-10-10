// LAN transport — Network.framework TCP (Nagle off) plus Bonjour for finding
// games on the local network. Frames are parsed on the connection's queue and
// handed to the game through a locked inbox; the game drains it on the main
// thread once per tick, so all game state stays main-thread only.

import Foundation
import Network

/// one decoded frame (plus anything pre-built off-main, e.g. a lit chunk)
struct NetFrame {
    let type: NetMsg
    let body: [UInt8]
    var built: Any? = nil
}

/// thread-safe FIFO between a connection queue and the main thread
final class NetInbox {
    private let lock = NSLock()
    private var items: [(Int, NetFrame)] = []

    func push(_ conn: Int, _ f: NetFrame) {
        lock.lock(); items.append((conn, f)); lock.unlock()
    }
    func drain() -> [(Int, NetFrame)] {
        lock.lock(); defer { lock.unlock() }
        let out = items
        items.removeAll(keepingCapacity: true)
        return out
    }
}

private func tcpParams() -> NWParameters {
    let tcp = NWProtocolTCP.Options()
    tcp.noDelay = true
    tcp.enableKeepalive = true
    tcp.keepaliveIdle = 10
    let p = NWParameters(tls: nil, tcp: tcp)
    p.allowLocalEndpointReuse = true
    return p
}

private var nextConnId = 1

/// one framed TCP connection
final class NetConn {
    let id: Int
    let conn: NWConnection
    private let queue: DispatchQueue
    private var buf = [UInt8]()
    private var closed = false
    private let lock = NSLock()
    private var _queued = 0
    /// frame handler, called on the connection queue (may pre-build heavy data)
    var onFrame: ((NetFrame) -> Void)?
    /// called once, on the connection queue
    var onClose: ((String) -> Void)?
    var onReady: (() -> Void)?

    /// bytes handed to send() that the OS hasn't taken yet — throttles bulk data
    var queuedBytes: Int { lock.lock(); defer { lock.unlock() }; return _queued }

    init(_ c: NWConnection) {
        id = nextConnId
        nextConnId += 1
        conn = c
        queue = DispatchQueue(label: "pebble.net.\(id)")
    }
    convenience init(host: String, port: UInt16) {
        self.init(NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: tcpParams()))
    }
    convenience init(endpoint: NWEndpoint) {
        self.init(NWConnection(to: endpoint, using: tcpParams()))
    }

    func start() {
        conn.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready: self.onReady?()
            case .failed(let e): self.finish("connection failed: \(e.localizedDescription)")
            case .waiting(let e): self.finish("can't reach host: \(e.localizedDescription)")
            case .cancelled: self.finish("disconnected")
            default: break
            }
        }
        conn.start(queue: queue)
        receive()
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buf.append(contentsOf: data)
                if !self.parse() { self.finish("bad data from peer"); return }
            }
            if let err { self.finish(err.localizedDescription); return }
            if done { self.finish("connection closed"); return }
            self.receive()
        }
    }

    /// peel complete frames off the buffer; false on a corrupt stream
    private func parse() -> Bool {
        var off = 0
        while buf.count - off >= 5 {
            let len = Int(buf[off]) | Int(buf[off + 1]) << 8 | Int(buf[off + 2]) << 16 | Int(buf[off + 3]) << 24
            if len < 1 || len > NET_MAX_FRAME { return false }
            if buf.count - off - 4 < len { break }
            let typeByte = buf[off + 4]
            let body = Array(buf[(off + 5)..<(off + 4 + len)])
            off += 4 + len
            guard let type = NetMsg(rawValue: typeByte) else { continue } // newer peer: skip unknown
            onFrame?(NetFrame(type: type, body: body))
        }
        if off > 0 { buf.removeFirst(off) }
        return true
    }

    func send(_ frame: Data) {
        if frame.isEmpty { return }
        lock.lock(); _queued += frame.count; lock.unlock()
        conn.send(content: frame, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self._queued -= frame.count; self.lock.unlock()
        })
    }

    func close() {
        conn.cancel()
    }

    private func finish(_ why: String) {
        if closed { return }
        closed = true
        conn.cancel()
        onClose?(why)
    }
}

/// accepts guests and advertises the game over Bonjour
final class NetListener {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "pebble.net.listen")
    let port: UInt16

    /// tries `port` and the next few if it's taken
    init(port: UInt16, name: String, onConn: @escaping (NWConnection) -> Void) throws {
        var lastErr: Error = NetError.badFrame
        for p in port..<(port + 10) {
            do {
                let l = try NWListener(using: tcpParams(), on: NWEndpoint.Port(rawValue: p)!)
                // Bonjour instance names are capped at 63 bytes
                var short = name
                while short.utf8.count > 63 { short.removeLast() }
                l.service = NWListener.Service(name: short, type: NET_SERVICE_TYPE)
                l.newConnectionHandler = onConn
                l.stateUpdateHandler = { st in
                    if case .failed(let e) = st { print("[net] listener failed: \(e)") }
                }
                l.start(queue: queue)
                listener = l
                self.port = p
                return
            } catch {
                lastErr = error
            }
        }
        throw lastErr
    }

    func stop() { listener.cancel() }
}

/// a game found on the local network
public struct LANGame {
    public let name: String
    let endpoint: NWEndpoint
}

/// browses Bonjour for Pebble games; `games` updates on the main thread
public final class LANBrowser {
    private let browser: NWBrowser
    public private(set) var games: [LANGame] = []

    public init() {
        browser = NWBrowser(for: .bonjour(type: NET_SERVICE_TYPE, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found: [LANGame] = results.compactMap { r in
                if case .service(let name, _, _, _) = r.endpoint { return LANGame(name: name, endpoint: r.endpoint) }
                return nil
            }.sorted { $0.name < $1.name }
            DispatchQueue.main.async { self?.games = found }
        }
        browser.start(queue: DispatchQueue(label: "pebble.net.browse"))
    }

    deinit { browser.cancel() }
    public func stop() { browser.cancel() }
}

/// this Mac's LAN IPv4 addresses (for "tell your friend to connect to…")
public func localIPv4Addresses() -> [String] {
    var out: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
    defer { freeifaddrs(ifaddr) }
    var p: UnsafeMutablePointer<ifaddrs>? = first
    while let cur = p {
        let flags = Int32(cur.pointee.ifa_flags)
        if let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
           flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 {
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let s = String(cString: host)
                if !s.hasPrefix("169.254") { out.append(s) }
            }
        }
        p = cur.pointee.ifa_next
    }
    return out
}
