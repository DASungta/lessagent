// Native QR generation and a Vision roundtrip check; never print the payload.
import Cocoa
import CoreImage
import Vision

precondition(CommandLine.arguments.count == 3, "Pass a private payload file and PNG output path")
let payload = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(Data(payload.utf8), forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
let code = filter.outputImage!
let extent = code.extent.insetBy(dx: -4, dy: -4)
let white = CIImage(color: .white).cropped(to: extent)
let padded = code.composited(over: white).cropped(to: extent)
let image = CIContext().createCGImage(padded.transformed(by: CGAffineTransform(scaleX: 12, y: 12)), from: extent.applying(CGAffineTransform(scaleX: 12, y: 12)))!
let check = VNDetectBarcodesRequest()
check.symbologies = [.qr]
try VNImageRequestHandler(cgImage: image, options: [:]).perform([check])
precondition(check.results?.first?.payloadStringValue == payload, "QR roundtrip failed")
let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("PASS native QR generated and Vision roundtrip verified; payload omitted")
