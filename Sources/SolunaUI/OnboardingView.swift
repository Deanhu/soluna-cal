import SwiftUI

/// 首次引导：3 屏（能干什么 / 需要授权 / 完成）
public struct OnboardingView: View {
    public init(initialPage: Int = 0, onFinish: @escaping () -> Void) {
        _page = State(initialValue: initialPage)
        self.onFinish = onFinish
    }
    let onFinish: () -> Void
    @State private var page = 0
    /// 最后一屏的开关：默认关（不擅自替用户决定），但给一次选择的机会
    @State private var birthdayReminder = false

    private let pages: [(String, String, String)] = [
        ("calendar", "一眼看清今天", "公历、农历、节气、节日，点开菜单栏就有"),
        ("party.popper", "放假补班早知道", "法定假期连成色带，调休补班灰色标记，还有倒计时"),
        ("gift", "记住农历生日", "爸妈的农历生日录一次，每年自动出现在日历上"),
        ("bell.badge", "要不要到点提醒你", "生日和节日当天早上 9 点提醒一次，随时可以关"),
    ]

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: pages[page].0)
                .font(.system(size: 44)).foregroundStyle(Color.accentColor)
            Text(pages[page].1).font(.title2).fontWeight(.semibold)
            Text(pages[page].2).font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if page == pages.count - 1 {
                Toggle("生日、节日当天提醒我", isOn: $birthdayReminder)
                    .toggleStyle(.switch)
            }
            Spacer()
            HStack {
                if page < pages.count - 1 {
                    Button("跳过") { onFinish() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                Button(page < pages.count - 1 ? "下一步" : "开始使用") {
                    if page < pages.count - 1 {
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
        .frame(width: 420, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
