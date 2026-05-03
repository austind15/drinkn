import SwiftUI
import Combine
import CoreLocation
import UIKit

@MainActor
final class LogBeerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var image: UIImage?
    @Published var note: String = ""
    @Published var locationName: String = ""
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var drinkType: DrinkType = .beer
    @Published var isFetchingLocation = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var didSubmit = false
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    /// Initialize the manager eagerly so iOS knows we are a location-aware app
    /// from the moment the view model is created. (Lazy init means iOS may
    /// never see the app as a location consumer, and Settings → Drink-N
    /// → Location won't appear until then.)
    private let locationManager: CLLocationManager

    override init() {
        locationManager = CLLocationManager()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        super.init()
        locationManager.delegate = self
        authStatus = locationManager.authorizationStatus
    }

    func requestLocation() {
        errorMessage = nil
        let status = locationManager.authorizationStatus
        authStatus = status
        switch status {
        case .notDetermined:
            isFetchingLocation = true
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isFetchingLocation = true
            locationManager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Location is off for Drink-N. Open Settings to enable it."
        @unknown default:
            break
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func clearLocation() {
        latitude = nil
        longitude = nil
    }

    func reset() {
        image = nil
        note = ""
        locationName = ""
        latitude = nil
        longitude = nil
        drinkType = .beer
        errorMessage = nil
        isSubmitting = false
        didSubmit = false
    }

    func submit() async {
        guard let img = image else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await APIClient.shared.logBeer(
                photo: img,
                latitude: latitude,
                longitude: longitude,
                locationName: locationName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : locationName,
                note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note,
                drinkType: drinkType
            )
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authStatus = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.isFetchingLocation = false
                self.errorMessage = "Location permission denied. You can enable it in Settings."
            default:
                self.isFetchingLocation = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.latitude = loc.coordinate.latitude
            self.longitude = loc.coordinate.longitude
            self.isFetchingLocation = false
            self.errorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isFetchingLocation = false
            self.errorMessage = "Couldn't fetch location: \(error.localizedDescription)"
        }
    }
}

struct LogBeerView: View {
    @StateObject private var vm = LogBeerViewModel()
    @State private var showingCamera = false
    @State private var showingConfirmation = false
    @State private var hasAutoOpened = false
    @State private var pendingWarning: DrinkLimitStore.WarningLevel = .none
    @State private var showWarning = false

    var body: some View {
        NavigationStack {
            ZStack {
                if vm.image == nil {
                    primaryCTA
                } else {
                    formView
                }

                if showingConfirmation {
                    confirmationOverlay
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .navigationTitle("Log a drink")
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(sourceType: .camera) { img in
                    vm.image = img
                    showingCamera = false
                } onCancel: {
                    showingCamera = false
                }
                .ignoresSafeArea()
            }
            .onAppear {
                // Auto-open the camera the first time the user lands on this tab,
                // so the Log button is one tap, not two.
                if !hasAutoOpened && vm.image == nil {
                    hasAutoOpened = true
                    showingCamera = true
                }
            }
        }
    }

    private var primaryCTA: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("🍻").font(.system(size: 100))
            Text("Logged a drink? Snap it.")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Button {
                showingCamera = true
            } label: {
                Label("Log a drink 🍺", systemImage: "camera.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .padding(.horizontal, 40)
            Spacer()
        }
        .padding()
    }

    private var formView: some View {
        Form {
            Section("Photo") {
                if let img = vm.image {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button("Retake") { showingCamera = true }
            }

            Section("What's in the glass?") {
                DrinkTypePicker(selection: $vm.drinkType)
                    .padding(.vertical, 4)
            }

            Section {
                locationRow
                TextField("Or type a place — e.g. The Crown Pub", text: $vm.locationName)
            } header: {
                Text("Location (optional)")
            } footer: {
                Text("Coordinates are blurred to ~100 m before storage.")
                    .font(.caption2)
            }

            Section("Note (optional, max 140)") {
                TextField("Post-standup IPA", text: $vm.note, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .onChange(of: vm.note) { _, newVal in
                        if newVal.count > 140 { vm.note = String(newVal.prefix(140)) }
                    }
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err).foregroundStyle(.red)
                    if vm.authStatus == .denied || vm.authStatus == .restricted {
                        Button("Open Settings") { vm.openSettings() }
                    }
                }
            }

            Section {
                Button {
                    let level = DrinkLimitStore.shared.warningLevelForNextDrink()
                    if level == .none {
                        performSubmit()
                    } else {
                        pendingWarning = level
                        showWarning = true
                    }
                } label: {
                    if vm.isSubmitting {
                        HStack { ProgressView(); Text("Submitting…") }
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Submit \(vm.drinkType.emoji)").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(vm.isSubmitting)
            }
        }
        .alert(warningTitle, isPresented: $showWarning) {
            if pendingWarning == .hardLimit {
                Button("OK", role: .cancel) {}
            } else {
                Button("Cancel", role: .cancel) {}
                Button("Log it anyway") { performSubmit() }
            }
        } message: {
            Text(warningMessage)
        }
    }

    private var warningTitle: String {
        switch pendingWarning {
        case .softReminder: return "Pace yourself"
        case .strongWarning: return "Take care of yourself"
        case .hardLimit: return "You've hit today's limit"
        case .none: return ""
        }
    }

    private var warningMessage: String {
        switch pendingWarning {
        case .softReminder:
            return "That's 5+ drinks today. Drink some water, eat something, and check in with how you're feeling."
        case .strongWarning:
            return "You've logged 8+ drinks. This is a lot. Please slow down, hydrate, and consider stopping. If you or someone you're with needs help, call SAMHSA at 1-800-662-4357."
        case .hardLimit:
            return "You've logged 15 drinks today and Drink-N won't accept any more entries until tomorrow. This isn't a punishment — it's a safety limit. Please stop drinking, stay with people you trust, and call 911 if anyone shows signs of alcohol poisoning."
        case .none:
            return ""
        }
    }

    private func performSubmit() {
        Task {
            await vm.submit()
            if vm.didSubmit {
                DrinkLimitStore.shared.recordSubmission()
                withAnimation { showingConfirmation = true }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                withAnimation { showingConfirmation = false }
                vm.reset()
            }
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        if let lat = vm.latitude, let lon = vm.longitude {
            HStack {
                Label(String(format: "%.3f, %.3f", lat, lon), systemImage: "checkmark.circle.fill")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.green)
                Spacer()
                Button("Clear", role: .destructive) { vm.clearLocation() }
                    .font(.caption)
            }
        } else if vm.isFetchingLocation {
            HStack { ProgressView(); Text("Fetching location…") }
        } else if vm.authStatus == .denied || vm.authStatus == .restricted {
            VStack(alignment: .leading, spacing: 8) {
                Label("Location is off for Drink-N", systemImage: "location.slash")
                    .foregroundStyle(.secondary)
                Button("Open Settings") { vm.openSettings() }
                    .font(.caption)
            }
        } else {
            Button {
                vm.requestLocation()
            } label: {
                Label("Use my location", systemImage: "location.fill")
            }
        }
    }

    private var confirmationOverlay: some View {
        VStack(spacing: 12) {
            Text(vm.drinkType.emoji).font(.system(size: 96)).symbolEffect(.bounce, value: showingConfirmation)
            Text("\(vm.drinkType.displayName) logged!").font(.title.bold()).foregroundStyle(.orange)
        }
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 12)
    }
}
