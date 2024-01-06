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
            JSConnecter.showLog(0, JSBridge.logLevel);
        }
        """
        )
        
        bridge.showLogCallback = { level, message in
            XCTAssertEqual(message as? Int, 1)
            expectation.fulfill()
        }
        
        bridge.logLevel = .info
        bridge.call("testAction", arguments: "23")
        
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
        
        bridge.showLogCallback = { level, message in
            XCTAssertEqual(message as? String, "haha")
            expectation.fulfill()
        }
        
        bridge.call("testAction", arguments: "haha")
        wait(for: [expectation], timeout: 1)
    }
}
