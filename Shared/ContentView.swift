//
//  ContentView.swift
//  Shared
//
//  Created by Scott on 4/8/23.
//
import SwiftUI
import Speech
import Combine
import AVFoundation


struct ContentView: View {
    @State private var recognizedText: String = ""
    @State private var isListening: Bool = false
    @State private var audioEngine: AVAudioEngine = AVAudioEngine()
    @State private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    @State private var request: SFSpeechAudioBufferRecognitionRequest = SFSpeechAudioBufferRecognitionRequest()
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var openAIKey: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var synthesizer = AVSpeechSynthesizer()
    @State private var pauseTimer: Timer?
    // Default the pause timer to 2 seconds
    @State private var pauseTimerInterval: Double = 2.0
    @State private var conversationHistory: [[String: Any]] = [
        ["role": "system", "content": "You are a helpful assistant accessed via a voice interface from Apple devices. Your responses will be read aloud to the user. Please keep your responses brief. If you have a long response, ask the user if they want you to continue. If the user’s input doesn’t quite make sense, it might have been dictated incorrectly: feel free to guess what they really said."]
    ]
    @State private var realTimeRecognizedText: String = ""


    var body: some View {
        VStack {
            TextField("OpenAI API Key", text: $openAIKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Text("Conversation History:")
                .font(.headline)
            
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(conversationHistory.indices, id: \.self) { index in
                            if index > 0 { // Hide the system message at the start
                                let message = conversationHistory[index]
                                let role = message["role"] as? String ?? ""
                                let content = message["content"] as? String ?? ""

                                if role == "user" {
                                    Text("User: \(content)")
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                } else if role == "assistant" {
                                    Text("Assistant: \(content)")
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                } else {
                                    Text(content)
                                }
                            }
                        }
                        // Display the real-time recognized text
                        if !realTimeRecognizedText.isEmpty {
                            Text("User: \(realTimeRecognizedText)")
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .onChange(of: conversationHistory.count) { _ in
                        withAnimation {
                            scrollViewProxy.scrollTo(conversationHistory.count - 1, anchor: .bottom)
                        }
                    }
                    // TODO: This is a hack to get the scroll view to scroll to the bottom when the real-time recognized text changes, but doesn't work when the user is speaking
                    .onChange(of: realTimeRecognizedText) { _ in
                        withAnimation {
                            scrollViewProxy.scrollTo(conversationHistory.count - 1, anchor: .bottom)
                        }
                    }
                }
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
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            requestSpeechRecognitionAuthorization()
        }
        .padding()
    }
    
    func startRecognition() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        // Check if there's an existing tap and remove it
        if inputNode.numberOfInputs > 0 {
            inputNode.removeTap(onBus: 0)
        }
        request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            DispatchQueue.main.async {
                self.alertMessage = "Speech recognition is not available on this device."
                self.showAlert = true
            }
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request, resultHandler: { (result, error) in
            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                    self.realTimeRecognizedText = result.bestTranscription.formattedString
                    print("Recognized text: \(self.recognizedText)") // Debug print statement 1
                    // Stop the assistant's speech when user speech is detected
                    if self.synthesizer.isSpeaking {
                        self.synthesizer.stopSpeaking(at: .immediate)
                    }
                }

                // Reset the timer each time speech is detected
                self.pauseTimer?.invalidate()
                self.pauseTimer = Timer.scheduledTimer(withTimeInterval: self.pauseTimerInterval, repeats: false) { _ in
                    print("Pause detected, calling OpenAI API...")

                    self.stopRecognition()
                    self.isListening = false

                    self.conversationHistory.append(["role": "user", "content": self.recognizedText])
                    
                    self.callOpenAIAPITurbo(model: "gpt-3.5-turbo", messages: self.conversationHistory) { response in
                        self.recognizedText = response
                        self.conversationHistory.append(["role": "assistant", "content": response])
                        self.realTimeRecognizedText = ""
                        self.speakText(response)
                    }
                }
            }
        })

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            self.request.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()
    }
    
    func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        request.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    func callOpenAIAPITurbo(model: String, messages: [[String: Any]], completion: @escaping (String) -> Void) {
        guard !openAIKey.isEmpty else {
            alertMessage = "Please enter your OpenAI API key."
            showAlert = true
            return
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonData: [String: Any] = [
            "model": model,
            "messages": messages
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonData, options: [])

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    alertMessage = "Error connecting to OpenAI API."
                    showAlert = true
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                    let choices = json["choices"] as? [[String: Any]],
                    let message = choices.first?["message"] as? [String: String],
                    let content = message["content"] {
                        DispatchQueue.main.async {
                            completion(content)
                            self.startRecognition() // Restart the recognition process after the assistant's response is spoken

                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        alertMessage = "Error parsing OpenAI API response."
                        showAlert = true
                    }
                }
            } else {
                DispatchQueue.main.async {
                    alertMessage = "Error: Invalid API key or server error."
                    showAlert = true
                }
            }
        }.resume()
    }
    func speakText(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        if let siriVoice4 = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.SiriFemale-compact") {
            utterance.voice = siriVoice4
        } else {
            // Fallback to the default voice if the specified language is not available
            utterance.voice = AVSpeechSynthesisVoice(language: "en")
        }
        synthesizer.speak(utterance)
    }
    func requestSpeechRecognitionAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            switch authStatus {
            case .authorized:
                print("Speech recognition authorized.")
            case .denied:
                print("Speech recognition authorization denied.")
            case .restricted, .notDetermined:
                print("Speech recognition not available.")
            @unknown default:
                print("Unknown authorization status.")
            }
        }
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
