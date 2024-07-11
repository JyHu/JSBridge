//
//  BasicTests.swift
//  
//
//  Created by Jo on 2024/1/6.
//

import XCTest
@testable import JSBridge

final class BasicTests: XCTestCase {

    var bridge = TestableBridge()
    
    func testLogLevel() {
        let expectation = expectation(description: "testLogLevel")
        bridge.append(
        """
        function testAction(message) {
            JSBridge.showLog(0, message);
            JSBridge.showLog(1, message);
            JSBridge.showLog(2, message);
        }
        """
        )
        
        var logCount: Int = 0
        bridge.showLogHandler = { level, message in
            logCount += 1
        }
        
        bridge.logLevel = .info
        bridge.call("testAction", argument: "23")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if logCount == 2 {
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    /// 测试 showLog方法可以调用
    func testShowLog() throws {
        let expectation = expectation(description: "testShowLog")
        
        bridge.append(
            """
            function testAction(message) {
                JSConnecter.showLog(0, message);
            }
            """
        )
        
        bridge.showLogHandler = { level, message in
            XCTAssertEqual(message as? String, "haha")
            expectation.fulfill()
        }
        
        bridge.call("testAction", argument: "haha")
        wait(for: [expectation], timeout: 1)
    }
}
