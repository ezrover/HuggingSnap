//
//  CropBoxOverlayView.swift
//  HuggingSnap
//
//  Created on 3/24/25.
//

import SwiftUI

// Simple struct to represent a crop box
struct CropBox {
    var rect: CGRect
    var isResizing: Bool
    var isMoving: Bool
    var activeCorner: Corner?
    var dragStart: CGPoint?
    
    enum Corner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }
}

struct CropBoxOverlayView: View {
    // Use a simple crop box struct for UI state
    @State private var cropBox = CropBox(
        rect: CGRect(x: 50, y: 50, width: 300, height: 300),
        isResizing: false,
        isMoving: false,
        activeCorner: nil,
        dragStart: nil
    )
    
    // Callback for when the user taps on the crop box
    var onCapture: (() -> Void)?
    
    // Colors for the crop box
    private let cropBoxColor = Color.white
    private let cropBoxCornerColor = Color.yellow
    private let cornerIndicatorSize: CGFloat = 30
    
    // Minimum size for the crop box
    private let minSize: CGFloat = 100
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Transparent overlay
                Color.clear
                
                // Crop box outline
                Rectangle()
                    .strokeBorder(cropBoxColor, lineWidth: 2)
                    .frame(width: cropBox.rect.width, height: cropBox.rect.height)
                    .position(x: cropBox.rect.midX, y: cropBox.rect.midY)
                
                // Corner indicators
                Group {
                    // Top left
                    Rectangle()
                        .fill(cropBoxCornerColor)
                        .frame(width: cornerIndicatorSize, height: cornerIndicatorSize)
                        .position(x: cropBox.rect.minX, y: cropBox.rect.minY)
                    
                    // Top right
                    Rectangle()
                        .fill(cropBoxCornerColor)
                        .frame(width: cornerIndicatorSize, height: cornerIndicatorSize)
                        .position(x: cropBox.rect.maxX, y: cropBox.rect.minY)
                    
                    // Bottom left
                    Rectangle()
                        .fill(cropBoxCornerColor)
                        .frame(width: cornerIndicatorSize, height: cornerIndicatorSize)
                        .position(x: cropBox.rect.minX, y: cropBox.rect.maxY)
                    
                    // Bottom right
                    Rectangle()
                        .fill(cropBoxCornerColor)
                        .frame(width: cornerIndicatorSize, height: cornerIndicatorSize)
                        .position(x: cropBox.rect.maxX, y: cropBox.rect.maxY)
                }
            }
            .contentShape(Rectangle()) // Make the entire area tappable
            // Add a tap gesture to capture and analyze the image
            .onTapGesture {
                // Call the capture callback when the user taps on the crop box
                onCapture?()
            }
            // Add a drag gesture for resizing and moving the crop box
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // First drag event - determine if we're resizing or moving
                        if !cropBox.isResizing && !cropBox.isMoving {
                            // Check if we're on a corner
                            let topLeft = CGRect(x: cropBox.rect.minX - cornerIndicatorSize/2,
                                               y: cropBox.rect.minY - cornerIndicatorSize/2,
                                               width: cornerIndicatorSize,
                                               height: cornerIndicatorSize)
                            
                            let topRight = CGRect(x: cropBox.rect.maxX - cornerIndicatorSize/2,
                                                y: cropBox.rect.minY - cornerIndicatorSize/2,
                                                width: cornerIndicatorSize,
                                                height: cornerIndicatorSize)
                            
                            let bottomLeft = CGRect(x: cropBox.rect.minX - cornerIndicatorSize/2,
                                                  y: cropBox.rect.maxY - cornerIndicatorSize/2,
                                                  width: cornerIndicatorSize,
                                                  height: cornerIndicatorSize)
                            
                            let bottomRight = CGRect(x: cropBox.rect.maxX - cornerIndicatorSize/2,
                                                   y: cropBox.rect.maxY - cornerIndicatorSize/2,
                                                   width: cornerIndicatorSize,
                                                   height: cornerIndicatorSize)
                            
                            // Start resizing if we're on a corner and set the active corner
                            if topLeft.contains(value.startLocation) {
                                cropBox.isResizing = true
                                cropBox.activeCorner = .topLeft
                            } else if topRight.contains(value.startLocation) {
                                cropBox.isResizing = true
                                cropBox.activeCorner = .topRight
                            } else if bottomLeft.contains(value.startLocation) {
                                cropBox.isResizing = true
                                cropBox.activeCorner = .bottomLeft
                            } else if bottomRight.contains(value.startLocation) {
                                cropBox.isResizing = true
                                cropBox.activeCorner = .bottomRight
                            } else if cropBox.rect.contains(value.startLocation) {
                                // If we're inside the crop box but not on a corner, we're moving
                                cropBox.isMoving = true
                                cropBox.dragStart = value.startLocation
                            }
                        }
                        
                        // Handle resizing
                        if cropBox.isResizing, let corner = cropBox.activeCorner {
                            var newRect = cropBox.rect
                            
                            // Resize based on which corner is being dragged
                            switch corner {
                            case .topLeft:
                                let width = cropBox.rect.maxX - value.location.x
                                let height = cropBox.rect.maxY - value.location.y
                                if width >= minSize && height >= minSize {
                                    newRect = CGRect(
                                        x: value.location.x,
                                        y: value.location.y,
                                        width: width,
                                        height: height
                                    )
                                }
                            case .topRight:
                                let width = value.location.x - cropBox.rect.minX
                                let height = cropBox.rect.maxY - value.location.y
                                if width >= minSize && height >= minSize {
                                    newRect = CGRect(
                                        x: cropBox.rect.minX,
                                        y: value.location.y,
                                        width: width,
                                        height: height
                                    )
                                }
                            case .bottomLeft:
                                let width = cropBox.rect.maxX - value.location.x
                                let height = value.location.y - cropBox.rect.minY
                                if width >= minSize && height >= minSize {
                                    newRect = CGRect(
                                        x: value.location.x,
                                        y: cropBox.rect.minY,
                                        width: width,
                                        height: height
                                    )
                                }
                            case .bottomRight:
                                let width = value.location.x - cropBox.rect.minX
                                let height = value.location.y - cropBox.rect.minY
                                if width >= minSize && height >= minSize {
                                    newRect = CGRect(
                                        x: cropBox.rect.minX,
                                        y: cropBox.rect.minY,
                                        width: width,
                                        height: height
                                    )
                                }
                            }
                            
                            cropBox.rect = newRect
                        }
                        // Handle moving
                        else if cropBox.isMoving, let startPoint = cropBox.dragStart {
                            // Calculate the drag offset
                            let offsetX = value.location.x - startPoint.x
                            let offsetY = value.location.y - startPoint.y
                            
                            // Move the crop box by the offset
                            cropBox.rect = CGRect(
                                x: cropBox.rect.minX + offsetX,
                                y: cropBox.rect.minY + offsetY,
                                width: cropBox.rect.width,
                                height: cropBox.rect.height
                            )
                            
                            // Update the drag start point for the next move
                            cropBox.dragStart = value.location
                        }
                    }
                    .onEnded { _ in
                        cropBox.isResizing = false
                        cropBox.isMoving = false
                        cropBox.activeCorner = nil
                        cropBox.dragStart = nil
                    }
            )
        }
    }
}

#Preview {
    CropBoxOverlayView(onCapture: {
        print("Capture photo")
    })
    .frame(width: 400, height: 600)
    .background(Color.black)
}