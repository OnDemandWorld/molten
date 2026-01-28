//
//  SettingsView.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var swamaUri: String
    @Binding var ollamaUri: String
    @Binding var ollamaBearerToken: String
    @Binding var systemPrompt: String
    @Binding var vibrations: Bool
    @Binding var colorScheme: AppColorScheme
    @Binding var defaultModel: String
    @Binding var swamaApiKey: String
    @Binding var appUserInitials: String
    @Binding var pingInterval: String
    @Binding var voiceIdentifier: String
    @Binding var swamaStatus: Bool?
    @Binding var ollamaStatus: Bool?
    var save: () -> ()
    var checkServer: () -> ()
    var deleteAll: () -> ()
    var allLanguageModels: [LanguageModelSD]
    var voices: [AVSpeechSynthesisVoice]
    
    @State private var deleteConversationsDialog = false
    
    var body: some View {
        VStack {
            ZStack {
                HStack {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(.label))
                    }
                    
                    
                    Spacer()
                    
                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(.label))
                    }
                }
                
                HStack {
                    Spacer()
                    Text("Settings")
                        .font(.system(size: 16))
                        .fontWeight(.medium)
                        .foregroundStyle(Color(.label))
                    Spacer()
                }
            }
            .padding()
            
            Form {
                // General Settings
                Section(header: Text("General Settings").font(.headline)) {
                    Picker(selection: $defaultModel) {
                        ForEach(allLanguageModels, id:\.self) { model in
                            Text(model.displayName).tag(model.name)
                        }
                    } label: {
                        Label {
                            Text("Default Model")
                        } icon: {
                            Image(systemName: "cpu")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(Color(.label))
                                .frame(width: 24, height: 24)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System prompt")
                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 13))
                            .cornerRadius(4)
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: 100)
                        Text("Sets the AI's behavior and context for new conversations. This is added as the first message when a conversation is empty.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    TextField("Ping Interval (seconds)", text: $pingInterval)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                }
                
                // Ollama Section
                Section(header: Text("Ollama").font(.headline)) {
                    TextField("Ollama server URI", text: $ollamaUri, onCommit: checkServer)
                        .textContentType(.URL)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if !os(macOS)
                        .padding(.top, 8)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
#endif
                    
                    if let status = ollamaStatus {
                        HStack {
                            Text(status ? "Connected" : "Not Connected")
                                .foregroundStyle(status ? .green : .red)
                            Spacer()
                        }
                    }
                    
                    TextField("Bearer Token (optional)", text: $ollamaBearerToken)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                        .autocapitalization(.none)
#endif
                }
                
                // Swama Section
                Section(header: Text("Swama").font(.headline)) {
                    TextField("Swama server URI", text: $swamaUri, onCommit: checkServer)
                        .textContentType(.URL)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if !os(macOS)
                        .padding(.top, 8)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
#endif
                    
                    if let status = swamaStatus {
                        HStack {
                            Text(status ? "Connected" : "Not Connected")
                                .foregroundStyle(status ? .green : .red)
                            Spacer()
                        }
                    }
                    
                    TextField("Bearer Token (optional)", text: $swamaApiKey)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                        .autocapitalization(.none)
#endif
                }
                
                // App Section
                Section(header: Text("App").font(.headline)) {
#if os(iOS)
                    Toggle(isOn: $vibrations, label: {
                        Label("Vibrations", systemImage: "water.waves")
                            .foregroundStyle(Color.label)
                    })
#endif
                    
                    Picker(selection: $colorScheme) {
                        ForEach(AppColorScheme.allCases, id:\.self) { scheme in
                            Text(scheme.toString).tag(scheme.id)
                        }
                    } label: {
                        Label("Appearance", systemImage: "sun.max")
                            .foregroundStyle(Color.label)
                    }
                    
                    Picker(selection: $voiceIdentifier) {
                        ForEach(voices, id:\.self.identifier) { voice in
                            Text(voice.prettyName).tag(voice.identifier)
                        }
                    } label: {
                        Label("Voice", systemImage: "waveform")
                            .foregroundStyle(Color.label)
                        
#if os(macOS)
                        Text("Download voices by going to Settings > Accessibility > Spoken Content > System Voice > Manage Voices.")
#else
                        Text("Download voices by going to Settings > Accessibility > Spoken Content > Voices.")
#endif
                        
                        Button(action: {
#if os(macOS)
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpeakableItems") {
                                NSWorkspace.shared.open(url)
                            }
#else
                            let url = URL(string: "App-Prefs:root=General&path=ACCESSIBILITY")
                            if let url = url, UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            }
#endif
                            
                        }) {
                            
                            Text("Open Settings")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Initials", text: $appUserInitials)
                            .disableAutocorrection(true)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
#if os(iOS)
                            .keyboardType(.default)
                            .autocapitalization(.allCharacters)
#endif
                        Text("Used to display your initials in chat messages (e.g., \"AM\" instead of \"User\")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(action: {deleteConversationsDialog.toggle()}) {
                        HStack {
                            Spacer()
                            
                            Text("Clear All Data")
                                .foregroundStyle(Color(.systemRed))
                                .padding(.vertical, 6)
                            
                            Spacer()
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .preferredColorScheme(colorScheme.toiOSFormat)
        .confirmationDialog("Delete All Conversations?", isPresented: $deleteConversationsDialog) {
            Button("Delete", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Delete All Conversations?")
        }
    }
}

#Preview {
    SettingsView(
        swamaUri: .constant(""),
        ollamaUri: .constant(""),
        ollamaBearerToken: .constant(""),
        systemPrompt: .constant("You are an intelligent assistant solving complex problems. You are an intelligent assistant solving complex problems. You are an intelligent assistant solving complex problems."),
        vibrations: .constant(true),
        colorScheme: .constant(.light),
        defaultModel: .constant("qwen3"),
        swamaApiKey: .constant(""),
        appUserInitials: .constant("AM"),
        pingInterval: .constant("5"),
        voiceIdentifier: .constant("sample"),
        swamaStatus: .constant(nil),
        ollamaStatus: .constant(nil),
        save: {},
        checkServer: {},
        deleteAll: {},
        allLanguageModels: LanguageModelSD.sample,
        voices: []
    )
}

