//
//  main.swift
//  SubjectExtractorForMac
//
//  Created by Raydow on 2025/2/23.
//

import AVFoundation
import CoreImage

print("\n*** 对视频主体抠图，输出PNG序列帧 ***")

while true {
    // 提示用户输入视频文件路径
    print("\n请拖入一个或多个视频: ", terminator: "")
    guard let args = readLine()?.trimmingCharacters(in: .whitespaces), !args.isEmpty else {
        print("路径为空")
        exit(1)
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "'主体抠图_'yyMMdd"
    let timestamp = formatter.string(from: Date())

    var videoPaths = args.split(separator: " ")

    var i = 1
    while i < videoPaths.count {
        let pre = videoPaths[i - 1]
        let current = videoPaths[i]
        if pre.last == "\\" {
            videoPaths[i - 1] = (pre + " " + current).filter({
                $0 != "\\"
            })
            videoPaths.remove(at: i)
        } else {
            i += 1
        }
    }

    for (i, videoPath) in videoPaths.enumerated() {
        let videoPath = String(videoPath)

        // 检查文件是否存在
        let videoURL = URL(fileURLWithPath: videoPath)
        if !FileManager.default.fileExists(atPath: videoPath) {
            print("文件不存在")
            continue
        }

        // 尝试加载文件为 AVAsset
        let asset = AVAsset(url: videoURL)
        // 检查是否有视频轨道
        var isVideo = false
        for track in asset.tracks {
            if track.mediaType == .video {
                isVideo = true
                break
            }
        }
        let fileName = videoURL.lastPathComponent
        print("\n------- 第 \(i + 1) 个 -------")
        print("文件: \(fileName)")

        // 创建输出目录，位于输入视频文件的同级目录下
        let outputDir = "\(videoURL.deletingLastPathComponent().path)/\(timestamp)/\(videoURL.deletingPathExtension().lastPathComponent)"

        print("输出路径: \(outputDir)")

        if !isVideo {
            print("不是视频文件\n跳过")
            continue
        }
        // 创建 AVAssetReader 来读取视频帧
        guard let reader = try? AVAssetReader(asset: asset) else {
            print("读取失败: 无法创建 AVAssetReader")
            continue
        }

        // 创建输出目录
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)

        let videoTrack = asset.tracks(withMediaType: .video).first!
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        reader.add(trackOutput)
        reader.startReading()

        print("处理中...")

        var frameCount = 0

        // 处理每一帧
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            autoreleasepool {
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    // 将 CVPixelBuffer 转换为 CGImage
                    let ciImage: CIImage? = SubjectExtractor.convert(pixelBuffer)

                    if let cgImage = ciImage?.cgImage {
                        // 保存为 PNG 文件
                        let framePath = "\(outputDir)/\(frameCount).png"
                        let url = URL(fileURLWithPath: framePath)

                        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                        CGImageDestinationAddImage(destination, cgImage, nil)
                        CGImageDestinationFinalize(destination)

                        frameCount += 1
                    }
                }
            }
        }

        print("处理完成，共处理 \(frameCount) 帧")
    }
}
