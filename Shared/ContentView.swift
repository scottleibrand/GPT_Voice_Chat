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


    var body: some View {
        VStack {
            TextField("OpenAI API Key", text: $openAIKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Text("Recognized Text:")
                .font(.headline)
            
            ScrollView {
                Text(recognizedText)
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
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            DispatchQueue.main.async {
                self.alertMessage = "Speech recognition is not available on this device."
                self.showAlert = true
            }
            return
        }
        //request.shouldReportPartialResults = true
        //request.taskHint = .dictation // Add this line to set the task hint to dictation

        recognitionTask = speechRecognizer.recognitionTask(with: request, resultHandler: { (result, error) in
            if let result = result {
                DispatchQueue.main.async {
                    self.recognizedText = result.bestTranscription.formattedString
                    print("Recognized text: \(self.recognizedText)") // Debug print statement 1

                }
                
                // A pause in speech is detected or an error occurs
                print("result.isFinal: \(result.isFinal)") // Debug print statement 3
                print("error: \(error)") // Debug print statement 4
                
                if result.isFinal && (error == nil) {
                    print("Finished recognition, calling OpenAI API...") // Debug print statement 2
                    self.stopRecognition()
                    self.isListening = false

                    let messages: [[String: Any]] = [
                        ["role": "system", "content": "You are a helpful assistant accessed via a voice interface from Apple devices. Your responses will be read aloud to the user. Please keep your responses brief. If you have a long response, ask the user if they want you to continue. If the user’s input doesn’t quite make sense, it might have been dictated incorrectly: feel free to guess what they really said."],
                        ["role": "user", "content": self.recognizedText]
                    ]
                    
                    self.callOpenAIAPITurbo(model: "gpt-3.5-turbo", messages: messages) { response in
                        self.recognizedText = response
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
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
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
