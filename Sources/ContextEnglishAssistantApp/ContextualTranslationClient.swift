import ContextEnglishCore
import Foundation

struct TranslationDraft {
    let selectedText: String
    let language: DetectedLanguage
    let context: SelectionTextContext?
    let bounds: CGRect?
    let scenario: String?

    var request: ContextualTranslationRequest {
        ContextualTranslationRequest(
            requestId: UUID().uuidString,
            selectedText: selectedText,
            sourceLanguage: language.rawValue,
            targetLanguage: "auto-opposite",
            surroundingText: context?.text,
            selectionStart: context?.selectionStartUTF16,
            selectionLength: context?.selectionLengthUTF16,
            contextCaptureLevel: context == nil ? "selection_only" : "sentence",
            scenario: scenario
        )
    }
}

struct ContextualTranslationRequest: Codable {
    let requestId: String
    let selectedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let surroundingText: String?
    let selectionStart: Int?
    let selectionLength: Int?
    let contextCaptureLevel: String
    let scenario: String?
}

struct ContextualSelectedMeaning: Codable {
    let source: String
    let target: String
    let partOfSpeech: String?
    let explanationZh: String
}

struct ContextualSentenceTranslation: Codable {
    let source: String
    let target: String
}

struct ContextualTranslationAlternative: Codable {
    let target: String
    let meaningZh: String?
    let differenceZh: String
}

struct ContextualTranslationResponse: Codable {
    let requestId: String
    let sourceLanguage: String
    let targetLanguage: String
    let contextUsed: Bool
    let selectedMeaning: ContextualSelectedMeaning
    let sentence: ContextualSentenceTranslation
    let alternatives: [ContextualTranslationAlternative]
    let modelLabel: String?
}

enum ContextualTranslationError: LocalizedError {
    case endpointNotConfigured
    case invalidResponse
    case server(status: Int, message: String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .endpointNotConfigured:
            return "AI 服务尚未配置。请从学习中心或菜单栏打开“AI 服务设置”。"
        case .invalidResponse:
            return "模型服务返回了无法识别的结果。"
        case .server(let status, let message):
            return "模型服务错误（\(status)）：\(message)"
        case .transport(let message):
            return "无法连接模型服务：\(message)"
        }
    }
}

protocol ContextualTranslationProviding {
    func translate(_ request: ContextualTranslationRequest) async throws -> ContextualTranslationResponse
}

final class ContextualTranslationClient: ContextualTranslationProviding {
    private let settings: AppSettings
    private let session: URLSession

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func translate(_ requestValue: ContextualTranslationRequest) async throws -> ContextualTranslationResponse {
        guard let endpoint = settings.contextualTranslationEndpoint else {
            throw ContextualTranslationError.endpointNotConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestValue)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ContextualTranslationError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = (try? JSONDecoder().decode(ServiceErrorBody.self, from: data).detail)
                    ?? String(data: data, encoding: .utf8)
                    ?? "未知错误"
                throw ContextualTranslationError.server(
                    status: httpResponse.statusCode,
                    message: String(message.prefix(300))
                )
            }
            return try JSONDecoder().decode(ContextualTranslationResponse.self, from: data)
        } catch let error as ContextualTranslationError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ContextualTranslationError.transport(error.localizedDescription)
        }
    }
}

private struct ServiceErrorBody: Codable {
    let detail: String
}
