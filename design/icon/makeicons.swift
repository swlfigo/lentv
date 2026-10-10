// 从一张方形构图生成三个平台的 App 图标，写入 Asset Catalog。
//
// 用法：swiftc -O makeicons.swift -o makeicons && ./makeicons <构图.jpg> <Assets.xcassets>
//
// - iOS / iPadOS：1024 不透明方图，系统负责圆角
// - macOS：按 macOS 11+ 模板，在 1024 画布里画 824 的圆角矩形，带投影，导出 16～1024 全套
// - tvOS：两层视差图标（背景色 + Vision 抠出的前景）和 Top Shelf 横幅
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("用法: makeicons <构图.jpg> <Assets.xcassets>"); exit(1)
}
let catalog = URL(fileURLWithPath: args[2])
let workDir = URL(fileURLWithPath: args[1]).deletingLastPathComponent().appendingPathComponent("build")
try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - 工具

func canvas(_ width: Int, _ height: Int, opaque: Bool = false) -> CGContext {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: info)!
    context.interpolationQuality = .high
    return context
}

func save(_ image: CGImage, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

func resized(_ image: CGImage, _ size: Int, opaque: Bool = false) -> CGImage {
    let context = canvas(size, size, opaque: opaque)
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()!
}

func writeJSON(_ object: Any, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]

/// 取左上、右上两个角的平均色作为背景色（下方两个角可能被小熊身体挡住）
func backgroundColor(of image: CGImage) -> CGColor {
    let context = canvas(image.width, image.height, opaque: true)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    let patch = image.width / 40
    var sum = [0.0, 0.0, 0.0], count = 0.0
    for (x0, y0) in [(0, 0), (image.width - patch, 0)] {          // CGContext 的内存从顶部一行开始
        for y in y0..<(y0 + patch) {
            for x in x0..<(x0 + patch) {
                let p = (y * context.bytesPerRow) + x * 4
                sum[0] += Double(data[p]); sum[1] += Double(data[p + 1]); sum[2] += Double(data[p + 2]); count += 1
            }
        }
    }
    return CGColor(colorSpace: sRGB, components: [sum[0] / count / 255, sum[1] / count / 255, sum[2] / count / 255, 1])!
}

/// Vision 主体抠图，返回与原图同尺寸、背景透明的前景
func foreground(of image: CGImage) throws -> CGImage {
    let handler = VNImageRequestHandler(cgImage: image)
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])
    guard let observation = request.results?.first else { throw NSError(domain: "makeicons", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有识别到主体"]) }
    let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
    let ciImage = CIImage(cvPixelBuffer: buffer)
    return CIContext().createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: sRGB)!
}

/// 前景底部贴齐画布底边、水平居中，高度占画布的 heightRatio
func place(_ subject: CGImage, in context: CGContext, width: Int, height: Int, heightRatio: CGFloat, centerX: CGFloat? = nil) {
    let h = CGFloat(height) * heightRatio
    let w = h * CGFloat(subject.width) / CGFloat(subject.height)
    let x = (centerX ?? CGFloat(width) / 2) - w / 2
    context.draw(subject, in: CGRect(x: x, y: 0, width: w, height: h))
}

// MARK: - 生成

let background = backgroundColor(of: source)
let subject = try foreground(of: source)
save(subject, workDir.appendingPathComponent("foreground.png"))

/// 原图去掉主体后剩下的场景（背景色 + 绿叶等装饰），用作 tvOS 背景层和 Top Shelf 底图。
/// 抠掉的范围比主体略大一圈，避免视差移动时背景层露出主体的残边。
let scenery: CGImage = {
    let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
    let holed = canvas(source.width, source.height)
    holed.draw(source, in: rect)
    holed.setBlendMode(.destinationOut)
    let d = CGFloat(source.width) * 0.006
    for (dx, dy) in [(0, 0), (d, 0), (-d, 0), (0, d), (0, -d), (d, d), (-d, -d), (d, -d), (-d, d)] {
        holed.draw(subject, in: rect.offsetBy(dx: dx, dy: dy))
    }
    let result = canvas(source.width, source.height)
    result.setFillColor(background)
    result.fill(rect)
    result.draw(holed.makeImage()!, in: rect)
    return result.makeImage()!
}()
save(scenery, workDir.appendingPathComponent("scenery.png"))
print("背景色:", background.components!.prefix(3).map { String(format: "%.3f", $0) })

