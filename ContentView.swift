//
//  ContentView.swift
//  CrowdFind (iOS)
//
//  Created by Rohan Matta on 9/20/25.
//

import SwiftUI
import CoreBluetooth
import Combine
import MapKit

// --- App Navigation State ---
enum AppScreen {
    case main
    case map
}

// --- Scan State Management ---
enum ScanState {
    case idle
    case scanning
    case results(totalCount: Int, unknownCount: Int, location: CLLocationCoordinate2D)
}

// --- Location Manager ---
// This class works on iOS without changes.
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var currentLocation: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.first?.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager failed with error: \(error.localizedDescription)")
    }
}

// --- BLUETOOTH LOGIC ---
// This class works on iOS without changes.
class BLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals = Set<UUID>()
    private var unknownDeviceCount = 0
    private var locationManager: LocationManager
    
    @Published var scanState: ScanState = .idle
    
    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func reset() {
        scanState = .idle
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            print("iPhone Bluetooth is not available. State: \(central.state)")
        } else {
            print("iPhone Bluetooth is On")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        let rssiThreshold: Int = -70
        guard RSSI.intValue > rssiThreshold else {
            return
        }
        
        let (inserted, _) = discoveredPeripherals.insert(peripheral.identifier)
        if inserted {
            let locationString = if let loc = locationManager.currentLocation {
                "Lat: \(loc.latitude), Lon: \(loc.longitude)"
            } else {
                "Location not available"
            }
            print("Found Device: \(peripheral.name ?? "Unknown") | RSSI: \(RSSI.intValue) | Location: \(locationString)")
            
            if peripheral.name == nil {
                unknownDeviceCount += 1
            }
        }
    }
    
    func startScan() {
        guard centralManager.state == .poweredOn else {
            print("Cannot scan, Bluetooth is not powered on.")
            return
        }
        
        print("Starting 2-second scan...")
        discoveredPeripherals.removeAll()
        unknownDeviceCount = 0
        scanState = .scanning
        
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.stopScan()
        }
    }
    
    private func stopScan() {
        centralManager.stopScan()
        let finalCount = discoveredPeripherals.count
        print("Scan finished. Found \(finalCount) unique devices. (\(unknownDeviceCount) unknown)")
        
        let scanLocation = locationManager.currentLocation ?? CLLocationCoordinate2D(latitude: 37.3347, longitude: -122.0090)
        scanState = .results(totalCount: finalCount, unknownCount: self.unknownDeviceCount, location: scanLocation)
    }
}


// --- Main App View Controller ---
// This works on iOS without changes.
// --- Main App View Controller ---
struct MainAppView: View {
    @State private var currentScreen: AppScreen = .main
    @StateObject private var locationManager = LocationManager()
    @StateObject private var bleScanner: BLEScanner
    
    init() {
        let lm = LocationManager()
        _locationManager = StateObject(wrappedValue: lm)
        _bleScanner = StateObject(wrappedValue: BLEScanner(locationManager: lm))
    }
    
    var body: some View {
        switch currentScreen {
        case .main:
            ContentView(bleScanner: bleScanner, currentScreen: $currentScreen)
        case .map:
            // UPDATED: We now extract and pass the unknownCount to the MapView.
            if case let .results(total, unknown, location) = bleScanner.scanState {
                MapView(deviceCount: total, unknownCount: unknown, centerCoordinate: location, currentScreen: $currentScreen) {
                    bleScanner.reset()
                }
            } else {
                ContentView(bleScanner: bleScanner, currentScreen: $currentScreen)
            }
        }
    }
}


// --- USER INTERFACE (Main Screen) ---
struct ContentView: View {
    @ObservedObject var bleScanner: BLEScanner
    @Binding var currentScreen: AppScreen

