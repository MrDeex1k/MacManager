import Foundation
import MacManagerCore
import Observation

@MainActor @Observable
final class IslandClipboardModel {
    typealias Request = ClipboardSearchModel.Request
    private let searchState = ClipboardSearchModel()
    let service: ClipboardService
    private(set) var active = false
    var query = "" {
        didSet {
            if query != oldValue {
                searchState.reset()
                action?.cancel(); action = nil; actionID = nil
                confirmation?.cancel(); confirmation = nil; restoringID = nil; copiedID = nil
            }
        }
    }
    var selectedID: UUID?
    private(set) var copiedID: UUID?
    private(set) var restoringID: UUID?
    var searchFailure: ClipboardFailure? { searchState.failure }
    @ObservationIgnored private var action: Task<Void, Never>?
    @ObservationIgnored private var confirmation: Task<Void, Never>?
    @ObservationIgnored private var presentation = 0
    @ObservationIgnored private var actionID: UUID?
    var hasPendingWork: Bool { searchState.hasPendingWork || action != nil || confirmation != nil }

    func activate() { reset(); active = true; reconcileSelection() }

    init(service: ClipboardService) { self.service = service }
    var request: Request { Request(query: query, service: service) }
    var searching: Bool { !query.isEmpty && searchState.completed != request && !service.suspended }
    var entries: [ClipboardEntry] {
        guard active, !service.suspended else { return [] }
        return searchState.entries(for: request, service: service)
    }

    func search(_ request: Request) async {
        guard active, !Task.isCancelled, request == self.request else { return }
        guard !request.suspended else { reset(); return }
        guard !request.query.isEmpty else { searchState.reset(); reconcileSelection(); return }
        _ = try? await searchState.search(request, service: service, limit: 50)
        guard active, request == self.request, !Task.isCancelled else { return }
        reconcileSelection()
    }
    func reconcileSelection() {
        if !entries.contains(where: { $0.id == selectedID }) { selectedID = entries.first?.id }
    }
    func move(_ delta: Int) {
        guard !entries.isEmpty else { selectedID = nil; return }
        let current = entries.firstIndex { $0.id == selectedID } ?? 0
        selectedID = entries[min(max(current + delta, 0), entries.count - 1)].id
    }
    func restoreSelected() { if let selectedID { restore(selectedID) } }
    func restore(_ id: UUID) {
        guard active, restoringID == nil, !searching, !service.suspended,
              entries.contains(where: { $0.id == id && !$0.damaged }) else { return }
        action?.cancel(); confirmation?.cancel(); copiedID = nil; restoringID = id
        let identifier = UUID(); actionID = identifier
        action = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let token = self.presentation
            defer { if self.actionID == identifier { self.action = nil; self.actionID = nil } }
            let succeeded = await self.service.restore(id)
            guard self.active, token == self.presentation, !Task.isCancelled, !self.service.suspended else { return }
            self.restoringID = nil
            guard succeeded, self.service.restoredID == id else { return }
            self.copiedID = id
            self.confirmation = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, self?.presentation == token else { return }
                self?.copiedID = nil
                self?.confirmation = nil
            }
        }
    }
    func delete(_ id: UUID) {
        guard active, !searching, !service.suspended, entries.contains(where: { $0.id == id }) else { return }
        Task { await service.delete(id) }
    }
    func toggleCapture() {
        guard active else { return }
        var value = service.preferences
        if value.enabled { value.paused.toggle() }
        else { value.enabled = true; value.paused = false }
        Task { await service.updatePreferences(value) }
    }
    func reset() {
        active = false; presentation += 1
        searchState.reset()
        actionID = nil
        action?.cancel(); action = nil; confirmation?.cancel(); confirmation = nil
        query = ""
        selectedID = nil; copiedID = nil; restoringID = nil
    }
}
