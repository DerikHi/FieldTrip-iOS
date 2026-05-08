import XCTest
@testable import FieldTrip

// MARK: - Mock AuthService

final class MockAuthService: AuthServiceProtocol {
    var signInResult: Result<AuthUser, Error> = .failure(AuthError.invalidCredentials)
    var registerResult: Result<AuthUser, Error> = .failure(AuthError.unknown("Not configured"))
    var shouldThrowOnPasswordReset = false
    var passwordResetEmailSent = false
    var emailVerificationSent = false
    var reloadResult: Bool = false

    var currentFirebaseUser: (any Any)? { nil } // simplified

    var firebaseUser: (any Any)? { nil }

    func signIn(email: String, password: String) async throws -> AuthUser {
        switch signInResult {
        case .success(let user): return user
        case .failure(let error): throw error
        }
    }

    func register(email: String, password: String, fullName: String) async throws -> AuthUser {
        switch registerResult {
        case .success(let user): return user
        case .failure(let error): throw error
        }
    }

    func signOut() throws {}

    func sendPasswordReset(email: String) async throws {
        if shouldThrowOnPasswordReset { throw AuthError.userNotFound }
        passwordResetEmailSent = true
    }

    func sendEmailVerification() async throws {
        emailVerificationSent = true
    }

    func reloadUser() async throws -> Bool {
        return reloadResult
    }
}

extension MockAuthService {
    var currentFirebaseUserProtocol: (any Any)? { nil }
}

// We need a concrete conformance — let's extend the protocol
extension MockAuthService: @retroactive AuthServiceProtocol {
    // Already implemented above
}

final class LoginViewModelTests: XCTestCase {
    var mockService: MockAuthService!
    var vm: LoginViewModel!

    override func setUp() {
        super.setUp()
        mockService = MockAuthService()
    }

    @MainActor
    func testFormInvalidWithEmptyFields() {
        let vm = LoginViewModel(authService: mockService)
        XCTAssertFalse(vm.isFormValid)
    }

    @MainActor
    func testFormInvalidWithBadEmail() {
        let vm = LoginViewModel(authService: mockService)
        vm.email = "notanemail"
        vm.password = "anypassword"
        XCTAssertFalse(vm.isFormValid)
    }

    @MainActor
    func testFormValidWithGoodCredentials() {
        let vm = LoginViewModel(authService: mockService)
        vm.email = "user@university.edu"
        vm.password = "anypassword"
        XCTAssertTrue(vm.isFormValid)
    }

    @MainActor
    func testSignInSuccessNavigatesToHome() async {
        mockService.signInResult = .success(AuthUser(
            id: "123",
            email: "user@test.edu",
            fullName: "Test User",
            role: .user,
            organization: nil,
            createdAt: Date()
        ))
        let vm = LoginViewModel(authService: mockService)
        vm.email = "user@test.edu"
        vm.password = "Password1!"

        await vm.signIn()

        XCTAssertTrue(vm.navigateToHome)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testSignInFailureSetsErrorMessage() async {
        mockService.signInResult = .failure(AuthError.invalidCredentials)
        let vm = LoginViewModel(authService: mockService)
        vm.email = "user@test.edu"
        vm.password = "WrongPass1!"

        await vm.signIn()

        XCTAssertFalse(vm.navigateToHome)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(vm.errorMessage, AuthError.invalidCredentials.errorDescription)
    }

    @MainActor
    func testTooManyRequestsErrorMessage() async {
        mockService.signInResult = .failure(AuthError.tooManyRequests)
        let vm = LoginViewModel(authService: mockService)
        vm.email = "user@test.edu"
        vm.password = "Password1!"

        await vm.signIn()

        XCTAssertEqual(vm.errorMessage, "Too many attempts. Please wait a few minutes and try again.")
    }
}
