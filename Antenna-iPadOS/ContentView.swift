//
//  ContentView.swift
//  Antenna-iPadOS
//
//  Created by Dakota Kim on 6/8/25.
//

import SwiftUI
import GameController

struct ContentView: View {
    @State private var axes: [Float] = [0, 0]
    @State private var buttons: [Bool] = Array(repeating: false, count: 4)
    @State private var isRecording = false
    @State private var telemetry: [(String, TimeInterval, [Float])] = []
    @State private var wsTask: URLSessionWebSocketTask? = nil
    @State private var isConnected = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 20) {
                Text("🎮 Controller").font(.headline)

                ForEach(axes.indices, id: \.self) { i in
                    Text("Axis \(i): \(String(format: "%.2f", axes[i]))")
                }

                ForEach(buttons.indices, id: \.self) { i in
                    Text("Button \(i): " + (buttons[i] ? "Pressed" : "Released"))
                }

                Button("Move Servo") {
                    // TODO: POST to Antenna /move
                }
                .buttonStyle(.borderedProminent)

                Toggle("Recording", isOn: $isRecording)
                    .onChange(of: isRecording) { on in
                        // TODO: call /start-recording /stop-recording
                    }

                Button(isConnected ? "Connected" : "Connect to Telemetry") {
                    connectToWebSocket()
                }
                .disabled(isConnected)
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .navigationTitle("Antenna Control")
        } detail: {
            VStack {
                Text("📡 Telemetry").font(.headline)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(telemetry, id: \.1) { entry in
                            let (ts, _, joints) = entry
                            Text("\(ts): [\(joints.map { String(format: "%.2f", $0) }.joined(separator: ", "))]")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Telemetry")
        }
        .onAppear {
            setupGamepad()
        }
    }

    // MARK: - Gamepad

    func setupGamepad() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { notif in
            guard let ctrl = notif.object as? GCController,
                  let pad = ctrl.extendedGamepad else { return }

            pad.valueChangedHandler = { gamepad, element in
                axes[0] = gamepad.leftThumbstick.xAxis.value
                axes[1] = gamepad.leftThumbstick.yAxis.value
                buttons[0] = gamepad.buttonA.isPressed
                buttons[1] = gamepad.buttonB.isPressed
            }
        }
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    // MARK: - WebSocket

    func connectToWebSocket() {
        guard !isConnected else { return }
        let url = URL(string: "ws://192.168.1.47:8000/ws/telemetry")!
        let task = URLSession.shared.webSocketTask(with: url)
        wsTask = task
        task.resume()
        isConnected = true
        receiveMessage()
    }

    func receiveMessage() {
        wsTask?.receive { result in
            switch result {
            case .success(.string(let msg)):
                print("@D \(msg)")
                if let data = msg.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ts = obj["timestamp"] as? String,
                   let jointsD = obj["joints"] as? [Double] {
                    let jointsF = jointsD.map { Float($0) }
                    DispatchQueue.main.async {
                        telemetry.insert((ts, Date().timeIntervalSince1970, jointsF), at: 0)
                        if telemetry.count > 100 { telemetry.removeLast() }
                    }
                }
                receiveMessage() // continue receiving
            case .failure(let error):
                print("WebSocket error: \(error)")
                DispatchQueue.main.async {
                    isConnected = false
                }
            default:
                break
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
