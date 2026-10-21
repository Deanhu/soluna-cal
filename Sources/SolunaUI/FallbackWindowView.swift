import SwiftUI
import LunarCore

/// 菜单栏没位置时的兜底窗口。
///
/// 刘海屏 Mac 的菜单栏一旦塞满，系统会把多出来的状态项藏到刘海后面——
/// 图标不显示、也没有任何提示。新用户装完看不到东西，只会以为「装了没反应」。
/// 这个窗口提供两件事：说明原因 + 一个能用的日历界面。
public struct FallbackWindowView: View {
    let store: BirthdayStore
    let hotKeyText: String
    let onRequestSettings: (() -> Void)?
    let onRequestYear: (() -> Void)?
    let onEditEvent: ((Date) -> Void)?
    let onOpenYiji: ((Date) -> Void)?
    let onClose: () -> Void

    public init(store: BirthdayStore, hotKeyText: String,
                onRequestSettings: (() -> Void)? = nil,
                onRequestYear: (() -> Void)? = nil,
                onEditEvent: ((Date) -> Void)? = nil,
                onOpenYiji: ((Date) -> Void)? = nil,
                onClose: @escaping () -> Void) {
        self.store = store
        self.hotKeyText = hotKeyText
        self.onRequestSettings = onRequestSettings
        self.onRequestYear = onRequestYear
        self.onEditEvent = onEditEvent
        self.onOpenYiji = onOpenYiji
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            banner
            Divider()
            calendar
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 橙色横幅：说清「为什么看不到图标」和「现在能怎么办」
    private var banner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("菜单栏没有位置了")
                    .font(.system(size: 12, weight: .semibold))
                Text("SolunaCal 的图标被挤到刘海后面，所以你看不到它。\n按住 ⌘ 把不用的菜单栏图标拖走，图标就会露出来；也可以随时按 \(hotKeyText) 呼出这个面板。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("知道了") { onClose() }
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.adaptive(light: 0xFFF4E5, dark: 0x3A2E1C))
    }

    /// 内嵌日历：四条弹窗入口全部透传，兜底窗口和弹窗行为一致
    private var calendar: some View {
        var popover = CalendarPopoverView(store: store, fixedHeight: false)
        popover.onOpenSettings = onRequestSettings
        // 兜底窗口没有「当前浏览月份」的概念，年视图按今天所在年份打开
        popover.onOpenYear = { _ in onRequestYear?() }
        popover.onEditEvent = onEditEvent
        popover.onOpenYiji = onOpenYiji
        return popover
            .frame(maxWidth: .infinity)
    }
}
