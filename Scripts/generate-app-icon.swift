#!/usr/bin/env swift
//
// Генерирует ТОЛЬКО legacy PNG-стек для Assets.xcassets/AppIcon.appiconset —
// плоские растровые размеры, как до macOS 26.
//
// Слоёная иконка Liquid Glass (AppIcon.icon) здесь не делается: формат
// folder.iconcomposer.icon собирается в GUI Icon Composer, который лежит в
// /Applications/Xcode.app/Contents/Applications/Icon Composer.app.
// Как её подключить — см. «App icon» в CONTRIBUTING.md.
//
// Исходные параметры рисунка, чтобы иконка в Icon Composer совпала с этой:
//   фон     — линейный градиент 135°, RGB 0.24/0.52/0.98 → 0.10/0.34/0.82
//   символ   — SF Symbol «arrow.triangle.branch», semibold, 46% от стороны
//   скругление — 22% от стороны, инсет 6%
import AppKit

struct IconSpec: Hashable {
    let filename: String
    let pixels: Int
}

let specs: [IconSpec] = [
    IconSpec(filename: "icon_16x16.png", pixels: 16),
    IconSpec(filename: "icon_16x16@2x.png", pixels: 32),
    IconSpec(filename: "icon_32x32.png", pixels: 32),
    IconSpec(filename: "icon_32x32@2x.png", pixels: 64),
    IconSpec(filename: "icon_128x128.png", pixels: 128),
    IconSpec(filename: "icon_128x128@2x.png", pixels: 256),
    IconSpec(filename: "icon_256x256.png", pixels: 256),
    IconSpec(filename: "icon_256x256@2x.png", pixels: 512),
    IconSpec(filename: "icon_512x512.png", pixels: 512),
    IconSpec(filename: "icon_512x512@2x.png", pixels: 1024),
]

func drawIcon(pixels: Int) -> NSImage {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.06
    let rounded = NSBezierPath(roundedRect: canvas.insetBy(dx: inset, dy: inset), xRadius: size * 0.22, yRadius: size * 0.22)

    let top = NSColor(calibratedRed: 0.24, green: 0.52, blue: 0.98, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.82, alpha: 1)
    NSGradient(colors: [top, bottom])?.draw(in: rounded, angle: 135)

    let highlight = NSBezierPath(roundedRect: canvas.insetBy(dx: inset + size * 0.02, dy: inset + size * 0.02), xRadius: size * 0.19, yRadius: size * 0.19)
    NSColor.white.withAlphaComponent(0.14).setFill()
    highlight.fill()

    let symbolPointSize = size * 0.46
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        .applying(.init(hierarchicalColor: .white))
    guard let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else {
        image.unlockFocus()
        return image
    }

    let symbolSide = size * 0.54
    let symbolRect = NSRect(
        x: (size - symbolSide) / 2,
        y: (size - symbolSide) / 2,
        width: symbolSide,
        height: symbolSide
    )
    symbol.draw(in: symbolRect)

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "generate-app-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try data.write(to: url)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "KeenSwitch/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for spec in specs {
    let url = outputDir.appendingPathComponent(spec.filename)
    try writePNG(drawIcon(pixels: spec.pixels), to: url)
    fputs("Wrote \(spec.filename)\n", stderr)
}
