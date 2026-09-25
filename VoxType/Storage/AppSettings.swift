import Foundation
import SwiftUI

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    enum ModelOption: String, CaseIterable, Identifiable {
        case largeTurbo = "ggml-large-v3-turbo-q5_0"
        case medium     = "ggml-medium"
        case small      = "ggml-small"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .largeTurbo: return "Large V3 Turbo (Q5, recommended)"
            case .medium:     return "Medium"
            case .small:      return "Small"
            }
        }
        var fileName: String { rawValue + ".bin" }
    }

    enum LanguageOption: String, CaseIterable, Identifiable {
        case auto = "auto"
        case en   = "en"
        case es   = "es"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .auto: return "Auto-detect"
            case .en:   return "English"
            case .es:   return "Español"
            }
        }
    }
    enum LLMProvider: String, CaseIterable, Identifiable {
        case ollama = "ollama"
        case openai = "openai"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .ollama: return "Ollama (Local)"
            case .openai: return "OpenAI (Cloud)"
            }
        }
    }

    enum LLMMode: String, CaseIterable, Identifiable {
        case formatter = "formatter"
        case assistant = "assistant"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .formatter: return "✍️ Formatter"
            case .assistant: return "🤖 Assistant"
            }
        }
    }

    enum FormatterTheme: String, CaseIterable, Identifiable {
        case yellow = "yellow"
        case blue = "blue"
        case turquoise = "turquoise"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .yellow: return "Yellow"
            case .blue: return "Blue"
            case .turquoise: return "Turquoise"
            }
        }
        var color1: Color {
            switch self {
            case .yellow: return .yellow
            case .blue: return .cyan
            case .turquoise: return Color(red: 0.0, green: 0.8, blue: 0.7)
            }
        }
        var color2: Color {
            switch self {
            case .yellow: return .orange
            case .blue: return .blue
            case .turquoise: return Color(red: 0.0, green: 0.4, blue: 0.5)
            }
        }
    }

    enum AssistantTheme: String, CaseIterable, Identifiable {
        case purple = "purple"
        case pink = "pink"
        case lime = "lime"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .purple: return "Purple"
            case .pink: return "Pink"
            case .lime: return "Lime Punch"
            }
        }
        var color1: Color {
            switch self {
            case .purple: return Color(red: 0.8, green: 0.5, blue: 1.0)
            case .pink: return Color(red: 1.0, green: 0.3, blue: 0.6)
            case .lime: return Color(red: 0.7, green: 1.0, blue: 0.0)
            }
        }
        var color2: Color {
            switch self {
            case .purple: return Color(red: 0.4, green: 0.0, blue: 0.8)
            case .pink: return Color(red: 0.8, green: 0.0, blue: 0.3)
            case .lime: return Color(red: 0.2, green: 0.7, blue: 0.0)
            }
        }
    }

    enum WidgetSize: String, CaseIterable, Identifiable {
        case small = "small"
        case medium = "medium"
        case large = "large"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }

    @Published var selectedModel: ModelOption {
        didSet { defaults.set(selectedModel.rawValue, forKey: "selectedModel") }
    }

    @Published var language: LanguageOption {
        didSet { defaults.set(language.rawValue, forKey: "language") }
    }

    @Published var fillerRemovalEnabled: Bool {
        didSet { defaults.set(fillerRemovalEnabled, forKey: "fillerRemovalEnabled") }
    }

    @Published var keepMicWarm: Bool {
        didSet { defaults.set(keepMicWarm, forKey: "keepMicWarm") }
    }

    @Published var ollamaEnabled: Bool {
        didSet { defaults.set(ollamaEnabled, forKey: "ollamaEnabled") }
    }

    @Published var llmProvider: LLMProvider {
        didSet { defaults.set(llmProvider.rawValue, forKey: "llmProvider") }
    }

    @Published var llmMode: LLMMode {
        didSet { defaults.set(llmMode.rawValue, forKey: "llmMode") }
    }

    @Published var formatterTheme: FormatterTheme {
        didSet { defaults.set(formatterTheme.rawValue, forKey: "formatterTheme") }
    }

    @Published var assistantTheme: AssistantTheme {
        didSet { defaults.set(assistantTheme.rawValue, forKey: "assistantTheme") }
    }

    @Published var widgetSize: WidgetSize {
        didSet { defaults.set(widgetSize.rawValue, forKey: "widgetSize") }
    }

    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: "ollamaModel") }
    }

    @Published var openAIKey: String {
        didSet { KeychainStore.set(openAIKey, forKey: "openAIKey") }
    }

    @Published var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: "openAIModel") }
    }

    @Published var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: "systemPrompt") }
    }

    @Published var assistantPrompt: String {
        didSet { defaults.set(assistantPrompt, forKey: "assistantPrompt") }
    }

    @Published var customVocabulary: String {
        didSet { defaults.set(customVocabulary, forKey: "customVocabulary") }
    }

    private init() {
        let modelRaw = defaults.string(forKey: "selectedModel") ?? ModelOption.largeTurbo.rawValue
        self.selectedModel = ModelOption(rawValue: modelRaw) ?? .largeTurbo

        let langRaw = defaults.string(forKey: "language") ?? LanguageOption.auto.rawValue
        self.language = LanguageOption(rawValue: langRaw) ?? .auto

        let sizeRaw = defaults.string(forKey: "widgetSize") ?? WidgetSize.small.rawValue
        self.widgetSize = WidgetSize(rawValue: sizeRaw) ?? .small

        if defaults.object(forKey: "fillerRemovalEnabled") == nil {
            self.fillerRemovalEnabled = true
        } else {
            self.fillerRemovalEnabled = defaults.bool(forKey: "fillerRemovalEnabled")
        }

        self.keepMicWarm = defaults.bool(forKey: "keepMicWarm")
        self.ollamaEnabled = defaults.bool(forKey: "ollamaEnabled")

        let providerRaw = defaults.string(forKey: "llmProvider") ?? LLMProvider.ollama.rawValue
        self.llmProvider = LLMProvider(rawValue: providerRaw) ?? .ollama

        let modeRaw = defaults.string(forKey: "llmMode") ?? LLMMode.formatter.rawValue
        self.llmMode = LLMMode(rawValue: modeRaw) ?? .formatter

        let formatterThemeRaw = defaults.string(forKey: "formatterTheme") ?? FormatterTheme.yellow.rawValue
        self.formatterTheme = FormatterTheme(rawValue: formatterThemeRaw) ?? .yellow

        let assistantThemeRaw = defaults.string(forKey: "assistantTheme") ?? AssistantTheme.purple.rawValue
        self.assistantTheme = AssistantTheme(rawValue: assistantThemeRaw) ?? .purple

        self.ollamaModel = defaults.string(forKey: "ollamaModel") ?? "llama3.2"
        if let legacyKey = defaults.string(forKey: "openAIKey") {
            if !legacyKey.isEmpty { KeychainStore.set(legacyKey, forKey: "openAIKey") }
            defaults.removeObject(forKey: "openAIKey")
        }
        self.openAIKey = KeychainStore.string(forKey: "openAIKey") ?? ""
        self.openAIModel = defaults.string(forKey: "openAIModel") ?? "gpt-4o-mini"

        let strictPipelinePrompt = "You are a raw text formatting pipeline. Your ONLY job is to take the transcribed dictated text, correct its spelling and punctuation, and output ONLY the final corrected text. \nRULES:\n1. NO conversational filler. NO greetings. NO explanations.\n2. DO NOT repeat the original text. Output ONLY the polished version.\n3. Maintain the original language (Spanish/English).\n4. If the text is a single word, just output that word with correct capitalization.\nFailure to obey ruins the user's document."

        let savedPrompt = defaults.string(forKey: "systemPrompt") ?? ""

        if savedPrompt.isEmpty || savedPrompt.contains("Eres un ") {
            self.systemPrompt = strictPipelinePrompt
        } else {
            self.systemPrompt = savedPrompt
        }

        let assistantDefault = "You are a smart AI coding and writing assistant. The user will dictate instructions or requests. Fulfill their request intelligently. Use appropriate formatting such as markdown code blocks if coding, or professional tone if writing an email. DO NOT include unnecessary conversational filler, just provide the answer or result."
        self.assistantPrompt = defaults.string(forKey: "assistantPrompt") ?? assistantDefault

        self.customVocabulary = defaults.string(forKey: "customVocabulary") ?? ""
    }
}
