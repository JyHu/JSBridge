//
//  NativeCallTests.swift
//  
//
//  Created by Jo on 2024/1/6.
//

import XCTest
@testable import JSBridge

final class NativeCallTests: XCTestCase {

    var bridge = TestableBridge()
    
    func testReply() throws {
        bridge.append(
        """
        function testAction(taskID, watch, params) {
            JSBridge.reply(taskID, params);
        }
        
        function testAction2(taskID, watch, params) {
            JSBridge.reply(taskID, params);
        }
        """
        )
        
        let exp00 = expectation(description: "test1")
        bridge.asyncCall("testAction", watch: .oncetime, arguments: "hello") { message in
            XCTAssertEqual(message as? String, "hello")
            exp00.fulfill()
        }
        wait(for: [exp00], timeout: 1)
        
        let exp01 = expectation(description: "test2")
        bridge.asyncCall("testAction2", watch: .oncetime, arguments: "world") { message in
            XCTAssertEqual(message as? String, "world")
            exp01.fulfill()
        }
        wait(for: [exp01], timeout: 1)
        
        let exp02 = expectation(description: "test3")
        let params2: [String: String] = ["username" : "jos", "age": "18"]
        bridge.asyncCall("testAction", watch: .oncetime, arguments: params2) { message in
            XCTAssertEqual(message as? [String: String], params2)
            exp02.fulfill()
        }
        wait(for: [exp02], timeout: 1)
    }
    
    func testTaskID() throws {
        bridge.append(
        """
        function testAction(taskID, watch, params) {
            JSConnecter.asyncReply({"taskID": taskID, "result": params});
        }
        """
        )
        
        XCTAssertEqual(bridge.asyncCall("testAction"), 0)
        XCTAssertEqual(bridge.asyncCall("testAction"), 1)
        XCTAssertEqual(bridge.asyncCall("testAction"), 2)
        XCTAssertEqual(bridge.asyncCall("testAction"), 3)
        XCTAssertNotEqual(bridge.asyncCall("testAction"), 6)
    }
    
    func testWatch() throws {
        bridge.append(
        """
        function testAction(taskID, watch, params) {
            JSBridge.reply(taskID, params);
        }
        
        function testTrigger(taskID) {
            JSBridge.reply(taskID, "Hello");
        }
        """
        )
        
        func runTest(_ watch: JSExportObject.Watch, expectCount: Int, expectCount2: Int) {
            let exp = expectation(description: "test")
            var results: [String] = []
            
            let taskID = bridge.asyncCall("testAction", watch: watch, arguments: "hello") { message in
                if let message = message as? String {
                    results.append(message)
                }
            }
            
            bridge.call("testTrigger", arguments: taskID)
            bridge.call("testTrigger", arguments: taskID)
            bridge.call("testTrigger", arguments: taskID)
            bridge.call("testTrigger", arguments: taskID)
            bridge.call("testTrigger", arguments: taskID)
            bridge.call("testTrigger", arguments: taskID)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                XCTAssertEqual(results, Array(repeating: "hello", count: expectCount) + Array(repeating: "Hello", count: expectCount2))
                exp.fulfill()
            }
            
            wait(for: [exp], timeout: 1)
        }
        
        runTest(.notify, expectCount: 0, expectCount2: 0)
        runTest(.oncetime, expectCount: 1, expectCount2: 0)
        runTest(.monitor, expectCount: 1, expectCount2: 6)
    }
}
