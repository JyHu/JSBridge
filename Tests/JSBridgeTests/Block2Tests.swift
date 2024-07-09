//
//  Block2Tests.swift
//  
//
//  Created by hujinyou on 2024/7/8.
//

import XCTest
@testable import JSBridge

final class Block2Tests: XCTestCase {
    var bridge = TestableBridge()
    
    func testBlock() {
        let expectation = expectation(description: "block")
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:MM:ss.SSSS"
        bridge.append(
            """
            function testBlock(message) {
                JSConnecter.sleep(0.5, function() {
                    JSConnecter.showLog(0, "wake up");
                });
                JSConnecter.showLog(0, message);
            }
            """
        )
        
        print(formatter.string(from: Date()))
        bridge.showLogCallback = { level, message in
            if message as? String == "wake up" {
                expectation.fulfill()
                print(formatter.string(from: Date()))
            }
        }
        
        bridge.logLevel = .debug
        bridge.call("testBlock", arguments: "haha")
        
        wait(for: [expectation], timeout: 2)
    }
}
