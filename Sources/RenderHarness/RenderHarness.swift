import AppKit
import SwiftUI
import SolunaUI

/// 离屏渲染 harness：把弹窗视图绘成 PNG，用于无头自查。
/// 用法: RenderHarness <输出.png>
@main
enum RenderHarnessMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let view = CalendarPopoverView(store: BirthdayStore())
        let hosting = NSHostingView(rootView: view)
        // --dark：强制深色外观，用于深色模式自查
        if CommandLine.arguments.contains("--dark") {
            hosting.appearance = NSAppearance(named: .darkAqua)
        }
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 430)
        hosting.layoutSubtreeIfNeeded()

        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fatalError("bitmapImageRepForCachingDisplay failed")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("png encoding failed")
        }
        let out = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "soluna_preview.png"
        try! png.write(to: URL(fileURLWithPath: out))
        print("written:", out, Int(size.width), "x", Int(size.height))
        exit(0)
    }
}
