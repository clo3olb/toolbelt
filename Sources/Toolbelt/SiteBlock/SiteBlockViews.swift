import SwiftUI

// MARK: - 팝오버

struct SiteBlockPanelSection: View {
    @ObservedObject var blocker: SiteBlocker
    @ObservedObject var model: PanelModel

    var body: some View {
        PanelSection("사이트 차단") {
            Button("사이트·시간표") { model.openMainWindow(.feature(.siteBlock)) }
                .buttonStyle(.link).font(.caption)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if !blocker.helperInstalled {
                    HStack {
                        Text("처음 한 번 도우미 설치가 필요합니다").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("설치") { model.openMainWindow(.feature(.siteBlock)) }.controlSize(.small)
                    }
                } else {
                    Picker("", selection: Binding(get: { blocker.mode }, set: blocker.setMode)) {
                        ForEach(SiteBlocker.Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    SiteBlockStatus(blocker: blocker)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 지금 상태 한 줄: 차단 중 / 허용 / 반영 대기
struct SiteBlockStatus: View {
    @ObservedObject var blocker: SiteBlocker

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.caption)
            Spacer(minLength: 0)
        }
    }

    private var icon: String {
        if !blocker.applied { return "clock.arrow.circlepath" }
        return blocker.isActive ? "hand.raised.fill" : "checkmark.circle"
    }

    private var color: Color {
        if !blocker.applied { return .orange }
        return blocker.isActive ? .red : .secondary
    }

    private var text: String {
        let what = blocker.isActive ? "\(blocker.domains.count)개 사이트 차단 중" : "차단하지 않는 중"
        let why = blocker.mode == .schedule ? " (시간표)" : ""
        return blocker.applied ? what + why : what + why + " — 반영 대기 (몇 초 걸릴 수 있음)"
    }
}

// MARK: - 메인 창 페이지

struct SiteBlockPage: View {
    @ObservedObject var blocker: SiteBlocker
    @State private var draft = ""
    @State private var invalid = false

    var body: some View {
        PageScaffold(title: "사이트 차단", subtitle: "이 Mac의 모든 브라우저와 앱에서 지정한 사이트에 접속하지 못하게 합니다.") {
            Card(title: "상태") {
                if blocker.helperInstalled {
                    Picker("차단", selection: Binding(get: { blocker.mode }, set: blocker.setMode)) {
                        Text("끔").tag(SiteBlocker.Mode.off)
                        Text("항상 차단").tag(SiteBlocker.Mode.always)
                        Text("시간표대로").tag(SiteBlocker.Mode.schedule)
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 360)
                    SiteBlockStatus(blocker: blocker)
                    HStack {
                        Text("차단 도우미가 설치돼 있습니다.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("도우미 제거…", action: blocker.uninstallHelper).controlSize(.small)
                    }
                } else {
                    Text("사이트 차단은 /etc/hosts를 고치므로 처음 한 번 관리자 암호로 작은 도우미를 설치합니다. 그 뒤로는 켜고 끄거나 시간표가 바뀔 때 암호를 묻지 않습니다.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("도우미 설치…", action: blocker.installHelper)
                }
                if let error = blocker.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Card(title: "차단할 사이트") {
                Text(verbatim: "도메인이나 주소를 붙여 넣으세요. www.와 m.도 함께 막습니다. 다른 하위 주소(예: music.youtube.com)는 따로 추가해야 합니다.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(blocker.domains, id: \.self) { domain in
                    HStack {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                        Text(domain).font(.body.monospaced())
                        Spacer()
                        Button { blocker.removeDomain(domain) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("목록에서 빼기")
                    }
                }
                if blocker.domains.isEmpty {
                    Text("아직 차단할 사이트가 없습니다").font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("예: youtube.com", text: $draft).textFieldStyle(.roundedBorder).frame(width: 260)
                        .onSubmit(add)
                    Button("추가", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if invalid { Text("도메인 형식이 아닙니다").font(.caption).foregroundStyle(.red) }
                }
            }

            Card(title: "시간표") {
                Text("'시간표대로'일 때 아래 시간에만 막습니다. 끝나는 시각이 시작보다 이르면 자정을 넘깁니다. 시작과 끝이 같으면 그 요일 하루 종일입니다.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach($blocker.schedules) { $schedule in
                    ScheduleRow(schedule: $schedule) { blocker.schedules.removeAll { $0.id == schedule.id } }
                }
                Button("시간대 추가") {
                    blocker.schedules.append(BlockSchedule(weekdays: [2, 3, 4, 5, 6], start: 9 * 60, end: 18 * 60))
                }
                .controlSize(.small)
            }

            Card(title: "알아두기") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• 이미 열려 있던 페이지는 새로 고칠 때부터 막힙니다. 브라우저가 주소를 기억하고 있으면 1분쯤 걸릴 수 있습니다.")
                    Text("• 브라우저의 '보안 DNS 사용'(DNS over HTTPS)이 켜져 있으면 우회될 수 있습니다. Chrome·Arc: 설정 → 개인정보 및 보안 → 보안.")
                    Text("• 시간표는 Toolbelt가 실행 중일 때 바뀝니다. Toolbelt를 끄면 마지막 상태가 그대로 유지됩니다.")
                }
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { blocker.update() }
    }

    private func add() {
        invalid = !blocker.addDomain(draft)
        if !invalid { draft = "" }
    }
}

/// 시간대 한 줄: 요일 칩 · 시작 · 끝 · 삭제
private struct ScheduleRow: View {
    @Binding var schedule: BlockSchedule
    let onDelete: () -> Void

    /// 월요일부터 (Calendar weekday: 1 = 일요일)
    private static let days: [(weekday: Int, name: String)] = [(2, "월"), (3, "화"), (4, "수"), (5, "목"), (6, "금"), (7, "토"), (1, "일")]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(Self.days, id: \.weekday) { day in
                    let on = schedule.weekdays.contains(day.weekday)
                    Button {
                        if on { schedule.weekdays.remove(day.weekday) } else { schedule.weekdays.insert(day.weekday) }
                    } label: {
                        Text(day.name).font(.caption.weight(.medium)).frame(width: 24, height: 22)
                            .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                            .foregroundStyle(on ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            DatePicker("", selection: time(\.start), displayedComponents: .hourAndMinute).labelsHidden()
            Text("–")
            DatePicker("", selection: time(\.end), displayedComponents: .hourAndMinute).labelsHidden()
            Spacer()
            Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless).help("시간대 삭제")
        }
    }

    /// 분 ↔ 오늘 날짜의 시각
    private func time(_ key: WritableKeyPath<BlockSchedule, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: schedule[keyPath: key] / 60, minute: schedule[keyPath: key] % 60,
                                  second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            schedule[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}
