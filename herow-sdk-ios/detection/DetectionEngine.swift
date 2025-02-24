//
//  DetectionEngine.swift
//  herow-sdk-ios
//
//  Created by Damien on 27/01/2021.
//

import Foundation
import CoreLocation
import UIKit
@objc public enum UpdateType: Int {
    case update
    case geofence
    case fake
    case undefined
}
@objc public protocol DetectionEngineListener: class {
    func onLocationUpdate(_ location: CLLocation, from: UpdateType)
    
}


public class DetectionEngine: NSObject, LocationManager, CLLocationManagerDelegate, ConfigListener, AppStateDelegate {

    internal var isUpdatingPosition = false
    internal var isUpdatingSignificantChanges = false
    internal var isMonitoringRegion = false
    internal  var isMonitoringVisit = false
    internal var bgTaskManager = BackgroundTaskManager(app: UIApplication.shared, name: "io.herow.backgroundDetectionTask")
    private let timeIntervalLimit: TimeInterval = 2 * 60 * 60 // 2 hours
    private let dataHolder =  DataHolderUserDefaults(suiteName: "LocationManagerCoreLocation")
    private var locationManager: LocationManager
    private var skipCount = 0
    internal var lastLocation: CLLocation?
    internal var monitoringListeners: [WeakContainer<ClickAndConnectListener>] = [WeakContainer<ClickAndConnectListener>]()
    internal var detectionListners: [WeakContainer<DetectionEngineListener>] = [WeakContainer<DetectionEngineListener>]()
    internal var dispatchTime = Date(timeIntervalSince1970: 0)
    private var timeProvider: TimeProvider


