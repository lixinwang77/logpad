import SwiftUI

/// Left sidebar listing named groups of preset filter words. Clicking a group
/// applies all its words at once (joined with `|`); clicking a single word
/// applies just that word. Groups and words are edited inline here and stored
/// globally via `PresetStore.shared`.
struct PresetSidebarView: View {
    @ObservedObject var store: PresetStore
    let onApplyGroup: (FilterPresetGroup) -> Void
    let onApplyWord: (String) -> Void

    @ObservedObject private var langManager = LanguageManager.shared
    @State private var addingGroup = false
    @State private var newGroupText = ""
    @State private var showDuplicateAlert = false
    @FocusState private var newGroupFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.groups.isEmpty && !addingGroup {
                Spacer()
                Text(i18n.str("noPresetsHint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if addingGroup {
                            TextField(i18n.str("newGroupNamePlaceholder"), text: $newGroupText)
                                .textFieldStyle(.roundedBorder)
                                .focused($newGroupFocused)
                                .onSubmit(commitNewGroup)
                                .onChange(of: newGroupFocused) { _, focused in
                                    if !focused { commitNewGroup() }
                                }
                                .padding(.horizontal, 8)
                                .padding(.top, 6)
                        }
                        ForEach(store.groups) { group in
                            PresetGroupView(
                                group: group,
                                store: store,
                                onApplyGroup: onApplyGroup,
                                onApplyWord: onApplyWord
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 160, idealWidth: 220, maxWidth: 400)
        .background(Color(nsColor: .controlBackgroundColor))
        // Tapping empty sidebar space has no control to take first responder, so
        // an open inline field would keep focus. Resign it explicitly so the
        // field commits and dismisses, matching a click in the main log view.
        .contentShape(Rectangle())
        .onTapGesture { resignInlineEditing() }
        .alert(i18n.str("duplicateGroupName"), isPresented: $showDuplicateAlert) {
            Button(i18n.str("OK"), role: .cancel) {}
        }
    }

    private func resignInlineEditing() {
        if newGroupFocused { newGroupFocused = false }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private var header: some View {
        HStack {
            Text(i18n.str("presetsTitle"))
                .font(.headline)
            Spacer()
            Button {
                addingGroup = true
                newGroupText = ""
                DispatchQueue.main.async { newGroupFocused = true }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(i18n.str("addGroup"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func commitNewGroup() {
        let name = newGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { addingGroup = false; newGroupText = ""; return }
        // Keep the field open and warn on a duplicate name.
        if store.groupNameExists(name) {
            showDuplicateAlert = true
            return
        }
        store.addGroup(name: name)
        addingGroup = false
        newGroupText = ""
    }
}

/// A single preset group: an applyable header (group name) plus its words, with
/// inline rename / add-word / edit-word / delete affordances revealed on hover.
private struct PresetGroupView: View {
    let group: FilterPresetGroup
    @ObservedObject var store: PresetStore
    let onApplyGroup: (FilterPresetGroup) -> Void
    let onApplyWord: (String) -> Void

    private enum Field: Hashable {
        case rename
        case addWord
        case editWord(UUID)
    }

    @State private var hovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isAddingWord = false
    @State private var newWordText = ""
    @State private var editingWordID: UUID?
    @State private var editWordText = ""
    @State private var showDeleteConfirm = false
    @State private var showDuplicateAlert = false
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            groupHeader
            if !store.isCollapsed(group.id) {
                ForEach(group.words) { word in
                    wordRow(word)
                }
            }
            if isAddingWord {
                TextField(i18n.str("newWordPlaceholder"), text: $newWordText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .addWord)
                    .onSubmit(commitNewWord)
                    .padding(.leading, 18)
                    .padding(.trailing, 8)
            }
        }
        .padding(.vertical, 2)
        // Make the whole group rectangle (including transparent gaps between the
        // name and the trailing icons) hoverable, so moving the cursor toward
        // the icons doesn't drop `hovered` and hide them.
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        // Clicking elsewhere resigns the inline editor's focus; commit (or
        // cancel when empty) so the highlighted field doesn't linger.
        .onChange(of: focusedField) { _, newValue in
            guard newValue == nil else { return }
            if isRenaming {
                commitRename()
            } else if isAddingWord {
                commitNewWord()
            } else if let id = editingWordID,
                      let word = group.words.first(where: { $0.id == id }) {
                commitEditWord(word)
            }
        }
        .alert(i18n.str("deleteGroupConfirm"), isPresented: $showDeleteConfirm) {
            Button(i18n.str("delete"), role: .destructive) { store.deleteGroup(group.id) }
            Button(i18n.str("Cancel"), role: .cancel) {}
        }
        .alert(i18n.str("duplicateGroupName"), isPresented: $showDuplicateAlert) {
            Button(i18n.str("OK"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var groupHeader: some View {
        if isRenaming {
            TextField(i18n.str("newGroupNamePlaceholder"), text: $renameText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .rename)
                .onSubmit(commitRename)
                .padding(.horizontal, 8)
        } else {
            HStack(spacing: 4) {
                if group.words.isEmpty {
                    // Keep names aligned with groups that show a disclosure arrow.
                    Spacer().frame(width: 12)
                } else {
                    Button { store.toggleCollapsed(group.id) } label: {
                        Image(systemName: store.isCollapsed(group.id) ? "chevron.right" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(i18n.str(store.isCollapsed(group.id) ? "expandGroup" : "collapseGroup"))
                }

                Button(action: { onApplyGroup(group) }) {
                    Text(group.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(i18n.str("applyGroupHint"))

                HStack(spacing: 2) {
                    iconButton("square.and.pencil", help: i18n.str("rename")) {
                        renameText = group.name
                        isRenaming = true
                        focusField(.rename)
                    }
                    iconButton("plus", help: i18n.str("addWord")) {
                        store.expand(group.id)
                        newWordText = ""
                        isAddingWord = true
                        focusField(.addWord)
                    }
                    iconButton("trash", help: i18n.str("delete")) {
                        showDeleteConfirm = true
                    }
                }
                .opacity(hovered ? 1 : 0)
            }
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func wordRow(_ word: FilterPresetWord) -> some View {
        if editingWordID == word.id {
            TextField(i18n.str("newWordPlaceholder"), text: $editWordText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .editWord(word.id))
                .onSubmit { commitEditWord(word) }
                .padding(.leading, 18)
                .padding(.trailing, 8)
        } else {
            HStack(spacing: 4) {
                Button(action: { onApplyWord(word.text) }) {
                    Text(word.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 2) {
                    iconButton("square.and.pencil", help: i18n.str("rename")) {
                        editWordText = word.text
                        editingWordID = word.id
                        focusField(.editWord(word.id))
                    }
                    iconButton("trash", help: i18n.str("delete")) {
                        store.deleteWord(word.id, in: group.id)
                    }
                }
                .opacity(hovered ? 1 : 0)
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func focusField(_ field: Field) {
        DispatchQueue.main.async { focusedField = field }
    }

    private func commitRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { isRenaming = false; return }
        // Keep editing and warn if the name collides with another group.
        if store.groupNameExists(name, excluding: group.id) {
            showDuplicateAlert = true
            return
        }
        store.renameGroup(group.id, to: name)
        isRenaming = false
    }

    private func commitNewWord() {
        let text = newWordText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            store.addWord(to: group.id, text: text)
        }
        isAddingWord = false
        newWordText = ""
    }

    private func commitEditWord(_ word: FilterPresetWord) {
        let text = editWordText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            store.editWord(word.id, in: group.id, to: text)
        }
        editingWordID = nil
    }
}
