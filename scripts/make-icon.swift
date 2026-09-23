#!/usr/bin/env swift
// Renders the 1024x1024 app icon master. Usage: swift scripts/make-icon.swift <out.png>
import AppKit
import CoreGraphics

let side: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

func gray(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(gray: w, alpha: a) }

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

// macOS icon grid: an 824pt body centred on the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: gray(0, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(gray(0.16))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let background = CGGradient(colorsSpace: space, colors: [gray(0.27), gray(0.11)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

// A classic 2x6 strip: four photos above a caption band, tilted a few degrees.
let stripSize = CGSize(width: 240, height: 700)
let inset: CGFloat = 20
let gutter: CGFloat = 14
let footer: CGFloat = 64
ctx.translateBy(x: side / 2, y: side / 2)
ctx.rotate(by: -8 * .pi / 180)
let strip = CGRect(x: -stripSize.width / 2, y: -stripSize.height / 2, width: stripSize.width, height: stripSize.height)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: gray(0, 0.55))
ctx.addPath(CGPath(roundedRect: strip, cornerWidth: 10, cornerHeight: 10, transform: nil))
ctx.setFillColor(gray(0.97))
ctx.fillPath()
ctx.restoreGState()

let photoWidth = strip.width - inset * 2
let photoHeight = (strip.height - inset * 2 - footer - gutter * 3) / 4
let photo = CGGradient(colorsSpace: space, colors: [gray(0.36), gray(0.18)] as CFArray, locations: [0, 1])!
for i in 0..<4 {
    let top = strip.maxY - inset - CGFloat(i) * (photoHeight + gutter)
    let rect = CGRect(x: strip.minX + inset, y: top - photoHeight, width: photoWidth, height: photoHeight)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(photo, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    // A head and shoulders, so each frame reads as a portrait.
    ctx.setFillColor(gray(0.62))
    ctx.fillEllipse(in: CGRect(x: rect.midX - 22, y: rect.minY + photoHeight * 0.42, width: 44, height: 50))
    ctx.fillEllipse(in: CGRect(x: rect.midX - 52, y: rect.minY - 40, width: 104, height: 88))
    ctx.restoreGState()
}

let caption = CGRect(x: strip.midX - 60, y: strip.minY + inset + footer / 2 - 14, width: 120, height: 6)
ctx.setFillColor(gray(0.55))
ctx.addPath(CGPath(roundedRect: caption, cornerWidth: 3, cornerHeight: 3, transform: nil))
ctx.fillPath()
ctx.restoreGState()

guard let image = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
