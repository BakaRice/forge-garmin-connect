// Forge — 中文文案位图渲染脚本
// 用 macOS 系统字体 (PingFang SC) 把 UI 文案渲染成 PNG,
// 打包进 resources/drawables/ 作为 CIQ 位图资源。
// 背景: FR255 无矢量字体 API, Garmin 中文字体 > 1MB 超出 512KiB 内存上限,
// 故采用"渲染好的位图文案"方案 (docs/update.md §15 相关约束)。
// 运行: swift tools/render_labels.swift

import AppKit

let outDir = "resources/drawables"

// (文件名, 文案, 字号, 字重, 颜色)
let labels: [(String, String, CGFloat, NSFont.Weight, NSColor)] = [
    ("label_start",     "开始",     48, .semibold, .white),
    ("label_stop",      "停止",     48, .semibold, .white),
    ("label_save",      "保存",     48, .semibold, .white),
    ("label_done",      "完成",     30, .medium,   .white),
    ("label_saved",     "已保存",   34, .semibold, .white),
    ("label_avg_hr",    "平均心率", 22, .regular,  .white),
    ("label_max_hr",    "最大心率", 22, .regular,  .white),
    ("label_err_start", "开始失败", 16, .regular,  NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 1.0)),
    ("label_err_stop",  "停止失败", 16, .regular,  NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 1.0)),
    ("label_err_save",  "保存失败", 16, .regular,  NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 1.0)),
    ("label_err_discard", "放弃失败", 16, .regular, NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 1.0)),
]

func render(name: String, text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: text, attributes: attrs)
    let bounds = str.size()
    let pad: CGFloat = 8
    let w = Int(ceil(bounds.width + pad * 2))
    let h = Int(ceil(bounds.height + pad * 2))

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        print("ERROR: cannot create bitmap for \(name)")
        return
    }
    rep.size = NSSize(width: w, height: h)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    str.draw(at: NSPoint(x: pad, y: pad))
    NSGraphicsContext.restoreGraphicsState()

    if let data = rep.representation(using: .png, properties: [:]) {
        let path = "\(outDir)/\(name).png"
        try? data.write(to: URL(fileURLWithPath: path))
        print("\(path): \(w)x\(h), \(data.count) bytes")
    }
}

for (name, text, size, weight, color) in labels {
    render(name: name, text: text, size: size, weight: weight, color: color)
}
