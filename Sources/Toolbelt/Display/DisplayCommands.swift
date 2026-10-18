import Carbon.HIToolbox

enum DisplayCommands {
    /// 비상 복구 단축키. 화면이 안 보여도 누를 수 있도록 메뉴와 별개로 항상 등록한다.
    static let reconnectAll = Command(
        title: "모든 디스플레이 다시 연결",
        hotKey: HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: HotKey.controlOptionCommand),
        run: { DisplayManager.reconnectAll() }
    )
}
