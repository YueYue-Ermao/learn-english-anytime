import AppKit
import Combine
import ContextEnglishCore
import Foundation
import SwiftUI
import Translation

struct LocalTranslationResult: Equatable, Sendable {
    let sourceText: String
    let targetText: String
    let sourceLanguage: String
    let targetLanguage: String
    let usedSentenceContext: Bool
}

enum LocalTranslationError: LocalizedError {
    case unsupportedSystem
    case unsupportedLanguagePair
    case languagePackNotInstalled
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "本机翻译需要 macOS 15 或更高版本。"
        case .unsupportedLanguagePair:
            return "Apple 本机翻译暂不支持当前语言组合。"
        case .languagePackNotInstalled:
            return "中英文翻译资源尚未安装。请连接网络后重试，并在系统提示中允许下载语言包。"
        case .unavailable:
            return "本机翻译组件暂时不可用，请稍后重试。"
        case .failed(let message):
            return "本机翻译失败：\(message)"
        }
    }
}

@MainActor
protocol LocalTranslationProviding: AnyObject {
    var hostView: NSView { get }
    func translate(_ draft: TranslationDraft) async throws -> LocalTranslationResult
}

@available(macOS 15.0, *)
@MainActor
final class AppleLocalTranslationService: LocalTranslationProviding {
    private let bridge = AppleTranslationBridge()

    lazy var hostView: NSView = {
        let view = NSHostingView(rootView: AppleTranslationHostView(bridge: bridge))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    func translate(_ draft: TranslationDraft) async throws -> LocalTranslationResult {
        try Task.checkCancellation()

        let languages = languagePair(for: draft.language)
        let sourceText = draft.context?.text ?? draft.selectedText
        let usedSentenceContext = draft.context.map {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                != draft.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? false
        let request = AppleTranslationRequest(
            id: UUID(),
            sourceText: sourceText,
            sourceLanguage: languages.source,
            targetLanguage: languages.target,
            usedSentenceContext: usedSentenceContext
        )

        return try await withTaskCancellationHandler {
            try await bridge.submit(request)
        } onCancel: {
            Task { @MainActor [weak bridge] in
                bridge?.cancel(requestID: request.id)
            }
        }
    }

    private func languagePair(for language: DetectedLanguage) -> (source: String, target: String) {
        switch language {
        case .english:
            return ("en", "zh-Hans")
        case .chinese, .mixed:
            return ("zh-Hans", "en")
        case .unknown:
            return ("en", "zh-Hans")
        }
    }
}

@available(macOS 15.0, *)
private struct AppleTranslationRequest: Equatable {
    let id: UUID
    let sourceText: String
    let sourceLanguage: String
    let targetLanguage: String
    let usedSentenceContext: Bool
}

@available(macOS 15.0, *)
@MainActor
private final class AppleTranslationBridge: ObservableObject {
    @Published fileprivate var pendingRequest: AppleTranslationRequest?
    private var continuation: CheckedContinuation<LocalTranslationResult, Error>?

    func submit(_ request: AppleTranslationRequest) async throws -> LocalTranslationResult {
        try Task.checkCancellation()
        continuation?.resume(throwing: CancellationError())
        continuation = nil

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            pendingRequest = request
        }
    }

    func succeed(requestID: UUID, translatedText: String) {
        guard let request = pendingRequest, request.id == requestID else { return }
        let result = LocalTranslationResult(
            sourceText: request.sourceText,
            targetText: translatedText,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            usedSentenceContext: request.usedSentenceContext
        )
        pendingRequest = nil
        continuation?.resume(returning: result)
        continuation = nil
    }

    func fail(requestID: UUID, error: Error) {
        guard pendingRequest?.id == requestID else { return }
        pendingRequest = nil
        if error is CancellationError {
            continuation?.resume(throwing: CancellationError())
        } else if TranslationError.unsupportedLanguagePairing ~= error
                    || TranslationError.unsupportedSourceLanguage ~= error
                    || TranslationError.unsupportedTargetLanguage ~= error {
            continuation?.resume(throwing: LocalTranslationError.unsupportedLanguagePair)
        } else {
            continuation?.resume(throwing: LocalTranslationError.failed(error.localizedDescription))
        }
        continuation = nil
    }

    func cancel(requestID: UUID) {
        guard pendingRequest?.id == requestID else { return }
        pendingRequest = nil
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

@available(macOS 15.0, *)
private struct AppleTranslationHostView: View {
    @ObservedObject var bridge: AppleTranslationBridge
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onReceive(bridge.$pendingRequest.compactMap { $0 }) { request in
                triggerSession(for: request)
            }
            .translationTask(configuration) { session in
                guard let request = await MainActor.run(body: { bridge.pendingRequest }) else {
                    return
                }
                do {
                    try await session.prepareTranslation()
                    let response = try await session.translate(request.sourceText)
                    await MainActor.run {
                        bridge.succeed(requestID: request.id, translatedText: response.targetText)
                    }
                } catch {
                    await MainActor.run {
                        bridge.fail(requestID: request.id, error: error)
                    }
                }
            }
    }

    private func triggerSession(for request: AppleTranslationRequest) {
        let source = Locale.Language(identifier: request.sourceLanguage)
        let target = Locale.Language(identifier: request.targetLanguage)
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }
}
