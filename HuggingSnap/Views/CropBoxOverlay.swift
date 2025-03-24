//
//  CropBoxOverlay.swift
//  HuggingSnap
//
//  Created on 3/24/25.
//

import SwiftUI

struct CropBoxOverlay: View {
    // Direct reference to the camera manager
    let cameraManager: CameraManager
    
    // Colors for the crop box
    private let cropBoxColor = Color.white
    private let cornerColor = Color.yellow
    private let cornerSize: CGFloat = 30
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent overlay
                Color.clear
                
                // Crop box outline
                Rectangle()
                    .strokeBorder(cropBoxColor, lineWidth: 2)
                    .frame(width: cameraManager.cropBoxRect.width, height: cameraManager.cropBoxRect.height)
                    .position(x: cameraManager.cropBoxRect.midX, y: cameraManager.cropBoxRect.midY)
                
                // Corner indicators
                Group {
                    // Top left
                    Rectangle()
                        .fill(cornerColor)
                        .frame(width: cornerSize, height: cornerSize)
                        .position(x: cameraManager.cropBoxRect.minX, y: cameraManager.cropBoxRect.minY)
                    
                    // Top right
                    Rectangle()
                        .fill(cornerColor)
                        .frame(width: cornerSize, height: cornerSize)
                        .position(x: cameraManager.cropBoxRect.maxX, y: cameraManager.cropBoxRect.minY)
                    
                    // Bottom left
                    Rectangle()
                        .fill(cornerColor)
                        .frame(width: cornerSize, height: cornerSize)
                        .position(x: cameraManager.cropBoxRect.minX, y: cameraManager.cropBoxRect.maxY)
                    
                    // Bottom right
                    Rectangle()
                        .fill(cornerColor)
                        .frame(width: cornerSize, height: cornerSize)
                        .position(x: cameraManager.cropBoxRect.maxX, y: cameraManager.cropBoxRect.maxY)
                }
            }
            .contentShape(Rectangle()) // Make the entire area tappable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Check if we're starting a drag on a corner
                        if !cameraManager.isResizing {
                            if let corner = cameraManager.cornerContainingPoint(value.startLocation) {
                                cameraManager.startResizing(from: corner)
                            }
                        }
                        
                        // Update crop box if we're resizing
                        if cameraManager.isResizing {
                            cameraManager.updateCropBox(with: value.location)
                        }
                    }
                    .onEnded { _ in
                        cameraManager.endResizing()
                    }
            )
        }
    }
}