    public var showsBackgroundLocationIndicator: Bool {
        get {
            if #available(iOS 11.0, *) {
                return self.locationManager.showsBackgroundLocationIndicator
            } else {
                return false
            }
        }
        set(newValue) {
            if #available(iOS 11.0, *) {
                self.locationManager.showsBackgroundLocationIndicator = newValue
            } else {
                // Fallback on earlier versions
            }
        }
    }


    public var location: CLLocation? {
        get {
            return self.locationManager.location
        }
    }

    public var heading: CLHeading? {
        get {
            return self.locationManager.heading
        }
    }

    public var delegate: CLLocationManagerDelegate? {
        get {
            return self.locationManager.delegate
        }
        set(delegate) {
            self.locationManager.delegate = delegate
        }
    }

    public var pausesLocationUpdatesAutomatically: Bool {
        get {
            return self.locationManager.pausesLocationUpdatesAutomatically
        }
        set(pausesLocationUpdatesAutomatically) {
            self.locationManager.pausesLocationUpdatesAutomatically = pausesLocationUpdatesAutomatically
        }
    }

    public var allowsBackgroundLocationUpdates: Bool {
        get {
            return self.locationManager.allowsBackgroundLocationUpdates
        }
        set(allowsBackgroundLocationUpdates) {
            self.locationManager.allowsBackgroundLocationUpdates = allowsBackgroundLocationUpdates
        }
    }

    public var distanceFilter: CLLocationDistance {
        get {
            return self.locationManager.distanceFilter
        }
        set(distanceFilter) {
            self.locationManager.distanceFilter = distanceFilter
        }
    }

    public var desiredAccuracy: CLLocationAccuracy {
        get {
            return self.locationManager.desiredAccuracy
        }
        set(desiredAccuracy) {
            self.locationManager.desiredAccuracy = desiredAccuracy
        }
    }

    public var activityType: CLActivityType {
        get {
            return self.locationManager.activityType
        }
        set(activityType) {
            self.locationManager.activityType = activityType
        }
    }

    public func getMonitoredRegions() -> Set<CLRegion> {
        return self.locationManager.getMonitoredRegions()
    }

    public init(_ locationManager: LocationManager, timeProvider: TimeProvider = TimeProviderAbsolute()) {
        self.locationManager = locationManager
        self.timeProvider = timeProvider
        super.init()
        initBackgroundCapabilities()
        self.updateClickAndCollectState()
        self.locationManager.delegate = self
    }

    func initBackgroundCapabilities() {
        self.locationManager.allowsBackgroundLocationUpdates =  authorizationStatus() != .authorizedAlways ? false : configureBackgroundLocationUpdates()
    }

    public func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    public func authorizationStatus() -> CLAuthorizationStatus {
        return self.locationManager.authorizationStatus()
    }

    public func authorizationStatusString() -> String {
        return self.locationManager.authorizationStatusString()
    }

    public func setIsOnClickAndCollect(_ value: Bool) {

        if self.getIsOnClickAndCollect() != value {
            self.dataHolder.putBoolean(key: "isLocationMonitoring", value: value)
            self.dataHolder.apply()
            if( authorizationStatus() != .authorizedAlways) {
                self.locationManager.allowsBackgroundLocationUpdates = value
            }
            self.showsBackgroundLocationIndicator = value
            self.updateClickAndCollectState()
        }
    }

    private func setLastClickAndCollectActivationDate(_ value: Date?) {

        guard let value = value else {
            return dataHolder.remove(key: "lastClickAndCollectActivationDate")
        }
        self.dataHolder.putDate(key: "lastClickAndCollectActivationDate", value: value)
        self.dataHolder.apply()
    }

    private func getLastClickAndCollectActivationDate() -> Date? {

        return dataHolder.getDate(key: "lastClickAndCollectActivationDate")

    }

    private func checkLastClickAndCollectActivationDate() -> Bool {

        guard let date = getLastClickAndCollectActivationDate() else {
            return true
        }
        return Date() < Date(timeInterval: timeIntervalLimit, since: date)
    }


    private func checkClickAndCollectMode() -> Bool {

        let value = (isMonitoringVisit || isUpdatingPosition || isMonitoringRegion || isUpdatingSignificantChanges) &&   getIsOnClickAndCollect()
        let result = value && checkLastClickAndCollectActivationDate()
        setIsOnClickAndCollect(result)


        return value
    }
    public func updateClickAndCollectState() {
        if checkClickAndCollectMode() {
            if getLastClickAndCollectActivationDate() == nil {
                setLastClickAndCollectActivationDate(Date())
                didStartClickAndCollect()
            }
        } else {
            if getLastClickAndCollectActivationDate() != nil {
                setLastClickAndCollectActivationDate(nil)
                didStopClickAndCollect()
            }
        }
    }

    public func getIsOnClickAndCollect() -> Bool {
        return dataHolder.getBoolean(key: "isLocationMonitoring")
    }

    @available(iOS 14.0, *)
    public func accuracyAuthorizationStatus() -> CLAccuracyAuthorization {
        return locationManager.accuracyAuthorizationStatus()
    }

    public func accuracyAuthorizationStatusString() -> String {
        return self.locationManager.accuracyAuthorizationStatusString()

    }

    public func locationServicesEnabled() -> Bool {
        return self.locationManager.locationServicesEnabled()
    }

    public func startMonitoring(region: CLRegion) {
        GlobalLogger.shared.debug("startMonitoring in \(region.identifier)")
        isMonitoringRegion = true
        updateClickAndCollectState()
        locationManager.startMonitoring(region: region)
    }

    public func stopMonitoring(region: CLRegion) {
        GlobalLogger.shared.debug("stopMonitoring in \(region.identifier)")
        isMonitoringRegion = false
        updateClickAndCollectState()
        locationManager.stopMonitoring(region: region)
    }


    public func startMonitoringSignificantLocationChanges() {
        if locationServicesEnabled() {
            isUpdatingSignificantChanges = true
            updateClickAndCollectState()
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    public func stopMonitoringSignificantLocationChanges() {
        isUpdatingSignificantChanges = false
        updateClickAndCollectState()
        locationManager.stopMonitoringSignificantLocationChanges()
    }

    public func startUpdatingLocation() {
        if locationServicesEnabled() {
            isUpdatingPosition = true
            updateClickAndCollectState()
            locationManager.startUpdatingLocation()
        }
    }

    public func stopUpdatingLocation() {
        isUpdatingPosition = false
        updateClickAndCollectState()
        locationManager.stopUpdatingLocation()
    }

    public func startMonitoringVisits() {
        isMonitoringVisit = true
        updateClickAndCollectState()
        locationManager.startMonitoringVisits()
    }

    public func stopMonitoringVisits() {
        isMonitoringVisit = false
        updateClickAndCollectState()
        locationManager.stopMonitoringVisits()
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        GlobalLogger.shared.warning("locationManager monitoringDidFailFor \( String(describing: region?.identifier)), withError \(error.localizedDescription)")
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        GlobalLogger.shared.debug("locationManager didChangeAuthorization \( String(describing: status.rawValue))")
    }

    @available(iOS 14.0, *)
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        GlobalLogger.shared.debug("locationManager didChangeAuthorization \( String(describing: CLLocationManager.authorizationStatus().rawValue)) precision \(manager.accuracyAuthorization.rawValue)")
    }

    private func didStartClickAndCollect() {
        self.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        GlobalLogger.shared.verbose("DetectionEngine - didStartClickAndCollect")
        for listener in monitoringListeners {
            listener.get()?.didStartClickAndConnect()
        }
    }

    private func didStopClickAndCollect() {
        self.desiredAccuracy = kCLLocationAccuracyHundredMeters
        GlobalLogger.shared.verbose("DetectionEngine - didStopClickAndCollect")
        for listener in monitoringListeners {
            listener.get()?.didStopClickAndConnect()
        }
    }

    @objc public func registerClickAndCollectListener(listener: ClickAndConnectListener) {
        let first = monitoringListeners.first {
            ($0.get() === listener) == true
        }
        if first == nil {
            monitoringListeners.append(WeakContainer<ClickAndConnectListener>(value: listener))
        }
    }

    @objc public func unregisterClickAndCollectListener(listener: ClickAndConnectListener) {
        monitoringListeners = monitoringListeners.filter {
            ($0.get() === listener) == false
        }
    }

    @objc public func registerDetectionListener(listener: DetectionEngineListener) {
        let first = detectionListners.first {
            ($0.get() === listener) == true
        }
        if first == nil {
            detectionListners.append(WeakContainer<DetectionEngineListener>(value: listener))
        }
    }

    @objc public func unregisterDetectionListener(listener: DetectionEngineListener) {
        detectionListners = detectionListners.filter {
            ($0.get() === listener) == false
        }
    }

    func dispatchLocation(_ location: CLLocation, from: UpdateType = .undefined) -> Bool{
        bgTaskManager.start()
        var skip = false
        var distance = 0.0
        let distpatchTimeKO = abs(dispatchTime.timeIntervalSince1970 - timeProvider.getTime()) < 3
        if let lastLocation = self.lastLocation {
            let distanceKO =  lastLocation.distance(from: location) < 30
            let timeKO = (location.timestamp.timeIntervalSince1970 - lastLocation.timestamp.timeIntervalSince1970) < 10

            distance = lastLocation.distance(from: location)
            skip = distanceKO && timeKO && skipCount < 5
        }
        skip = skip || distpatchTimeKO
        if skip == false {
            if  self.lastLocation == nil {
                GlobalLogger.shared.debug("DetectionEngine - first location : \(location), accuracy: \(location.horizontalAccuracy)")
            }
            skipCount = 0
            self.lastLocation = location
            GlobalLogger.shared.debug("DetectionEngine - dispatchLocation : \(location) DISTANCE FROM LAST : \(distance), ")
            dispatchTime = Date(timeIntervalSince1970: timeProvider.getTime())
            for listener in  detectionListners {
                listener.get()?.onLocationUpdate(location, from: from)
            }
        } else {
            skipCount = skipCount + 1
            GlobalLogger.shared.debug("DetectionEngine - skip location : \(location) DISTANCE FROM LAST : \(distance)")
        }
        bgTaskManager.stop()
        return !skip
    }



    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

        if  let location: CLLocation =  locations.last {

            if location.timestamp.timeIntervalSince(Date()) < 20 {
                GlobalLogger.shared.debug("didUpdate - last location: \(location.coordinate.latitude),"
                                            + "\(location.coordinate.longitude) - \(location.timestamp)")
            _ = dispatchLocation(location, from: .update)
            }
        }
    }

    func extractLocationAfterRegionUpdate() {
        if let location = locationManager.location {
            GlobalLogger.shared.debug("extractLocationAfterRegionUpdate - \(location.coordinate.latitude), \(location.coordinate.longitude)")
            _ = dispatchLocation(location, from:.geofence)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        GlobalLogger.shared.debug("enter in region \(region) - start updating location")
        if LocationUtils.isGeofenceRegion(region) {
            extractLocationAfterRegionUpdate()
        } else {
            GlobalLogger.shared.debug("it's not a geofence region - we do not extract a location")
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        GlobalLogger.shared.debug("exit from region \(region) - start updating location")
        if LocationUtils.isGeofenceRegion(region) {
            extractLocationAfterRegionUpdate()
        } else {
            GlobalLogger.shared.debug("it's not a geofence region - we do not extract a location")
        }
    }

    func didRecievedConfig(_ config: APIConfig) {
        
        if config.enabled {
            startWorking()
        } else {
            stopWorking()
        }
    }

    func startWorking() {
        self.startUpdatingLocation()
        self.startMonitoringSignificantLocationChanges()
    }

    func stopWorking() {
        self.stopUpdatingLocation()
        self.stopMonitoringSignificantLocationChanges()
    }

    public func onAppInForeground() {
        bgTaskManager.onAppInForeground()
    }

    public func onAppInBackground() {
        bgTaskManager.onAppInBackground()
    }

   @objc public func dispatchFakeLocation() {
        let location = LocationUtils.randomLocation()
        for listener in  detectionListners {
            listener.get()?.onLocationUpdate(location, from: .fake)
        }
    }

}
