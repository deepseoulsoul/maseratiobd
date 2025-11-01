import Foundation

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isAuthenticated = false
    @Published var currentUser: AuthResponse?
    @Published var subscription: Subscription?

    private init() {
        checkAuthentication()
    }

    func checkAuthentication() {
        isAuthenticated = KeychainHelper.shared.getAccessToken() != nil
    }

    func signIn() async throws {
        do {
            // Try login first
            let response = try await APIService.shared.login()
            currentUser = response
            subscription = response.subscription
            isAuthenticated = true
        } catch {
            // If login fails, register
            let response = try await APIService.shared.register()
            currentUser = response
            subscription = response.subscription
            isAuthenticated = true
        }
    }

    func signOut() async {
        do {
            try await APIService.shared.logout()
        } catch {
            print("Logout error: \(error)")
        }

        currentUser = nil
        subscription = nil
        isAuthenticated = false
    }

    func refreshSubscription() async throws {
        let subscription: Subscription = try await APIService.shared.getSubscription()
        self.subscription = subscription
    }
}
