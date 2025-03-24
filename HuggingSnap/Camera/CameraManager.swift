////
////  ContentView.swift
////  HuggingSnap
////
////  Created by Cyril Zakka on 2/11/25.
////

import AVFoundation
import SwiftUI
import CoreGraphics
import UIKit
class CameraManager: NSObject, ObservableObject {
    enum Status {
        case unconfigured
        case configured
        case unauthorized
        case failed
    }
    
    static let shared = CameraManager()
    
    // Resizable crop box properties
    @Published var cropBoxRect: CGRect = CGRect(x: 50, y: 50, width: 300, height: 300)
    @Published var isResizing: Bool = false
    
    // Corner indicator size
    private let cornerIndicatorSize: CGFloat = 30
    
    // Enum to identify which corner is being dragged
    enum CropBoxCorner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }
    
    @Published var activeCorner: CropBoxCorner? = nil
    
    // Photo output
    private let photoOutput = AVCapturePhotoOutput()
    @Published private(set) var photo: Data?
    
    // Movie output
    private let movieOutput = AVCaptureMovieFileOutput()
    private var temporaryMovieURL: URL?
    @Published private(set) var isRecording = false
    @Published private(set) var movieURL: URL?
    
    @Published var error: CameraError?
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    
    let session = AVCaptureSession()
    
    private let sessionQueue = DispatchQueue(label: "com.cyrilzakka.SessionQ")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var status = Status.unconfigured
    
    private override init() {
        super.init()
        configure()
    }
    
    private func set(error: CameraError?) {
        DispatchQueue.main.async {
            self.error = error
        }
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video) { authorized in
                if !authorized {
                    self.status = .unauthorized
                    self.set(error: .deniedAuthorization)
                }
                self.sessionQueue.resume()
            }
        case .restricted:
            status = .unauthorized
            set(error: .restrictedAuthorization)
        case .denied:
            status = .unauthorized
            set(error: .deniedAuthorization)
        case .authorized:
            break
        @unknown default:
            status = .unauthorized
            set(error: .unknownAuthorization)
        }
    }
    
    private func configureCaptureSession() {
        guard status == .unconfigured else {
            return
        }
        
        session.beginConfiguration()
        
        defer {
            session.commitConfiguration()
        }
        
        let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: cameraPosition)
        guard let camera = device else {
            set(error: .cameraUnavailable)
            status = .failed
            return
        }
        
        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(cameraInput) {
                session.addInput(cameraInput)
            } else {
                set(error: .cannotAddInput)
                status = .failed
                return
            }
        } catch {
            set(error: .createCaptureInput(error))
            status = .failed
            return
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .speed
            photoOutput.isLivePhotoCaptureEnabled = false
        } else {
            set(error: .cannotAddOutput)
            status = .failed
            return
        }
        
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        } else {
            set(error: .cannotAddOutput)
            status = .failed
            return
        }
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            
            videoOutput.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            
            let videoConnection = videoOutput.connection(with: .video)
            videoConnection?.videoRotationAngle = 90
            videoConnection?.isVideoMirrored = true
        } else {
            set(error: .cannotAddOutput)
            status = .failed
            return
        }
        
        status = .configured
    }
    
    private func configure() {
        checkPermissions()
        
        sessionQueue.async {
            self.configureCaptureSession()
            self.session.startRunning()
        }
    }
    
    func switchCamera() {
        sessionQueue.async {
            self.reconfigureCaptureSession()
        }
    }
    
    private func reconfigureCaptureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        // Remove existing input
        for input in session.inputs {
            session.removeInput(input)
        }
        
        // Toggle camera position
        cameraPosition = cameraPosition == .front ? .back : .front
        
        // Get new camera device
        let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: cameraPosition)
        
        guard let camera = device else {
            set(error: .cameraUnavailable)
            status = .failed
            return
        }
        
        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(cameraInput) {
                session.addInput(cameraInput)
            } else {
                set(error: .cannotAddInput)
                status = .failed
                return
            }
            
            // Update video connection rotation
            if let videoConnection = videoOutput.connection(with: .video) {
                if cameraPosition == .front {
                    videoConnection.videoRotationAngle = 90
                } else {
                    videoConnection.videoRotationAngle = 90
                    videoConnection.isVideoMirrored = true
                }
            }
            
        } catch {
            set(error: .createCaptureInput(error))
            status = .failed
            return
        }
    }
    
    private func videoRotationAngleForCurrentOrientation() -> CGFloat {
        // Since we're having issues with UIKit, return a fixed value for now
        // In a real implementation, you would determine the device orientation
        // using platform-specific APIs
        return 0 // Default to portrait orientation (0 degrees)
    }
    
    func capturePhoto() {
        sessionQueue.async {
            let photoSettings = AVCapturePhotoSettings()
            photoSettings.photoQualityPrioritization = .speed
            
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoRotationAngle = self.videoRotationAngleForCurrentOrientation()
            }
            
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
    
    func toggleRecording() {
        guard !movieOutput.isRecording else {
            stopRecording()
            return
        }
        startRecording()
    }
    
    private func startRecording() {
        sessionQueue.async {
            guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("Couldn't create movie file")
                return
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let currentDate = dateFormatter.string(from: Date())
            let videoName = "video_\(currentDate).mov"
            let videoPath = documentsPath.appendingPathComponent(videoName)
            
            try? FileManager.default.removeItem(at: videoPath) // Remove existing file
            
            self.movieOutput.startRecording(to: videoPath, recordingDelegate: self)
            self.temporaryMovieURL = videoPath
            
            DispatchQueue.main.async {
                self.isRecording = true
            }
        }
    }
    
    private func stopRecording() {
        sessionQueue.async {
            self.movieOutput.stopRecording()
            DispatchQueue.main.async {
                self.isRecording = false
                if let tempURL = self.temporaryMovieURL {
                    self.movieURL = tempURL
                }
            }
        }
    }
    
    func set(
        _ delegate: AVCaptureVideoDataOutputSampleBufferDelegate,
        queue: DispatchQueue
    ) {
        sessionQueue.async {
            self.videoOutput.setSampleBufferDelegate(delegate, queue: queue)
        }
    }
    
    @Published private(set) var isStreamingPaused: Bool = false
    
    // Returns the frame for each corner indicator
    func cornerIndicatorFrame(for corner: CropBoxCorner) -> CGRect {
        switch corner {
        case .topLeft:
            return CGRect(x: cropBoxRect.minX - cornerIndicatorSize/2,
                          y: cropBoxRect.minY - cornerIndicatorSize/2,
                          width: cornerIndicatorSize,
                          height: cornerIndicatorSize)
        case .topRight:
            return CGRect(x: cropBoxRect.maxX - cornerIndicatorSize/2,
                          y: cropBoxRect.minY - cornerIndicatorSize/2,
                          width: cornerIndicatorSize,
                          height: cornerIndicatorSize)
        case .bottomLeft:
            return CGRect(x: cropBoxRect.minX - cornerIndicatorSize/2,
                          y: cropBoxRect.maxY - cornerIndicatorSize/2,
                          width: cornerIndicatorSize,
                          height: cornerIndicatorSize)
        case .bottomRight:
            return CGRect(x: cropBoxRect.maxX - cornerIndicatorSize/2,
                          y: cropBoxRect.maxY - cornerIndicatorSize/2,
                          width: cornerIndicatorSize,
                          height: cornerIndicatorSize)
        }
    }
    
    // Check if a point is within any corner indicator
    func cornerContainingPoint(_ point: CGPoint) -> CropBoxCorner? {
        for corner in [CropBoxCorner.topLeft, .topRight, .bottomLeft, .bottomRight] {
            if cornerIndicatorFrame(for: corner).contains(point) {
                return corner
            }
        }
        return nil
    }
    
    // Start resizing from a specific corner
    func startResizing(from corner: CropBoxCorner) {
        isResizing = true
        activeCorner = corner
    }
    
    // Update the crop box size based on drag movement
    func updateCropBox(with newPoint: CGPoint) {
        guard isResizing, let corner = activeCorner else { return }
        
        var newRect = cropBoxRect
        
        switch corner {
        case .topLeft:
            let width = cropBoxRect.maxX - newPoint.x
            let height = cropBoxRect.maxY - newPoint.y
            if width > 50 && height > 50 {
                newRect = CGRect(x: newPoint.x, y: newPoint.y,
                                width: width, height: height)
            }
        case .topRight:
            let width = newPoint.x - cropBoxRect.minX
            let height = cropBoxRect.maxY - newPoint.y
            if width > 50 && height > 50 {
                newRect = CGRect(x: cropBoxRect.minX, y: newPoint.y,
                                width: width, height: height)
            }
        case .bottomLeft:
            let width = cropBoxRect.maxX - newPoint.x
            let height = newPoint.y - cropBoxRect.minY
            if width > 50 && height > 50 {
                newRect = CGRect(x: newPoint.x, y: cropBoxRect.minY,
                                width: width, height: height)
            }
        case .bottomRight:
            let width = newPoint.x - cropBoxRect.minX
            let height = newPoint.y - cropBoxRect.minY
            if width > 50 && height > 50 {
                newRect = CGRect(x: cropBoxRect.minX, y: cropBoxRect.minY,
                                width: width, height: height)
            }
        }
        
        cropBoxRect = newRect
    }
    
    // End resizing
    func endResizing() {
        isResizing = false
        activeCorner = nil
    }
    
    // Crop the image based on the crop box
    func cropImage(from imageData: Data) -> Data? {
        guard let uiImage = UIImage(data: imageData) else { return nil }
        
        // Calculate the crop rect relative to the image size
        let imageSize = uiImage.size
        let viewSize = UIScreen.main.bounds.size
        
        // Calculate scaling factors
        let scaleX = imageSize.width / viewSize.width
        let scaleY = imageSize.height / viewSize.height
        
        // Calculate the crop rect in the image's coordinate space
        let cropX = cropBoxRect.origin.x * scaleX
        let cropY = cropBoxRect.origin.y * scaleY
        let cropWidth = cropBoxRect.size.width * scaleX
        let cropHeight = cropBoxRect.size.height * scaleY
        
        let cropRectInImage = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        
        // Ensure the crop rect is within the image bounds
        let validCropRect = cropRectInImage.intersection(CGRect(origin: .zero, size: imageSize))
        
        // Create a CGImage with the cropped portion
        guard let cgImage = uiImage.cgImage,
              let croppedCGImage = cgImage.cropping(to: validCropRect) else {
            return nil
        }
        
        // Create a new UIImage from the cropped CGImage
        let croppedImage = UIImage(cgImage: croppedCGImage,
                                  scale: uiImage.scale,
                                  orientation: uiImage.imageOrientation)
        
        // Convert back to data
        return croppedImage.jpegData(compressionQuality: 0.9)
    }
    
    func toggleStreaming() {
        isStreamingPaused.toggle()
        
        if isStreamingPaused {
            session.stopRunning()
        } else {
            sessionQueue.async {
                self.session.startRunning()
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            set(error: .photo(error))
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            set(error: .photo(NSError(domain: "CameraError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create image data"])))
            return
        }
        
        DispatchQueue.main.async {
            self.photo = imageData
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            set(error: .movie(error))
            return
        }
        
        // Optionally notify about successful recording
        print("Video saved to: \(outputFileURL.path)")
    }
}
