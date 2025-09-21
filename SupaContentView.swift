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
        
        // --- NEW: Insert data into Supabase using inputData ---
        let peopleCount = unknownDeviceCount / 3 + 1
        inputData(
            peopleCount: peopleCount,
            latitude: scanLocation.latitude,
            longitude: scanLocation.longitude
        ) {
            print("Inserted crowd data successfully.")
        }
        // --- END NEW ---
        
        scanState = .results(totalCount: finalCount, unknownCount: self.unknownDeviceCount, location: scanLocation)
    }
}


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
            MapView(currentScreen: $currentScreen) {
                bleScanner.reset()
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
                    let peopleCount = unknownCount / 3 + 1
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
    }
    
    // UI Helper Functions
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

// --- NEW: Swift model for map ---
struct ScanResult: Identifiable {
    let id: Int
    let peopleCount: Int
    let latitude: Double
    let longitude: Double
    let createdAt: String
}

// --- MAP VIEW ---
struct MapView: View {
    @Binding var currentScreen: AppScreen
    var onBack: () -> Void
    
    @State private var allScanResults: [ScanResult] = []
    
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9526, longitude: -75.1652), // Default to Philly
        latitudinalMeters: 10000,
        longitudinalMeters: 10000
    ))
    
    init(currentScreen: Binding<AppScreen>, onBack: @escaping () -> Void) {
        self._currentScreen = currentScreen
        self.onBack = onBack
    }
    
    private func circleColor(for peopleCount: Int) -> Color {
        if peopleCount < 5 { return .green }
        else if peopleCount < 15 { return .yellow }
        else if peopleCount < 30 { return .orange }
        else { return .red }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $cameraPosition) {
                ForEach(allScanResults) { result in
                    let coordinate = CLLocationCoordinate2D(latitude: result.latitude, longitude: result.longitude)
                    let color = circleColor(for: result.peopleCount)
                    
                    MapCircle(center: coordinate, radius: 50)
                        .foregroundStyle(color.opacity(0.6))
                        .stroke(color.opacity(0.8), lineWidth: 2)
                    
                    Annotation("\(result.peopleCount) People", coordinate: coordinate) {
                        Text("\(result.peopleCount)")
                            .font(.headline).padding(8)
                            .background(.regularMaterial)
                            .clipShape(Circle()).shadow(radius: 3)
                    }
                }
            }
            .ignoresSafeArea()
            .task {
                // Fetch from Supabase REST
                var req = makeRequest(path: "WhereTheCrowdAt?select=*")
                URLSession.shared.dataTask(with: req) { data, _, error in
                    if let error = error {
                        print("Fetch error: \(error)")
                        return
                    }
                    guard let data = data,
                          let rows = try? JSONDecoder().decode([CrowdRow].self, from: data) else {
                        print("Decode error")
                        return
                    }
                    DispatchQueue.main.async {
                        allScanResults = rows.map {
                            ScanResult(id: $0.ID,
                                       peopleCount: $0.people_count,
                                       latitude: $0.Latitude,
                                       longitude: $0.Longitude,
                                       createdAt: $0.created_at)
                        }
                    }
                }.resume()
            }
            
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


