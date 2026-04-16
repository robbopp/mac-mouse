// Mouse/Views/ServerPickerView.swift
import SwiftUI

struct ServerPickerView: View {
    @Bindable var connectionVM: ConnectionViewModel
    @State private var manualHost = ""
    @State private var manualPort = "5050"

    var body: some View {
        NavigationStack {
            List {
                // Permission denied banner
                if connectionVM.discoveryPermissionDenied {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Local Network Access Required", systemImage: "wifi.exclamationmark")
                                .font(.headline)
                            Text("Mouse needs permission to find servers on your network.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Discovered servers section
                Section {
                    if connectionVM.discoveredServers.isEmpty {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Searching for Mouse servers…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(connectionVM.discoveredServers) { server in
                            Button {
                                connectionVM.connect(to: server)
                            } label: {
                                HStack {
                                    Image(systemName: "desktopcomputer")
                                    Text(server.displayName)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("On this network")
                }

                // Manual entry section
                Section {
                    TextField("IP Address", text: $manualHost)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $manualPort)
                        .keyboardType(.numberPad)
                    Button("Connect") {
                        guard
                            !manualHost.isEmpty,
                            let port = UInt16(manualPort)
                        else { return }
                        connectionVM.connect(to: .manual(host: manualHost, port: port))
                    }
                    .disabled(manualHost.isEmpty)
                } header: {
                    Text("Connect manually")
                }

                // Error banner
                if case .error(let msg) = connectionVM.connectionState {
                    Section {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Mouse")
        }
    }
}
