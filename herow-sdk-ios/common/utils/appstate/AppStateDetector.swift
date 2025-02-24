//
//  AppStateDetector.swift
//  ConnectPlaceCommon
//
//  Created by Connecthings on 04/07/2017.
//  Copyright © 2017 Connecthings. All rights reserved.
//

import Foundation
import UIKit
@objc public class AppStateDetector: NSObject, AppStateDelegate {

    var appStateDelegates: [WeakContainer<AppStateDelegate>]
    var isOnBackground: Bool
    internal var bgTaskManager = BackgroundTaskManager(app: UIApplication.shared, name: "io.herow.backgroundDetectionTask")
    public override init() {
        appStateDelegates = [WeakContainer<AppStateDelegate>]()
        isOnBackground = true
        super.init()
        self.listenForAppStateChanges()
    }

    deinit {
        self.unlistenForAppStateChanges()
    }

    public func registerAppStateDelegate(appStateDelegate: AppStateDelegate) {
        appStateDelegates.append(WeakContainer(value: appStateDelegate))
        if isOnBackground {
            appStateDelegate.onAppInBackground()
        } else {
            appStateDelegate.onAppInForeground()
        }
    }

    public func unregisterAppStateDelegate(appStateDelegate: AppStateDelegate) {
        appStateDelegates = appStateDelegates.filter({ (delegate: WeakContainer<AppStateDelegate>) -> Bool in
            return delegate.get() !== appStateDelegate
        })
    }

    public func onAppInForeground() {
        if isOnBackground {
            GlobalLogger.shared.debug("appStateDetector - inForeground")
            isOnBackground = false
            for delegate in appStateDelegates {
                delegate.get()?.onAppInForeground()
            }
        }
    }

    public func onAppInBackground() {
        bgTaskManager.start()
        if !isOnBackground {
            GlobalLogger.shared.debug("appStateDetector - inBackground")
            isOnBackground = true
            for delegate in self.appStateDelegates {
                delegate.get()?.onAppInBackground()
            }
        }
        bgTaskManager.stop()
    }

    public func onAppTerminated() {
        onAppInBackground()
        for delegate in appStateDelegates {
            delegate.get()?.onAppTerminated?()
        }
    }
}

extension AppStateDetector {
    internal func listenForAppStateChanges() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppInBackground),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppInBackground),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppTerminated),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppInForeground),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppInBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)



    }

    internal func unlistenForAppStateChanges() {
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.willResignActiveNotification,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.willTerminateNotification,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.didBecomeActiveNotification,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.didEnterBackgroundNotification,
                                                  object: nil)
    }
}
