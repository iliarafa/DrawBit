#!/usr/bin/env swift

import Foundation
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Usage: swift scripts/generate_app_icon.swift <output.png> [--dark]
// Renders a 1024x1024 "BITME" wordmark using Press Start 2P.

func usage() -> Never {
    FileHandle.standardError.write(
        "usage: swift generate_app_icon.swift <output.png> [--dark]\n".data(using: .utf8)!
    )
    exit(2)
}

let args = CommandLine.arguments.dropFirst()
guard let outputArg = args.first else { usage() }
let dark = args.contains("--dark")
let outputURL = URL(fileURLWithPath: outputArg)

let fontURL = URL(fileURLWithPath: "Bitme/Resources/Fonts/PressStart2P-Regular.ttf")
guard let fontData = try? Data(contentsOf: fontURL) else {
    FileHandle.standardError.write("error: cannot read \(fontURL.path)\n".data(using: .utf8)!)
    exit(1)
}
guard let provider = CGDataProvider(data: fontData as CFData),
      let cgFont = CGFont(provider) else {
    FileHandle.standardError.write("error: cannot construct CGFont\n".data(using: .utf8)!)
    exit(1)
}

let canvas: CGFloat = 1024
let text = "BITME" as NSString
let targetWidthRatio: CGFloat = 0.80

let probeSize: CGFloat = 100
let probeFont = CTFontCreateWithGraphicsFont(cgFont, probeSize, nil, nil)
let probeAttrs: [NSAttributedString.Key: Any] = [
    .font: probeFont as Any,
    .kern: 0,
]
let probeString = NSAttributedString(string: text as String, attributes: probeAttrs)
let probeLine = CTLineCreateWithAttributedString(probeString)
let probeBounds = CTLineGetBoundsWithOptions(probeLine, .useOpticalBounds)
let fontSize = probeSize * (canvas * targetWidthRatio) / probeBounds.width

let font = CTFontCreateWithGraphicsFont(cgFont, fontSize, nil, nil)
let textColor: CGColor = dark
    ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    : CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
let bgColor: CGColor = dark
    ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

let attrs: [NSAttributedString.Key: Any] = [
    .font: font as Any,
    .foregroundColor: textColor,
    .kern: 0,
]
let attributed = NSAttributedString(string: text as String, attributes: attrs)
let line = CTLineCreateWithAttributedString(attributed)
let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("error: cannot create CGContext\n".data(using: .utf8)!)
    exit(1)
}

ctx.setShouldAntialias(false)
ctx.setAllowsAntialiasing(false)
ctx.setShouldSubpixelQuantizeFonts(false)
ctx.setShouldSubpixelPositionFonts(false)

ctx.setFillColor(bgColor)
ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

let textX = (canvas - textBounds.width) / 2 - textBounds.origin.x
let textY = (canvas - textBounds.height) / 2 - textBounds.origin.y
ctx.textPosition = CGPoint(x: textX, y: textY)
CTLineDraw(line, ctx)

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write("error: cannot make image\n".data(using: .utf8)!)
    exit(1)
}
guard let dest = CGImageDestinationCreateWithURL(
    outputURL as CFURL, UTType.png.identifier as CFString, 1, nil
) else {
    FileHandle.standardError.write("error: cannot create PNG destination\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("error: cannot finalize PNG\n".data(using: .utf8)!)
    exit(1)
}

print("wrote \(outputURL.path) (\(Int(canvas))x\(Int(canvas)), \(dark ? "dark" : "light"))")
