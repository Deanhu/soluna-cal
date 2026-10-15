import SwiftUI

/// 首次引导：3 屏（能干什么 / 需要授权 / 完成）
public struct OnboardingView: View {
    public init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        ("calendar", "一眼看清今天", "公历、农历、节气、节日，点开菜单栏就有"),
        ("party.popper", "放假补班早知道", "法定假期连成色带，调休补班灰色标记，还有倒计时"),
        ("gift", "记住农历生日", "爸妈的农历生日录一次，每年自动出现在日历上"),
    ]

    public var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: pages[page].0)
                .font(.system(size: 44)).foregroundStyle(Color.accentColor)
            Text(pages[page].1).font(.title2).fontWeight(.semibold)
            Text(pages[page].2).font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            HStack {
                if page < pages.count - 1 {
                    Button("跳过") { onFinish() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                Button(page < pages.count - 1 ? "下一步" : "开始使用") {
                    if page < pages.count - 1 { page += 1 } else { onFinish() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 420, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