// iOS：不透明方图
let appIcon = catalog.appendingPathComponent("AppIcon.appiconset")
try? FileManager.default.removeItem(at: appIcon)
save(resized(source, 1024, opaque: true), appIcon.appendingPathComponent("ios-1024.png"))
var images: [[String: Any]] = [["filename": "ios-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]]

// macOS：824 圆角矩形 + 投影
let macMaster: CGImage = {
    let context = canvas(1024, 1024)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: body, cornerWidth: 185.4, cornerHeight: 185.4, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(path); context.setFillColor(background); context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(path); context.clip()
    context.draw(source, in: body)
    context.restoreGState()
    return context.makeImage()!
}()
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "mac-\(points)@\(scale)x.png"
        save(resized(macMaster, points * scale), appIcon.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
writeJSON(["images": images, "info": info], appIcon.appendingPathComponent("Contents.json"))

// tvOS：分层图标 + Top Shelf
let brand = catalog.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
try? FileManager.default.removeItem(at: brand)

func imageStack(_ name: String, sizes: [(scale: Int, width: Int, height: Int)]) {
    let stack = brand.appendingPathComponent("\(name).imagestack")
    for layer in ["Front", "Back"] {
        let set = stack.appendingPathComponent("\(layer).imagestacklayer/Content.imageset")
        var entries: [[String: Any]] = []
        for size in sizes {
            let context = canvas(size.width, size.height)
            if layer == "Back" {
                // 纯色铺满，再按前景同样的位置画场景，绿叶落在主体身后
                context.setFillColor(background)
                context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
                place(scenery, in: context, width: size.width, height: size.height, heightRatio: 0.92)
            } else {
                place(subject, in: context, width: size.width, height: size.height, heightRatio: 0.92)
            }
            let file = "\(layer.lowercased())@\(size.scale)x.png"
            save(context.makeImage()!, set.appendingPathComponent(file))
            entries.append(["filename": file, "idiom": "tv", "scale": "\(size.scale)x"])
        }
        writeJSON(["images": entries, "info": info], set.appendingPathComponent("Contents.json"))
        writeJSON(["info": info], stack.appendingPathComponent("\(layer).imagestacklayer/Contents.json"))
    }
    writeJSON(["info": info, "layers": [["filename": "Front.imagestacklayer"], ["filename": "Back.imagestacklayer"]]],
              stack.appendingPathComponent("Contents.json"))
}
imageStack("App Icon", sizes: [(1, 400, 240), (2, 800, 480)])
imageStack("App Icon - App Store", sizes: [(1, 1280, 768)])

/// Top Shelf 横幅。tvOS 26 会把它放大到屏幕高度并铺满整屏，左右被裁掉，只有中间 16:9 的部分可见，
/// 下方约三成被程序坞遮住。所以文字和主体都放在中间可见区域、程序坞上方。
let shelfTitle = ProcessInfo.processInfo.environment["SHELF_TITLE"] ?? "冷映"
let shelfSubtitle = ProcessInfo.processInfo.environment["SHELF_SUBTITLE"]

func topShelf(_ name: String, width: Int, height: Int) {
    let set = brand.appendingPathComponent("\(name).imageset")
    var entries: [[String: Any]] = []
    for scale in [1, 2] {
        let (w, h) = (CGFloat(width * scale), CGFloat(height * scale))
        let context = canvas(Int(w), Int(h), opaque: true)
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let visibleWidth = h * 16 / 9                     // 铺满 16:9 屏幕时可见的宽度
        let safeLeft = (w - visibleWidth) / 2
        place(scenery, in: context, width: Int(w), height: Int(h), heightRatio: 0.9, centerX: safeLeft + visibleWidth * 0.72)
        place(subject, in: context, width: Int(w), height: Int(h), heightRatio: 0.9, centerX: safeLeft + visibleWidth * 0.72)

        // 浅色背景用小熊的深棕色，深色背景用白色
        let rgb = background.components!
        let luminance = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        let textColor = luminance > 0.6 ? NSColor(srgbRed: 0x4A / 255, green: 0x30 / 255, blue: 0x26 / 255, alpha: 1) : .white
        let titleFont = NSFont(name: "PingFangSC-Semibold", size: h * 0.22) ?? .boldSystemFont(ofSize: h * 0.22)
        let title = NSAttributedString(string: shelfTitle, attributes: [.font: titleFont, .foregroundColor: textColor, .kern: h * 0.015])
        let subtitle = shelfSubtitle.map {
            NSAttributedString(string: $0, attributes: [
                .font: NSFont(name: "PingFangSC-Medium", size: h * 0.075) ?? .systemFont(ofSize: h * 0.075),
                .foregroundColor: textColor.withAlphaComponent(0.75), .kern: h * 0.01])
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let x = safeLeft + visibleWidth * 0.07
        let centerY = h * 0.6                           // 程序坞上方的视觉中心
        let gap = h * 0.03
        let titleSize = title.size(), subtitleSize = subtitle?.size() ?? .zero
        let blockHeight = titleSize.height + (subtitle == nil ? 0 : gap + subtitleSize.height)
        let top = centerY + blockHeight / 2
        title.draw(at: CGPoint(x: x, y: top - titleSize.height))
        subtitle?.draw(at: CGPoint(x: x + h * 0.01, y: top - titleSize.height - gap - subtitleSize.height))
        NSGraphicsContext.restoreGraphicsState()

        let file = "\(name.lowercased().replacingOccurrences(of: " ", with: "-"))@\(scale)x.png"
        save(context.makeImage()!, set.appendingPathComponent(file))
        entries.append(["filename": file, "idiom": "tv", "scale": "\(scale)x"])
    }
    writeJSON(["images": entries, "info": info], set.appendingPathComponent("Contents.json"))
}
topShelf("Top Shelf Image", width: 1920, height: 720)
topShelf("Top Shelf Image Wide", width: 2320, height: 720)

writeJSON([
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
    "info": info,
], brand.appendingPathComponent("Contents.json"))

// 预览图
save(macMaster, workDir.appendingPathComponent("preview-mac.png"))
print("完成：AppIcon.appiconset（iOS + macOS）和 App Icon & Top Shelf Image.brandassets（tvOS）")
