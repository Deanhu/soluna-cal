import SwiftUI

/// 首次引导。
///
/// 产品上必须解决一件事：菜单栏 App 装完可能「什么也看不见」——
/// 图标被塞满的菜单栏挤到刘海后面，用户第一反应是「装了没反应」。
/// 所以引导里要提前说清：图标在哪、看不到怎么办、怎么随时唤醒。
public struct OnboardingView: View {
    public init(initialPage: Int = 0,
                hotKeyText: String = "⌥⌘C",
                onFinish: @escaping () -> Void) {
        _page = State(initialValue: initialPage)
        self.hotKeyText = hotKeyText
        self.onFinish = onFinish
    }
    let onFinish: () -> Void
    private let hotKeyText: String
    @State private var page = 0
    /// 最后一屏的开关：默认关（不擅自替用户决定），但给一次选择的机会
    @State private var birthdayReminder = false

    // 计算属性：描述里要带当前快捷键，而存储属性的初始化器里拿不到 self
    private var pages: [(String, String, String)] { [
        ("calendar", "一眼看清今天", "公历、农历、节气、节日，点开菜单栏就有"),
        ("party.popper", "放假补班早知道", "法定假期连成色带，调休补班灰色标记，还有倒计时"),
        ("gift", "记住农历生日", "爸妈的农历生日录一次，每年自动出现在日历上"),
        ("menubar.rectangle", "图标在屏幕右上角",
         "装完不会弹出窗口，只在菜单栏出现一个小图标。\n如果那里已经挤满，图标会被藏到刘海后面——那时会自动弹出窗口，也能随时按 \(hotKeyText) 呼出。"),
    ] }

    /// 最后一屏（提醒开关）单独判定，避免以后加屏时把开关带到别的页上
    private var isLastPage: Bool { page == pages.count }

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: isLastPage ? "bell.badge" : pages[page].0)
                .font(.system(size: 44)).foregroundStyle(Color.accentColor)
            Text(isLastPage ? "要不要到点提醒你" : pages[page].1)
                .font(.title2).fontWeight(.semibold)
            Text(isLastPage ? "生日和节日当天早上 9 点提醒一次，随时可以关" : pages[page].2)
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)

            if isLastPage {
                Toggle("生日、节日当天提醒我", isOn: $birthdayReminder)
                    .toggleStyle(.switch)
            }
            Spacer()
            HStack {
                if !isLastPage {
                    Button("跳过") { onFinish() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                Button(isLastPage ? "开始使用" : "下一步") {
                    if !isLastPage {
                        page += 1
                    } else {
                        // 只在打开时写入，保持「默认关」的语义
                        if birthdayReminder {
                            UserDefaults.standard.set(true, forKey: "notify.birthday")
                            UserDefaults.standard.set(true, forKey: "notify.festival")
                        }
                        onFinish()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 420, height: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
