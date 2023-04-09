//
//  ContentView.swift
//  GPT Voice Chat WatchKit Extension
//
//  Created by Scott on 4/9/23.
//

import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @State private var recognizedText: String = ""
    @State private var isListening: Bool = false

    var body: some View {
        VStack {
            Text("Recognized Text:")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recognizedText)
                }
                .padding()
            }

            HStack {
                Button(action: {
                    if isListening {
                        stopRecognition()
                    } else {
                        startRecognition()
                    }
                    isListening.toggle()
                }) {
                    Text(isListening ? "Stop Listening" : "Start Listening")
                }
            }
            .padding()
        }
        .padding()
    }
    
    func startRecognition() {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["command": "startRecognition"], replyHandler: { response in
                if let recognizedText = response["recognizedText"] as? String {
                    DispatchQueue.main.async {
                        self.recognizedText = recognizedText
                    }
                }
            }, errorHandler: { error in
                print("Error sending startRecognition command: \(error.localizedDescription)")
            })
        }
    }
    
    func stopRecognition() {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["command": "stopRecognition"], replyHandler: nil, errorHandler: { error in
                print("Error sending stopRecognition command: \(error.localizedDescription)")
            })
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
