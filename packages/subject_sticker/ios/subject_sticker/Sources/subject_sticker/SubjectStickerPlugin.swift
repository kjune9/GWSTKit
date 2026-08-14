import Flutter
import UIKit
import Vision

/// On-device subject cutout via the Vision foreground instance mask.
///
/// One method: `cutout {path}` -> transparent PNG bytes of the foreground,
/// or a FlutterError (`unsupported` / `decode-failed` / `no-subject` /
/// `segmentation-failed` / `encode-failed`).
///
/// Requires iOS 17+ at runtime (`VNGenerateForegroundInstanceMaskRequest`);
/// the Dart side gates `subjectCutoutSupported` on the OS version so this
/// plugin only reports `unsupported` as a defensive fallback.
public class SubjectStickerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "subject_sticker", binaryMessenger: registrar.messenger())
    let instance = SubjectStickerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "cutout":
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(code: "bad-args", message: "missing 'path'", details: nil))
        return
      }
      cutout(path: path, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func cutout(path: String, result: @escaping FlutterResult) {
    guard #available(iOS 17.0, *) else {
      result(FlutterError(code: "unsupported", message: "requires iOS 17+", details: nil))
      return
    }
    // Vision's perform() is synchronous and heavy — keep it off the main thread.
    DispatchQueue.global(qos: .userInitiated).async {
      let outcome = Self.performCutout(path: path)
      DispatchQueue.main.async {
        switch outcome {
        case .success(let data):
          result(FlutterStandardTypedData(bytes: data))
        case .failure(let error):
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      }
    }
  }

  @available(iOS 17.0, *)
  private static func performCutout(path: String) -> Result<Data, CutoutError> {
    guard let source = UIImage(contentsOfFile: path),
      let cgImage = normalizedCGImage(of: source)
    else {
      return .failure(CutoutError(code: "decode-failed", message: "could not read image"))
    }
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return .failure(
        CutoutError(code: "segmentation-failed", message: error.localizedDescription))
    }
    guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
      return .failure(CutoutError(code: "no-subject", message: "no foreground returned"))
    }
    do {
      let buffer = try observation.generateMaskedImage(
        ofInstances: observation.allInstances, from: handler,
        croppedToInstancesExtent: false)
      guard let png = pngData(from: buffer) else {
        return .failure(CutoutError(code: "encode-failed", message: "could not encode PNG"))
      }
      return .success(png)
    } catch {
      return .failure(
        CutoutError(code: "segmentation-failed", message: error.localizedDescription))
    }
  }

  /// Redraws the image when its EXIF orientation is not `.up`, so the mask
  /// lines up with what the user sees (parity with ML Kit's fromFilePath).
  private static func normalizedCGImage(of image: UIImage) -> CGImage? {
    if image.imageOrientation == .up { return image.cgImage }
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    let redrawn = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }
    return redrawn.cgImage
  }

  /// CVPixelBuffer (BGRA with alpha) -> PNG, preserving transparency.
  private static func pngData(from buffer: CVPixelBuffer) -> Data? {
    let ciImage = CIImage(cvPixelBuffer: buffer)
    let context = CIContext()
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      return nil
    }
    return UIImage(cgImage: cgImage).pngData()
  }

  private struct CutoutError: Error {
    let code: String
    let message: String
  }
}
