import Foundation
import Observation

/// Per-surface search state. Services/storage are shared; query results never cross surfaces.
@MainActor @Observable public final class ClipboardSearchModel {
    public struct Request: Hashable, Sendable {
        public let query: String
        public let revision: Int
        public let suspended: Bool
        @MainActor public init(query: String, service: ClipboardService) {
            self.query = query; revision = service.revision; suspended = service.suspended
        }
    }
    public private(set) var matches: [ClipboardEntry] = []
    public private(set) var completed: Request?
    public private(set) var failure: ClipboardFailure?
    @ObservationIgnored private var task: Task<[ClipboardEntry], Error>?
    @ObservationIgnored private var generation = 0
    public var hasPendingWork: Bool { task != nil }
    public init() {}

    public func entries(for request: Request, service: ClipboardService) -> [ClipboardEntry] {
        guard !service.suspended else { return [] }
        return request.query.isEmpty ? service.entries : completed == request ? matches : []
    }

    @discardableResult public func search(_ request: Request, service: ClipboardService, limit: Int = 1_000) async throws -> [ClipboardEntry] {
        guard !Task.isCancelled, !request.suspended, request == Request(query: request.query, service: service) else { throw CancellationError() }
        reset()
        let token = generation
        let operation = Task { try await service.search(request.query, limit: limit) }
        task = operation
        defer { if token == generation { task = nil } }
        do {
            let result = try await withTaskCancellationHandler { try await operation.value } onCancel: { operation.cancel() }
            try Task.checkCancellation()
            guard token == generation, request == Request(query: request.query, service: service) else { throw CancellationError() }
            matches = result; completed = request
            return result
        } catch {
            if !(error is CancellationError), !Task.isCancelled, token == generation,
               request == Request(query: request.query, service: service) {
                failure = error as? ClipboardFailure ?? .storage; completed = request
            }
            throw error
        }
    }

    public func reset() {
        generation += 1; task?.cancel(); task = nil
        matches = []; completed = nil; failure = nil
    }
}
