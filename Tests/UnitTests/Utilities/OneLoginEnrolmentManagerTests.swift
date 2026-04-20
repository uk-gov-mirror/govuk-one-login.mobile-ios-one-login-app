import Coordination
import LocalAuthenticationWrapper
import Networking
@testable import OneLogin
import XCTest

class MockChildCoordinatorExpectation: ChildCoordinator {
    
    weak var parentCoordinator: (any Coordination.ParentCoordinator)?
    
    typealias StartAsFunction = () -> Void
    typealias FinishAsFunction = () -> Void
    
    var startAsFunction: StartAsFunction
    var finishAsFunction: FinishAsFunction

    init(startAsFunction: @escaping StartAsFunction = {}, finishAsFunction: @escaping FinishAsFunction = {}) {
        self.startAsFunction = startAsFunction
        self.finishAsFunction = finishAsFunction
    }
    
    func start() {
        self.startAsFunction()
    }
    
    func finish() {
        self.finishAsFunction()
    }
}

extension OneLoginEnrolmentManager {
    static func make(mockLocalAuthContext: LocalAuthManaging = MockLocalAuthManager(),
                     mockSessionManager: SessionManager = MockSessionManager(),
                     mockAnalyticsService: OneLoginAnalyticsService = MockAnalyticsService(),
                     coordinator: ChildCoordinator? = nil) -> OneLoginEnrolmentManager {
        let coordinator = coordinator ?? EnrolmentCoordinator(
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
        // GIVEN the user has given FaceID permission
        mockLocalAuthContext.userDidConsentToFaceID = true
        // GIVEN saveSession returns an uncaught error
        mockSessionManager.errorFromSaveSession = MockError.generic
        // WHEN saveSession is called
        sut.saveSession()
        waitForTruth(self.mockSessionManager.didCallSaveSession, timeout: 5)
        // THEN an error is recorded in Crashlytics
        XCTAssertEqual(mockAnalyticsService.crashesLogged, [MockError.generic as NSError])
    }
    
    @MainActor
    func test_saveSession_promptForPermission_false() {
        // GIVEN the user has already given FaceID permission
        mockLocalAuthContext.userDidConsentToFaceID = false
        // WHEN saveSession is called
        sut.saveSession()
        waitForTruth(self.mockLocalAuthContext.didCallEnrolFaceIDIfAvailable, timeout: 5)
        // THEN no error is recorded in Crashlytics
        XCTAssertEqual(mockAnalyticsService.crashesLogged, [])
    }
    
    @MainActor
    func test_saveSession_promptForPermission_cancelled() {
        // GIVEN promptForPermission throws a cancelled error
        mockLocalAuthContext.errorFromEnrolLocalAuth = LocalAuthenticationWrapperError.cancelled
        // WHEN saveSession is called
        sut.saveSession()
        waitForTruth(self.mockLocalAuthContext.didCallEnrolFaceIDIfAvailable, timeout: 5)
        // THEN no error is recorded in Crashlytics
        XCTAssertEqual(mockAnalyticsService.crashesLogged, [])
    }
    
    @MainActor
    func test_saveSession_promptForPermission_fails() {
        // GIVEN promptForPermission throws an uncaught error
        mockLocalAuthContext.errorFromEnrolLocalAuth = MockError.generic
        // WHEN saveSession is called
        sut.saveSession()
        waitForTruth(self.mockLocalAuthContext.didCallEnrolFaceIDIfAvailable, timeout: 5)
        // THEN an error is recorded in Crashlytics
        XCTAssertEqual(mockAnalyticsService.crashesLogged, [MockError.generic as NSError])
    }

    @MainActor
    func test_saveSession_isWalletEnrolmentTrue_callsFinishOnCoordinator() {
        let expectation = expectation(description: #function)
        expectation.isInverted = true
        let mockChildCoordinatorExpectation = MockChildCoordinatorExpectation(finishAsFunction: {
                expectation.fulfill()
            })
        
        let sut: OneLoginEnrolmentManager = .make(coordinator: mockChildCoordinatorExpectation)
        // WHEN saveSession is called
        sut.saveSession(isWalletEnrolment: true)
        wait(for: [expectation], timeout: 1)
    }
    
    @MainActor
    func test_saveSession_isWalletEnrolmentFalse_finishOnCoordinatorNotCalled() {
        let expectation = expectation(description: #function)
        let mockChildCoordinatorExpectation = MockChildCoordinatorExpectation(finishAsFunction: {
                expectation.fulfill()
            })
        
        let sut: OneLoginEnrolmentManager = .make(coordinator: mockChildCoordinatorExpectation)
        // WHEN saveSession is called
        sut.saveSession(isWalletEnrolment: false)
        wait(for: [expectation], timeout: 5)
    }
    
    @MainActor
    func test_saveSession_default_finishOnCoordinatorNotCalled() {
        let expectation = expectation(description: #function)
        let mockChildCoordinatorExpectation = MockChildCoordinatorExpectation(finishAsFunction: {
                expectation.fulfill()
            })
        
        let sut: OneLoginEnrolmentManager = .make(coordinator: mockChildCoordinatorExpectation)
        // WHEN saveSession is called
        sut.saveSession()
        wait(for: [expectation], timeout: 5)
    }
    
    @MainActor
    func test_saveSession_isWalletEnrolmentTrue__walletCoordinator_notRemoved_asChild() {
        let expectation = expectation(description: #function)
        let tabManagerCoordinator = TabManagerCoordinator(root: UITabBarController(),
                                        analyticsService: mockAnalyticsService,
                                        networkingService: NetworkClient(),
                                        sessionManager: mockSessionManager)
        
        let walletCoordinator =  WalletCoordinator(analyticsService: mockAnalyticsService,
                                               networkingService: NetworkClient(),
                                               sessionManager: mockSessionManager)
        
        tabManagerCoordinator.childCoordinators.append(walletCoordinator)
        walletCoordinator.parentCoordinator = tabManagerCoordinator


        let sut: OneLoginEnrolmentManager = .make(coordinator: walletCoordinator)
        // WHEN saveSession is called
        sut.saveSession(isWalletEnrolment: true) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssert(tabManagerCoordinator.childCoordinators.count == 1)
    }
}
