import AuthenticationServices
import UIKit

@MainActor
final class CalendarAuthorizer: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    func authorize(_ start: AgendaStart) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let browser = ASWebAuthenticationSession(url: start.url, callbackURLScheme: "jacnomina") { [weak self] url, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error {
                        let cancelled = (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                        continuation.resume(throwing: APIError.message(cancelled ? "Autorización cancelada." : "No se pudo autorizar Agenda. Intenta de nuevo."))
                    } else {
                        do { try Self.validate(url, nonce: start.nonce); continuation.resume() }
                        catch { continuation.resume(throwing: error) }
                    }
                }
            }
            browser.presentationContextProvider = self; browser.prefersEphemeralWebBrowserSession = true; session = browser
            if !browser.start() { session = nil; continuation.resume(throwing: APIError.message("No se pudo abrir Google.")) }
        }
    }
    static func validate(_ url: URL?, nonce: String) throws {
        guard let url, let p = URLComponents(url: url, resolvingAgainstBaseURL: false), p.scheme == "jacnomina", p.host == "calendar", p.path.isEmpty, p.user == nil, p.password == nil, p.fragment == nil,
              nonce.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              let items = p.queryItems, items.filter({ $0.name == "nonce" }).count == 1, items.first(where: { $0.name == "nonce" })?.value == nonce, items.filter({ $0.name == "result" }).count == 1 else {
            throw APIError.message("La respuesta de Google no corresponde a esta autorización.")
        }
        guard items.first(where: { $0.name == "result" })?.value == "connected" else { throw APIError.message("Agenda no quedó conectada. Elige jacmusicestudios@gmail.com y concede consultar calendarios y editar eventos.") }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
