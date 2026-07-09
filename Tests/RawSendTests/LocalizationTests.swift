import Foundation
import Testing
@testable import RawSend

@Suite("Localization")
struct LocalizationTests {
    @Test func defaultLanguageIsEnglish() {
        let preferences = AppPreferences()

        #expect(preferences.appLanguage == .english)
        #expect(Localizer.text(.send, language: preferences.appLanguage) == "Send")
        #expect(Localizer.text(.requestTitle, language: preferences.appLanguage) == "Request")
    }

    @Test func chineseLanguageKeepsTechnicalTerms() {
        #expect(Localizer.text(.send, language: .simplifiedChinese) == "发送")
        #expect(Localizer.text(.requestImportantHeaders, language: .simplifiedChinese) == "请求重点 Headers")
        #expect(Localizer.text(.codexConsole, language: .simplifiedChinese) == "Codex 控制台")
    }

    @Test func englishLanguageKeepsTechnicalTerms() {
        #expect(Localizer.text(.requestImportantHeaders, language: .english) == "Important request Headers")
        #expect(Localizer.text(.includeDefaultHeadersInCurl, language: .english) == "Include default headers in cURL export")
        #expect(Localizer.text(.codexConsole, language: .english) == "Codex Console")
        #expect(Localizer.format(.bodyBytes, language: .english, 12) == "Body: 12B")
    }

    @Test func spanishLanguageKeepsTechnicalTerms() {
        #expect(AppLanguage.allCases.contains(.spanish))
        #expect(Localizer.text(.send, language: .spanish) == "Enviar")
        #expect(Localizer.text(.requestImportantHeaders, language: .spanish) == "Headers importantes de la request")
        #expect(Localizer.text(.includeDefaultHeadersInCurl, language: .spanish) == "Incluir headers por defecto en exportación cURL")
        #expect(Localizer.text(.codexConsole, language: .spanish) == "Consola Codex")
        #expect(Localizer.text(.fieldName, language: .spanish) == "Nombre")
        #expect(Localizer.format(.bodyBytes, language: .spanish, 12) == "Body: 12B")
    }

    @Test func everySupportedLanguageHasEveryKey() {
        for language in AppLanguage.allCases {
            let missing = Localizer.missingKeys(for: language)
            #expect(missing.isEmpty, "\(language.rawValue) missing keys: \(missing.map(\.rawValue).joined(separator: ", "))")
        }
    }

    @Test func unknownPersistedLanguageFallsBackToEnglishWithoutDroppingOtherPreferences() throws {
        let data = #"{"appLanguage":"fr","timeoutSeconds":12}"#.data(using: .utf8)!

        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)

        #expect(preferences.appLanguage == .english)
        #expect(preferences.timeoutSeconds == 12)
    }

    @Test func codexPromptUsesSelectedLanguage() {
        let input = CodexRunInput(
            userMessage: "strike auth data",
            configuredUserPrompt: "",
            rawRequest: "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n",
            responseText: "",
            responseLabel: "HTTPS",
            conversation: "user: previous",
            language: .spanish
        )

        let prompt = CodexPrompt.makePrompt(input: input)

        #expect(prompt.contains("Prompt de usuario configurado:"))
        #expect(prompt.contains("Conversación reciente:"))
        #expect(prompt.contains("reply y highlights.reason deben estar escritos en español"))
        #expect(prompt.contains("<response vacía>"))
        #expect(!prompt.contains("你是 RawSend"))
        #expect(!CodexPrompt.outputSchema.contains("Short Chinese response"))
    }
}