    private func crowdLevel(for peopleCount: Int) -> (level: String, range: String) {
        if peopleCount < 5 { return ("Low", "(< 5 People)") }
        else if peopleCount < 15 { return ("Medium", "(5-14 People)") }
        else if peopleCount < 30 { return ("High", "(15-29 People)") }
        else { return ("Very High", "(30+ People)") }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("CROWDSENSE")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
            
            ZStack {
                Circle()
                    .stroke(circleColor().opacity(0.3), lineWidth: 15)
                    .frame(width: 250, height: 250)
                
                switch bleScanner.scanState {
                case .idle:
                    VStack {
                        Text("Ready")
                            .font(.system(size: 60, weight: .bold, design: .rounded))
                        Text("Tap Scan to Start")
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                case .scanning:
                    ProgressView().scaleEffect(2)
                    
                case .results(let totalCount, let unknownCount, _):
                    let peopleCount = unknownCount / 3 + 1 // unknownCount instead of totalCount to improve accuracy
                    let levelInfo = crowdLevel(for: peopleCount)
                    VStack(spacing: 8) {
                        Text("\(peopleCount)")
                            .font(.system(size: 70, weight: .bold, design: .rounded))
                        Text(levelInfo.level.uppercased())
                            .font(.system(size: 20, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("~ \(totalCount) devices (\(unknownCount) unknown)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding(.top, 10)
                    }
                    
                }
            }
            
            Text(statusText())
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if case .results = bleScanner.scanState {
                Button(action: { currentScreen = .map }) {
                    Text("Show on Map")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            
            Button(action: { bleScanner.startScan() }) {
                Text(buttonText())
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(buttonColor())
                    .foregroundColor(.white)
                    .cornerRadius(15)
            }
            .padding(.horizontal)
            .disabled(isButtonDisabled())
            
        }
        .padding()
        // REMOVED: .frame(minWidth: 400, minHeight: 600) - not needed on iOS
    }
    
    // UI Helper Functions... (no changes needed)
    func statusText() -> String {
        switch bleScanner.scanState {
        case .idle: return "Ready to scan for nearby devices."
        case .scanning: return "Scanning for 2 seconds..."
        case .results(let totalCount, _, _): return "Scan complete. Found \(totalCount) devices."
        }
    }
    
    func buttonText() -> String {
        switch bleScanner.scanState {
        case .scanning: return "Scanning..."
        case .idle, .results: return "Start New Scan"
        }
    }
    
    func buttonColor() -> Color {
        switch bleScanner.scanState {
        case .scanning: return .gray
        case .idle, .results: return .blue
        }
    }
    
    func circleColor() -> Color {
        switch bleScanner.scanState {
        case .scanning: return .blue
        case .idle, .results: return .gray
        }
    }
    
    func isButtonDisabled() -> Bool {
        if case .scanning = bleScanner.scanState { return true }
        return false
    }
}


// --- MAP VIEW ---
struct MapView: View {
    let deviceCount: Int
    let unknownCount: Int // NEW: Property to hold the unknown device count.
    let centerCoordinate: CLLocationCoordinate2D
    @Binding var currentScreen: AppScreen
    var onBack: () -> Void
    
    @State private var cameraPosition: MapCameraPosition
    
    // UPDATED: The initializer now accepts unknownCount.
    init(deviceCount: Int, unknownCount: Int, centerCoordinate: CLLocationCoordinate2D, currentScreen: Binding<AppScreen>, onBack: @escaping () -> Void) {
        self.deviceCount = deviceCount
        self.unknownCount = unknownCount
        self.centerCoordinate = centerCoordinate
        self._currentScreen = currentScreen
        self.onBack = onBack
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: centerCoordinate, latitudinalMeters: 400, longitudinalMeters: 400
        )))
    }
    
    private var circleColor: Color {
        // UPDATED: The color is now based on the new formula.
        let peopleCount = unknownCount / 3 + 1
        if peopleCount < 5 { return .green }
        else if peopleCount < 15 { return .yellow }
        else if peopleCount < 30 { return .orange }
        else { return .red }
    }
    
    var body: some View {
        // ...The body of the MapView remains the same.
        let peopleCount = unknownCount / 3 + 1
        ZStack(alignment: .topLeading) {
            Map(position: $cameraPosition) {
                MapCircle(center: centerCoordinate, radius: 5)
                    .foregroundStyle(circleColor.opacity(0.6))
                    .stroke(circleColor.opacity(0.8), lineWidth: 2)
                
                Annotation("\(peopleCount) People", coordinate: centerCoordinate) {
                    VStack {
                        Text("\(peopleCount)")
                            .font(.headline).padding(8)
                            .background(.regularMaterial)
                            .clipShape(Circle()).shadow(radius: 3)
                        Image(systemName: "wifi")
                            .foregroundColor(.blue).font(.title2)
                    }
                }
            }
            .ignoresSafeArea()
            
            Button(action: {
                onBack()
                currentScreen = .main
            }) {
                HStack {
                    Image(systemName: "arrow.left")
                    Text("New Scan")
                }
                .padding(10)
                .background(.regularMaterial)
                .cornerRadius(10)
                .shadow(radius: 3)
                .padding()
            }
        }
    }
}
