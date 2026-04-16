//
//  ContentView.swift
//  Mouse
//
//  Created by Robert Oprean on 30.06.2025.
//

import SwiftUI
import Network

struct ContentView: View {
    @State private var connection: NWConnection?
    @State private var lastLocation: CGPoint?
    @State private var deltaToSend: CGPoint = .zero
    @State private var sendingTimer: Timer?

    
    // Your Mac's IP
    let serverIP = "192.168.1.138"
    let serverPort: UInt16 = 5050
    
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    dragAndTapGesture(in: geo.size)
                )
                .onAppear {
                    setupConnection()
                    startSendingLoop()
                }

        }
        .edgesIgnoringSafeArea(.all)
    }

    func dragAndTapGesture(in size: CGSize) -> some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                if let last = lastLocation {
                    let dx = value.location.x - last.x
                    let dy = value.location.y - last.y
                    deltaToSend.x += dx
                    deltaToSend.y += dy
                }
                lastLocation = value.location
            }
            .onEnded { _ in
                lastLocation = nil
            }

        
        let tap = TapGesture()
            .onEnded {
                sendClick()
            }
        
        return SimultaneousGesture(drag, tap)
    }

    
    func setupConnection() {
        let params = NWParameters.udp
        connection = NWConnection(
            host: NWEndpoint.Host(serverIP),
            port: NWEndpoint.Port(rawValue: serverPort)!,
            using: params
        )
        connection?.start(queue: .main)
    }
    
    func sendMove(dx: Double, dy: Double) {
        let scalingFactor = 4.0
        let scaledDx = dx * scalingFactor
        let scaledDy = dy * scalingFactor
        
        let dict: [String: Any] = ["type": "move", "dx": scaledDx, "dy": scaledDy]
        sendDict(dict)
    }

    
    func sendClick() {
        let dict: [String: Any] = ["type": "click"]
        sendDict(dict)
    }
    
    func sendDict(_ dict: [String: Any]) {
        guard let connection = connection else { return }
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }
    
    func startSendingLoop() {
        sendingTimer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            if deltaToSend != .zero {
                sendMove(dx: Double(deltaToSend.x), dy: Double(deltaToSend.y))
                deltaToSend = .zero
            }
        }
    }

}
