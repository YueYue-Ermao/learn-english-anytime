import Foundation

struct GrammarQuestionRequest: Codable {
    let requestId: String
    let sentence: String
    let question: String
    let scenario: String?
}

struct GrammarAlternativeExplanation: Codable {
    let form: String
    let explanationZh: String
}

struct GrammarExample: Codable {
    let english: String
    let chinese: String
    let noteZh: String
}

struct GrammarQuestionResponse: Codable {
    let requestId: String
    let answerZh: String
    let highlightedForm: String
    let grammarPoint: String
    let explanationZh: String
    let structure: String
    let alternatives: [GrammarAlternativeExplanation]
    let examples: [GrammarExample]
    let quickRuleZh: String
    let modelLabel: String?
}

protocol GrammarQuestionProviding {
    func ask(_ request: GrammarQuestionRequest) async throws -> GrammarQuestionResponse
}

final class GrammarQuestionClient: GrammarQuestionProviding {
    private let settings: AppSettings
    private let session: URLSession

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func ask(_ requestValue: GrammarQuestionRequest) async throws -> GrammarQuestionResponse {
        guard let endpoint = grammarEndpoint else {
            throw ContextualTranslationError.endpointNotConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestValue)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ContextualTranslationError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = (try? JSONDecoder().decode(GrammarServiceErrorBody.self, from: data).detail)
                    ?? String(data: data, encoding: .utf8)
                    ?? "未知错误"
                throw ContextualTranslationError.server(
                    status: httpResponse.statusCode,
                    message: String(message.prefix(300))
                )
            }
            return try JSONDecoder().decode(GrammarQuestionResponse.self, from: data)
        } catch let error as ContextualTranslationError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ContextualTranslationError.transport(error.localizedDescription)
        }
    }

    private var grammarEndpoint: URL? {
        guard let configured = settings.contextualTranslationEndpoint else { return nil }
        var components = URLComponents(url: configured, resolvingAgainstBaseURL: false)
        let translationSuffix = "/v1/translations/contextual"
        if let path = components?.path, path.hasSuffix(translationSuffix) {
            components?.path = String(path.dropLast(translationSuffix.count)) + "/v1/grammar/questions"
        } else {
            components?.path = "/v1/grammar/questions"
        }
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }
}

private struct GrammarServiceErrorBody: Codable {
    let detail: String
}
