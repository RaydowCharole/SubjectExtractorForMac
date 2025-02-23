//
//  SubjectExtractor.swift
//  SubjectExtractorForMac
//
//  Created by Raydow on 2025/2/11.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

// https://developer.apple.com/videos/play/wwdc2023/10176
class SubjectExtractor {
    static let shared = SubjectExtractor()

    private let request = VNGenerateForegroundInstanceMaskRequest()

    static func convert(_ pixelBuffer: CVPixelBuffer) -> CIImage? {
        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let mask = shared.subjectMask(fromImage: inputImage) else { return nil }
        let output = shared.apply(toInputImage: inputImage, mask: mask)

        return output
    }

    /// Returns the subject alpha mask for the given image.
    ///
    /// - parameter image: The image to extract a foreground subject from.
    /// - parameter atPoint: An optional normalized point for selecting a subject instance.
    func subjectMask(fromImage image: CIImage, atPoint point: CGPoint? = nil) -> CIImage? {
        // Create a request handler.
        let handler = VNImageRequestHandler(ciImage: image)

        // Perform the request.
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform Vision request.")
            return nil
        }

        // Acquire the instance mask observation.
        guard let result = request.results?.first else {
            print("No subject observations found.")
            return nil
        }

        let instances = instances(atPoint: point, inObservation: result)

        // Create a matted image with the subject isolated from the background.
        do {
            let mask = try result.generateScaledMaskForImage(forInstances: instances, from: handler)
            return CIImage(cvPixelBuffer: mask)
        } catch {
            print("Failed to generate subject mask.")
            return nil
        }
    }

    /// Returns the indices of the instances at the given point.
    ///
    /// - parameter atPoint: A point with a top-left origin, normalized within the range [0, 1].
    /// - parameter inObservation: The observation instance to extract subject indices from.
    private func instances(
        atPoint maybePoint: CGPoint?,
        inObservation observation: VNInstanceMaskObservation
    ) -> IndexSet {
        guard let point = maybePoint else {
            return observation.allInstances
        }

        // Transform the normalized UI point to an instance map pixel coordinate.
        let instanceMap = observation.instanceMask
        let coords = VNImagePointForNormalizedPoint(
            point,
            CVPixelBufferGetWidth(instanceMap) - 1,
            CVPixelBufferGetHeight(instanceMap) - 1)

        // Look up the instance label at the computed pixel coordinate.
        CVPixelBufferLockBaseAddress(instanceMap, .readOnly)
        guard let pixels = CVPixelBufferGetBaseAddress(instanceMap) else {
            fatalError("Failed to access instance map data.")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(instanceMap)
        let instanceLabel = pixels.load(
            fromByteOffset: Int(coords.y) * bytesPerRow + Int(coords.x),
            as: UInt8.self)
        CVPixelBufferUnlockBaseAddress(instanceMap, .readOnly)

        // If the point lies on the background, select all instances.
        // Otherwise, restrict this to just the selected instance.
        return instanceLabel == 0 ? observation.allInstances : [Int(instanceLabel)]
    }

    /// Applies the current effect and returns the composited image.
    private func apply(
        effect: Effect = .cut,
        toInputImage inputImage: CIImage,
        mask: CIImage
    ) -> CIImage {
        var postEffectBackground: CIImage?

        switch effect {
        case .highlight:
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = inputImage
            filter.ev = -3
            postEffectBackground = filter.outputImage!

        case .bokeh:
            let filter = CIFilter.bokehBlur()
            filter.inputImage = apply(
                effect: .none,
                toInputImage: CIImage(color: .white)
                    .cropped(to: inputImage.extent),
                mask: mask)
            filter.ringSize = 1
            filter.ringAmount = 1
            filter.softness = 1.0
            filter.radius = 20
            postEffectBackground = filter.outputImage!

        case .noir:
            let filter = CIFilter.photoEffectNoir()
            filter.inputImage = inputImage
            postEffectBackground = filter.outputImage!
        case .none:
            postEffectBackground = inputImage
        default:
            break
        }

        let filter = CIFilter.blendWithMask()
        filter.inputImage = inputImage
        filter.backgroundImage = postEffectBackground
        filter.maskImage = mask
        return filter.outputImage!
    }
}

/// Presets for the subjects' visual effects.
enum Effect: String, Equatable, CaseIterable {
    case none = "None"
    case highlight = "Highlight"
    case bokeh = "Bokeh Halo"
    case noir = "Noir"
    case cut = "Cut"
}

let context = CIContext()

extension CIImage {
    var cgImage: CGImage? {
        guard let cgImage = context.createCGImage(self, from: extent) else {
            return nil
        }
        return cgImage
    }
}
