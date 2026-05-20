//
//  ScreenCaptureOverlayWindowController.swift
//  iamge-detection
//

import SwiftUI
import UIKit

@MainActor
final class ScreenCaptureOverlayWindowController {
    static let shared = ScreenCaptureOverlayWindowController()

    private var overlayWindow: UIWindow?

    private init() {}

    func present(viewModel: ImageClassifierViewModel, onStop: @escaping () -> Void) {
        guard overlayWindow == nil else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let collapsedSize = ScreenCaptureOverlayMetrics.collapsedSize
        let bounds = scene.screen.bounds
        let safe = scene.keyWindow?.safeAreaInsets ?? .zero

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        window.frame = CGRect(
            x: bounds.width - collapsedSize.width - 16,
            y: safe.top + 12,
            width: collapsedSize.width,
            height: collapsedSize.height
        )

        let controller = UIHostingController(
            rootView: ScreenCaptureOverlayView(
                viewModel: viewModel,
                onStop: { [weak self] in
                    onStop()
                    self?.dismiss()
                },
                onResize: { [weak window] size in
                    guard let window else { return }
                    var frame = window.frame
                    let maxY = frame.maxY
                    let maxX = frame.maxX
                    frame.size = size
                    frame.origin.x = max(8, min(maxX - size.width, bounds.width - size.width - 8))
                    frame.origin.y = max(safe.top + 8, min(maxY - size.height, bounds.height - size.height - safe.bottom - 8))
                    window.frame = frame
                },
                onDrag: { [weak window] translation in
                    guard let window else { return }
                    var frame = window.frame
                    frame.origin.x += translation.width
                    frame.origin.y += translation.height
                    frame.origin.x = max(8, min(frame.origin.x, bounds.width - frame.width - 8))
                    frame.origin.y = max(safe.top + 8, min(frame.origin.y, bounds.height - frame.height - safe.bottom - 8))
                    window.frame = frame
                }
            )
        )
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false

        window.rootViewController = controller
        window.isHidden = false
        overlayWindow = window
    }

    func dismiss() {
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil
    }
}

enum ScreenCaptureOverlayMetrics {
    static let collapsedSize = CGSize(width: 220, height: 88)
    static let expandedSize = CGSize(width: 300, height: 176)
}
