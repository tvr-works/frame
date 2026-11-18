import AppKit
import Common
import FrameEngine

enum GlobalObserver {
    private static func onNotif(session: AppSession, _ notification: Notification) {
        let notifName = notification.name.rawValue
        Task { @MainActor in
            if notifName == NSWorkspace.didActivateApplicationNotification.rawValue {
                session.scheduleRefreshSession(.globalObserver(notifName), optimisticallyPreLayoutWorkspaces: true)
            } else {
                session.scheduleRefreshSession(.globalObserver(notifName))
            }
        }
    }

    @MainActor
    static func initObserver(session: AppSession = currentSession) {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { onNotif(session: session, $0) }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { onNotif(session: session, $0) }
        nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main) { onNotif(session: session, $0) }
        nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main) { onNotif(session: session, $0) }
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { onNotif(session: session, $0) }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { onNotif(session: session, $0) }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            Task { @MainActor in
                do {
                    try await recordMouseDownWindowSize(session: session)
                } catch {
                    session.scheduleRefreshSession(.globalObserver("mouseDown"))
                }
            }
        }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            Task { @MainActor in
                session.updateWindowDrag(at: session.platformServices.mouseLocation())
            }
        }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            onLeftMouseUp(session: session)
        }
        // A drag can end over Frame's own UI, which global event monitors do not receive.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            onLeftMouseUp(session: session)
            return event
        }
    }

    private static func onLeftMouseUp(session: AppSession) {
        Task { @MainActor in
            guard session === currentSession else { return }
            defer {
                clearMouseDownWindowSizes()
                session.cancelWindowDrag()
                session.scheduleRefreshSession(.globalObserverLeftMouseUp)
            }
            do {
                if session.windowDrag != nil {
                    let pointer = session.platformServices.mouseLocation()
                    _ = try await session.runLightSession(.globalObserverLeftMouseUp) {
                        session.finishWindowDrag(at: pointer)
                    }
                    return
                }
                try await resetManipulatedWithMouseIfPossible()
                let pointer = session.platformServices.mouseLocation()
                let clickedMonitor = pointer.monitorApproximation
                let currentFocus = session.focus
                switch true {
                    // Detect clicks on desktop of different monitors
                    case clickedMonitor.activeWorkspace != currentFocus.workspace:
                        _ = try await session.runLightSession(.globalObserverLeftMouseUp) {
                            clickedMonitor.activeWorkspace.focusWorkspace()
                        }
                    // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
                    //  And trigger new window detection that could be delayed due to mouseDown event
                    default:
                        session.scheduleRefreshSession(.globalObserverLeftMouseUp)
                }
            } catch {
                // The deferred refresh restores managed geometry even if a native lookup failed.
            }
        }
    }
}
