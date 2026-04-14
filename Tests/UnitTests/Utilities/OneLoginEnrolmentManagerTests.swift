import Coordination
import LocalAuthenticationWrapper
@testable import OneLogin
import XCTest

extension OneLoginEnrolmentManager {
    static func make(mockLocalAuthContext: LocalAuthManaging = MockLocalAuthManager(),
                     mockSessionManager: SessionManager = MockSessionManager(),
                     mockAnalyticsService: OneLoginAnalyticsService = MockAnalyticsService()) -> OneLoginEnrolmentManager {
        let coordinator = EnrolmentCoordinator(
            root: UINavigationController(),
            analyticsService: mockAnalyticsService,
            sessionManager: mockSessionManager
        )
        return OneLoginEnrolmentManager(
            localAuthContext: mockLocalAuthContext,
            sessionManager: mockSessionManager,
            analyticsService: mockAnalyticsService,
            coordinator: coordinator
        )
    }
}
final class OneLoginEnrolmentManagerTests: XCTestCase {
    private var mockLocalAuthContext: MockLocalAuthManager!
    private var mockSessionManager: MockSessionManager!
    private var mockAnalyticsService: MockAnalyticsService!
    private var coordinator: ChildCoordinator!
    private var sut: OneLoginEnrolmentManager!
    
    @MainActor
    override func setUp() {
        mockLocalAuthContext = MockLocalAuthManager()
        mockSessionManager = MockSessionManager()
        mockAnalyticsService = MockAnalyticsService()
        coordinator = EnrolmentCoordinator(
            root: UINavigationController(),
            analyticsService: mockAnalyticsService,
            sessionManager: mockSessionManager
        )
        sut = OneLoginEnrolmentManager(
            localAuthContext: mockLocalAuthContext,
            sessionManager: mockSessionManager,
            analyticsService: mockAnalyticsService,
            coordinator: coordinator
        )
    }
    
    override func tearDown() {
        mockLocalAuthContext = nil
        mockSessionManager = nil
        mockAnalyticsService = nil
        coordinator = nil
        sut = nil
    }
    
    enum MockError: Error {
        case generic
    }
}

extension OneLoginEnrolmentManagerTests {
    @MainActor
    func test_saveSession_succeeds() async {
        let exp = XCTNSNotificationExpectation(
            name: .enrolmentComplete,
            object: nil,
            notificationCenter: NotificationCenter.default
        )
        // GIVEN the user has given FaceID permission
        mockLocalAuthContext.userDidConsentToFaceID = true
        // WHEN saveSession is called
        sut.saveSession()
        // THEN enrolment complete notification is sent
        await fulfillment(of: [exp], timeout: 5)
    }
    
    @MainActor
    func test_saveSession_fails() {
        let expectation = expectation(description: #function)
        // GIVEN the user has given FaceID permission
        let mockLocalAuthContext = MockLocalAuthManager()
        mockLocalAuthContext.userDidConsentToFaceID = true
        // GIVEN saveSession returns an uncaught error
        let mockSessionManager = MockSessionManager()
        let mockSessionManagerExpectation = MockSessionManagerExpectation(sessionManager: mockSessionManager, didSaveAuthSessionAsFunction: {
            expectation.fulfill()
        })
        
        mockSessionManager.errorFromSaveSession = MockError.generic
        let mockAnalyticsService = MockAnalyticsService()
        let sut: OneLoginEnrolmentManager = .make(mockLocalAuthContext: mockLocalAuthContext,
                                                  mockSessionManager: mockSessionManagerExpectation,
                                                  mockAnalyticsService: mockAnalyticsService)
        
        // WHEN saveSession is called
        sut.saveSession()
        
        self.wait(for: [expectation], timeout: 5)
        XCTAssertTrue(mockSessionManager.didCallSaveSession)
        // THEN an error is recorded in Crashlytics
        XCTAssertEqual(mockAnalyticsService.crashesLogged, [MockError.generic as NSError])
    }
    
    @MainActor
    func test_saveSession_promptForPermission_false() {
        let expectation = expectation(description: #function)
        // GIVEN the user has already given FaceID permission
        let mockLocalAuthManager = MockLocalAuthManager()
        let mockLocalAuthManagerExpectation = MockLocalAuthManagerExpectation(mockLocalAuthManager: mockLocalAuthManager,
                                                                   expectation: expectation)
        mockLocalAuthManager.userDidConsentToFaceID = false
        let mockAnalyticsService = MockAnalyticsService()
        let sut: OneLoginEnrolmentManager = .make(mockLocalAuthContext: mockLocalAuthManagerExpectation,
                                                  mockAnalyticsService: mockAnalyticsService)
        // WHEN saveSession is called
        sut.saveSession()
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(mockLocalAuthManager.didCallEnrolFaceIDIfAvailable)
        // THEN no error is recorded in Crashlytics
        XCTAssertEqual(mockAnalyticsService.crashesLogged, [])
    }
    
    @MainActor
    func test_saveSession_promptForPermission_cancelled() {
        let expectation = expectation(description: #function)
        // GIVEN promptForPermission throws a cancelled error
        let mockLocalAuthManager = MockLocalAuthManager()
        let mockLocalAuthManagerExpectation = MockLocalAuthManagerExpectation(mockLocalAuthManager: mockLocalAuthManager,
                                                                   expectation: expectation)
        mockLocalAuthManager.errorFromEnrolLocalAuth = LocalAuthenticationWrapperError.cancelled
        let mockAnalyticsService = MockAnalyticsService()
        let sut: OneLoginEnrolmentManager = .make(mockLocalAuthContext: mockLocalAuthManagerExpectation,
                                                  mockSessionManager: mockSessionManager,
                                                  mockAnalyticsService: mockAnalyticsService)
        // WHEN saveSession is called
        sut.saveSession()
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(mockLocalAuthManager.didCallEnrolFaceIDIfAvailable)
        // THEN no error is recorded in Crashlytics
        XCTAssertEqual(mockAnalyticsService.crashesLogged, [])
    }
    
    @MainActor
    func test_saveSession_promptForPermission_fails() {
        let expectation = expectation(description: #function)
        // GIVEN promptForPermission throws an uncaught error
        let mockLocalAuthContext = MockLocalAuthManager()
        mockLocalAuthContext.errorFromEnrolLocalAuth = MockError.generic
        let mockAnalyticsService = MockAnalyticsServiceExpectation(expectation: expectation)
        let sut: OneLoginEnrolmentManager = .make(mockLocalAuthContext: mockLocalAuthContext,
                                                  mockSessionManager: mockSessionManager,
                                                  mockAnalyticsService: mockAnalyticsService)
        // WHEN saveSession is called
        sut.saveSession()
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(mockLocalAuthContext.didCallEnrolFaceIDIfAvailable)
        // THEN an error is recorded in Crashlytics
        XCTAssertEqual(mockAnalyticsService.crashesLogged, [MockError.generic as NSError])
    }
}
