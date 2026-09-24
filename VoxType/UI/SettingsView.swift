import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var connectionStatus: String = ""

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Model", selection: $settings.selectedModel) {
                    ForEach(AppSettings.ModelOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Picker("Language", selection: $settings.language) {
                    ForEach(AppSettings.LanguageOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Remove filler words", isOn: $settings.fillerRemovalEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Keep microphone ready", isOn: $settings.keepMicWarm)
                    Text(settings.keepMicWarm
                         ? "Capture starts instantly and includes the half-second before "
                           + "you press. macOS will show the microphone indicator "
                           + "continuously — audio is held in memory only and never leaves "
                           + "your Mac."
                         : "Off: the microphone opens on each press, which takes about "
                           + "160 ms — words spoken at the very instant you press can be "
                           + "cut off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom Vocabulary")
                    TextField("Product names, technical terms, people — comma separated",
                              text: $settings.customVocabulary, axis: .vertical)
                        .lineLimit(4...8)
                        .textFieldStyle(.roundedBorder)
                    Text("Words the model should expect. Improves accuracy on names it "
                         + "would otherwise guess at.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Appearance") {
                Picker("Widget Size", selection: $settings.widgetSize) {
                    ForEach(AppSettings.WidgetSize.allCases) { sizeOption in
                        Text(sizeOption.displayName).tag(sizeOption)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Post-Processing (LLM)") {
                Toggle("Enable LLM formatting", isOn: $settings.ollamaEnabled)

                if settings.ollamaEnabled {
                    Label("Rewrites text and may translate mixed-language dictation. "
                          + "For exact transcription, leave it off.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Picker("Active Mode", selection: $settings.llmMode) {
                        ForEach(AppSettings.LLMMode.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }.pickerStyle(.segmented)

                    Picker("Provider", selection: $settings.llmProvider) {
                        ForEach(AppSettings.LLMProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }.pickerStyle(.segmented)

                    if settings.llmProvider == .ollama {
                        TextField("Ollama Model", text: $settings.ollamaModel)
                    } else {
                        SecureField("OpenAI API Key", text: $settings.openAIKey)
                        TextField("OpenAI Model", text: $settings.openAIModel)
                    }

                    Picker("Formatter Theme", selection: $settings.formatterTheme) {
                        ForEach(AppSettings.FormatterTheme.allCases) { t in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(LinearGradient(colors: [t.color1, t.color2], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 14, height: 14)
                                    .shadow(color: t.color1.opacity(0.3), radius: 2)
                                Text(t.displayName)
                            }
                            .tag(t)
                        }
                    }.pickerStyle(.menu)

                    Picker("Assistant Theme", selection: $settings.assistantTheme) {
                        ForEach(AppSettings.AssistantTheme.allCases) { t in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(LinearGradient(colors: [t.color1, t.color2], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 14, height: 14)
                                    .shadow(color: t.color1.opacity(0.3), radius: 2)
                                Text(t.displayName)
                            }
                            .tag(t)
                        }
                    }.pickerStyle(.menu)

                    if settings.llmMode == .formatter {
                        TextField("Formatter Prompt", text: $settings.systemPrompt, axis: .vertical)
                            .lineLimit(3...5)
                    } else {
                        TextField("Assistant Prompt", text: $settings.assistantPrompt, axis: .vertical)
                            .lineLimit(3...5)
                    }

                    HStack {
                        Button("Test Connection") {
                            connectionStatus = "Testing..."
                            Task {
                                let isConnected: Bool
                                if settings.llmProvider == .ollama {
                                    isConnected = await OllamaClient().checkConnection()
                                } else {
                                    isConnected = await OpenAIClient().checkConnection(apiKey: settings.openAIKey)
                                }
                                await MainActor.run {
                                    connectionStatus = isConnected ? "✅ Connected to \(settings.llmProvider.displayName)" : "❌ Connection failed"
                                }
                            }
                        }
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section("Shortcut") {
                HStack {
                    Text("Trigger Microphone (Unified)")
                    Spacer()
                    Text("⌥ Space")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(5)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            }

            Section("About") {
                HStack {
                    Text("VoxType")
                    Spacer()
                    Text("v0.1.0")
                        .foregroundStyle(.secondary)
                }
                Text("100% offline voice dictation for macOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 320)
    }
}
