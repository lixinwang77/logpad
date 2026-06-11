import Foundation
import Combine

/// Global, shared store for the search-preset groups shown in the left sidebar.
/// A single instance backs every window/tab so edits stay in sync, and the
/// groups are persisted to `UserDefaults` as JSON so they survive relaunches.
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published var groups: [FilterPresetGroup] {
        didSet { persist() }
    }

    /// IDs of groups currently collapsed in the sidebar. Kept separate from the
    /// `FilterPresetGroup` model so adding it doesn't break decoding of presets
    /// saved by older builds. Persisted so the fold state survives relaunches.
    @Published var collapsedGroupIDs: Set<UUID> {
        didSet { persistCollapsed() }
    }

    private static let storageKey = "filterPresetGroups"
    private static let collapsedKey = "collapsedPresetGroupIDs"

    private init() {
        if let data = UserDefaults.standard.data(forKey: PresetStore.storageKey),
           let decoded = try? JSONDecoder().decode([FilterPresetGroup].self, from: data) {
            groups = decoded
        } else {
            groups = []
        }
        if let data = UserDefaults.standard.data(forKey: PresetStore.collapsedKey),
           let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            collapsedGroupIDs = decoded
        } else {
            collapsedGroupIDs = []
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: PresetStore.storageKey)
        }
    }

    private func persistCollapsed() {
        if let data = try? JSONEncoder().encode(collapsedGroupIDs) {
            UserDefaults.standard.set(data, forKey: PresetStore.collapsedKey)
        }
    }

    // MARK: - Collapse state

    func isCollapsed(_ id: UUID) -> Bool {
        collapsedGroupIDs.contains(id)
    }

    func toggleCollapsed(_ id: UUID) {
        if collapsedGroupIDs.contains(id) {
            collapsedGroupIDs.remove(id)
        } else {
            collapsedGroupIDs.insert(id)
        }
    }

    func expand(_ id: UUID) {
        collapsedGroupIDs.remove(id)
    }

    // MARK: - CRUD

    /// True if a group named `name` already exists (case-insensitive, trimmed),
    /// optionally ignoring the group with id `excluding` (used when renaming).
    func groupNameExists(_ name: String, excluding id: UUID? = nil) -> Bool {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return groups.contains {
            $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
        }
    }

    @discardableResult
    func addGroup(name: String) -> FilterPresetGroup {
        let group = FilterPresetGroup(name: name, words: [])
        groups.append(group)
        return group
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].name = name
    }

    func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        collapsedGroupIDs.remove(id)
    }

    func addWord(to groupID: UUID, text: String) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[idx].words.append(FilterPresetWord(text: text))
    }

    func editWord(_ wordID: UUID, in groupID: UUID, to text: String) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }),
              let wIdx = groups[gIdx].words.firstIndex(where: { $0.id == wordID }) else { return }
        groups[gIdx].words[wIdx].text = text
    }

    func deleteWord(_ wordID: UUID, in groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gIdx].words.removeAll { $0.id == wordID }
    }

    func toggleWordEnabled(_ wordID: UUID, in groupID: UUID) {
        guard let gIdx = groups.firstIndex(where: { $0.id == groupID }),
              let wIdx = groups[gIdx].words.firstIndex(where: { $0.id == wordID }) else { return }
        groups[gIdx].words[wIdx].isEnabled.toggle()
    }
}
