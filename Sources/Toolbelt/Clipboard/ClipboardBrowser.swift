import AppKit
import SwiftUI

/// 메인 창 "클립보드" 페이지: 왼쪽 기록 목록, 오른쪽 선택한 항목 상세. 설정은 ⚙︎ 시트.
struct ClipboardBrowser: View {
    @ObservedObject var history: ClipboardHistory
    @State private var selectedID: ClipItem.ID?
    @State private var search = ""
    @State private var showSettings = false

    private var filtered: [ClipItem] {
        guard !search.isEmpty else { return history.items }
        return history.items.filter {
            ($0.text ?? $0.preview).localizedCaseInsensitiveContains(search)
                || ($0.source ?? "").localizedCaseInsensitiveContains(search)
                || ($0.label ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    private var selected: ClipItem? { history.items.first { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                List(selection: $selectedID) {
                    ForEach(filtered) { item in
                        ClipListRow(item: item)
                            .tag(item.id)
                            .contextMenu { contextMenu(item) }
                    }
                }
                .onDeleteCommand { if let selected { history.delete(selected) } }
                .overlay {
                    if filtered.isEmpty {
                        Text(history.items.isEmpty ? (history.isEnabled ? "아직 기록이 없습니다" : "클립보드 기록이 꺼져 있습니다")
                                                   : "검색 결과가 없습니다")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)

            Group {
                if let selected {
                    ClipDetailView(item: selected, history: history).id(selected.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 34)).foregroundStyle(.secondary)
                        Text("항목을 선택하세요").foregroundStyle(.secondary)
                        Text("더블클릭하면 바로 복사합니다").font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 380)
        }
        .sheet(isPresented: $showSettings) { ClipboardSettingsSheet(history: history) }
        .onAppear {
            history.refreshAccess()
            if selectedID == nil { selectedID = history.items.first?.id }
        }
    }

    /// 목록 위: 기록 켜기/일시정지, 검색, 설정
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if history.isEnabled {
                    Toggle(isOn: Binding(get: { !history.isPaused }, set: { history.setPaused(!$0) })) {
                        Text(history.isPaused ? "일시정지됨" : "기록 중").font(.callout.weight(.medium))
                    }
                    .toggleStyle(.switch).controlSize(.mini)
                } else {
                    Text("기록 꺼짐").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    Button("켜기") { history.setEnabled(true) }.controlSize(.small)
                }
                Spacer()
                Text("\(history.items.count)개").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("클립보드 설정")
            }
            if !history.accessGranted && history.isEnabled {
                Button { history.requestAccess() } label: {
                    Label("클립보드 접근을 '항상 허용'으로 해 주세요", systemImage: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            if let notice = history.notice {
                Text(notice).font(.caption.weight(.medium)).foregroundStyle(.red)
            }
            TextField("검색", text: $search).textFieldStyle(.roundedBorder)
        }
        .padding(10)
    }

    @ViewBuilder
    private func contextMenu(_ item: ClipItem) -> some View {
        Button("복사") { history.copy(item) }
        if item.isSecret {
            Button("일반으로 바꾸기") { history.markNormal(item) }
        } else {
            Button("비밀로 바꾸기") { history.markSecret(item) }
        }
        Divider()
        Button("삭제", role: .destructive) { history.delete(item) }
    }
}

/// 목록 한 줄 (더블클릭하면 복사)
private struct ClipListRow: View {
    let item: ClipItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isSecret ? "lock.fill" : "text.alignleft")
                .font(.system(size: 12)).foregroundStyle(item.isSecret ? Color.orange : Color.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview).font(item.isSecret ? .body.monospaced() : .body).lineLimit(1)
                Text([item.label, item.source, ClipFormat.relative(item.date)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { ClipboardHistory.shared.copy(item) })
    }
}

/// 오른쪽 상세: 전체 내용(일반) 또는 가린 값 + 인증 후 보기(비밀), 동작 버튼
private struct ClipDetailView: View {
    let item: ClipItem
    @ObservedObject var history: ClipboardHistory
    @State private var revealed: String?
    @State private var confirmDelete = false

    private var content: String? { item.isSecret ? revealed : item.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if item.isSecret { Image(systemName: "lock.fill").foregroundStyle(.orange) }
                        Text(item.isSecret ? (item.label ?? "비밀") : "텍스트").font(.title3.weight(.semibold))
                    }
                    Text(meta).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Button("복사", systemImage: "doc.on.doc") { history.copy(item) }
                    .keyboardShortcut(.return, modifiers: [])
                if item.isSecret {
                    Button("일반으로", systemImage: "lock.open") { history.markNormal(item) }
                        .help("Touch ID/암호 확인 후 일반 항목으로 바꾸고, 다음부터 비밀로 기억하지 않습니다")
                } else {
                    Button("비밀로", systemImage: "lock") { history.markSecret(item) }
                        .help("보안 칩 키로 암호화해 가리고, 같은 값은 다음에도 비밀로 저장합니다")
                }
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                    .help("삭제")
                    .confirmationDialog("이 항목을 삭제할까요?", isPresented: $confirmDelete) {
                        Button("삭제", role: .destructive) { history.delete(item) }
                    }
            }
            .padding(16)
            Divider()

            if let content {
                ScrollView {
                    Text(content)
                        .font(item.isSecret ? .body.monospaced() : .body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                if item.isSecret {
                    Text("30초 뒤 다시 가립니다").font(.caption).foregroundStyle(.red).padding([.horizontal, .bottom], 16)
                }
            } else {
                VStack(spacing: 12) {
                    Text(item.preview).font(.title3.monospaced())
                    Text("비밀 값은 보안 칩 키로 암호화돼 있습니다").foregroundStyle(.secondary)
                    Button("보기 (Touch ID / 암호)", systemImage: "eye") { reveal() }
                    Text("복사 버튼은 확인 후 클립보드로 넣고 \(Int(ClipboardHistory.secretClearDelay))초 뒤 지웁니다")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var meta: String {
        var parts = [ClipFormat.full.string(from: item.date)]
        if let source = item.source { parts.append(source) }
        if let text = item.text { parts.append("\(text.count)자") }
        return parts.joined(separator: " · ")
    }

    private func reveal() {
        Task {
            guard let value = await history.reveal(item) else { return }
            revealed = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { revealed = nil }
        }
    }
}

/// ⚙︎ 시트: 접근 권한, 비밀 처리 설명, 기억한 비밀, 비밀로 취급할 앱, 모두 지우기
private struct ClipboardSettingsSheet: View {
    @ObservedObject var history: ClipboardHistory
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("클립보드 설정").font(.title2.weight(.bold))
                    Card(title: "기록") {
                        Toggle("클립보드 기록", isOn: Binding(get: { history.isEnabled }, set: history.setEnabled)).toggleStyle(.switch)
                        ClipboardPermissionRow(history: history)
                        Text("최근 \(ClipboardHistory.maxItems)개, 7일 동안 이 Mac에만 암호화해 보관합니다. API 키·토큰·개인 키, 비밀번호 관리자나 아래 앱에서 복사한 값은 비밀로 저장합니다: 값은 보안 칩(Secure Enclave) 키로 따로 암호화하고 목록에는 가려서 보여주며, 복사할 때 Touch ID나 Mac 암호를 확인하고 \(Int(ClipboardHistory.secretClearDelay))초 뒤 클립보드에서 지웁니다.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button("기록 모두 지우기", role: .destructive) { confirmClear = true }
                                .disabled(history.items.isEmpty)
                                .confirmationDialog("클립보드 기록과 비밀 항목을 모두 지울까요? (비밀로 기억한 값은 남습니다)", isPresented: $confirmClear) {
                                    Button("모두 지우기", role: .destructive, action: history.clearAll)
                                }
                        }
                    }
                    Card(title: "비밀로 기억한 값") {
                        HStack {
                            Text("\(history.rememberedSecrets.count)개").monospacedDigit()
                            Text("값은 저장하지 않고 되돌릴 수 없는 지문만 보관합니다").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("모두 잊기", action: history.forgetRememberedSecrets).controlSize(.small)
                                .disabled(history.rememberedSecrets.isEmpty)
                        }
                    }
                    Card(title: "비밀로 취급할 앱") {
                        Text("이 앱들에서 복사한 값은 모두 비밀로 저장합니다.").font(.callout).foregroundStyle(.secondary)
                        ForEach(history.excludedApps, id: \.self) { bundleID in
                            HStack {
                                Text(ClipFormat.appName(bundleID))
                                Text(ClipFormat.isInstalled(bundleID) ? bundleID : "설치 안 됨")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                Spacer()
                                Button { history.removeExcludedApp(bundleID) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                            }
                        }
                        Menu("실행 중인 앱 추가") {
                            ForEach(runningApps, id: \.bundleIdentifier) { app in
                                Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                                    if let id = app.bundleIdentifier { history.addExcludedApp(id) }
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("완료") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 620)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && !history.excludedApps.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

enum ClipFormat {
    static let full: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E) HH:mm:ss"
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return ClipboardHistory.knownAppNames[bundleID] ?? bundleID
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
