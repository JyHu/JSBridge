//
//  BridgeCallTests.swift
//  
//
//  Created by Jo on 2024/1/6.
//

import XCTest
@testable import JSBridge

final class BridgeCallTests: XCTestCase {
    var bridge = TestableBridge()
    
    /// 测试回复一个未知的taskID，会因为查不到缓存的callback而报错
    func testUnknownTaskID() throws {
        bridge.append(
        """
        function testAction(message) {
            JSBridge.call("nativeFunc", message, 1, function(param) {
                JSBridge.showLog(0, param);
            });
        }
        """
        )
        
        var results: [String] = []
        bridge.showLogHandler = { level, log in
            if let log = log as? String {
                results.append(log)
            }
        }
        
        bridge.callback(taskID: -2, message: "response message")
        
        let expectation = expectation(description: "test4")        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(results, [])
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1)
    }
    
    /// 测试JSBridge.call方法正常调用
    func testBridgeCall() throws {
        let expectation1 = expectation(description: "test-1")
        let expectation2 = expectation(description: "test-2")
        
        bridge.append(
        """
        function testAction(message) {
            JSBridge.call("nativeFunc", message, 1, function(param) {
                JSBridge.showLog(0, param);
            });
        }
        """
        )
        
        bridge.distributeHandler = { message in
            XCTAssertEqual(message.params as? String, "request message")
            XCTAssertEqual(message.name, "nativeFunc")
            
            self.bridge.callback(taskID: message.taskID, message: "response message")
            
            expectation1.fulfill()
        }
        
        bridge.showLogHandler = { level, log in
            XCTAssertEqual(log as? String, "response message")
            expectation2.fulfill()
        }
        
        bridge.logLevel = .debug
        bridge.call("testAction", argument: "request message")
        
        wait(for: [expectation1, expectation2], timeout: 1)
    }
    
    /// 测试 JSBridge.call 只回复一次（watch = 1）的处理方式，
    /// 只会接收nativie的一次回复，再次回复的时候JS中会查不到对应的callback缓存
    func testWatch1() throws {
        let expectation = expectation(description: "test3")
        
        bridge.append(
        """
        function testAction(message) {
            JSBridge.call("nativeFunc", message, 1, function(param) {
                JSConnecter.showLog(0, param);
            });
        }
        """
        )
        
        bridge.distributeHandler = { message in
            self.bridge.callback(taskID: message.taskID, message: "response message")
            self.bridge.callback(taskID: message.taskID, message: "response message 2")
        }
        
        var results: [String] = []
        
        bridge.showLogHandler = { level, log in
            if let log = log as? String {
                results.append(log)
            }
        }
        
        bridge.call("testAction", argument: "request message")
        
        /// 因为watch=1，所以在收到一次消息后就会移除callback，所以收到的数据就只会是第一个
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(results, ["response message"])
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1)
    }
    
    /// 测试JSBridge.call在watch=0的时候，不会缓存callback，在native回复js的时候
    /// 会因为找不到缓存的callback而报错
    func testWatch0() throws {
        let expectation = expectation(description: "test5")
        
        
        // watch = 0，在bridge中不会被缓存
        bridge.append(
        """
        function testAction(message) {
            JSBridge.call("nativeFunc", message, 0, function(param) { });
        }
        """
        )
        
        bridge.distributeHandler = { message in
            // 调用的时候，因为没有缓存callback，那么会直接报错
            self.bridge.callback(taskID: message.taskID, message: "response message")
        }
        
        var results: [String] = []
        
        bridge.showLogHandler = { level, log in
            if let log = log as? String {
                results.append(log)
            }
        }
        
        bridge.call("testAction", argument: "request message")
        
        /// watch=0，所以在native中callback在js中是接受不到回调的
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(results, [])
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1)
    }
    
    /// 测试JSBridge.call在watch = 2的时候可以连续接收native的多次回复
    func testWatch2() throws {
        let expectation = expectation(description: "test6")
        
        bridge.append(
        """
        function testAction(message) {
            JSBridge.call("nativeFunc", message, 2, function(param) {
                JSConnecter.showLog(0, param);
            });
        }
        """
        )
        
        bridge.distributeHandler = { message in
            self.bridge.callback(taskID: message.taskID, message: "response message")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.bridge.callback(taskID: message.taskID, message: "response message")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.bridge.callback(taskID: message.taskID, message: "response message")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.bridge.callback(taskID: message.taskID, message: "response message")
            }
        }
        
        var results: [String] = []
        bridge.showLogHandler = { level, log in
            if let log = log as? String {
                results.append(log)
            }
        }
        
        bridge.call("testAction", argument: "request message")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            XCTAssertEqual(results, Array(repeating: "response message", count: 4))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5)
    }
    
    /// 测试JS中调用call的时候taskID是累加的
    func testRepeatCall() throws {
        let expectation = expectation(description: "test6")
        
        bridge.append(
        """
        function testAction(message) {
            JSBridge.call("nativeFunc", message, 0, function(param) { });
            JSBridge.call("nativeFunc", message, 1, function(param) { });
            JSBridge.call("nativeFunc", message, 2, function(param) { });
            JSBridge.call("nativeFunc", message, 0, function(param) { });
            JSBridge.call("nativeFunc", message, 1, function(param) { });
            JSBridge.call("nativeFunc", message, 2, function(param) { });
        }
        """
        )
        
        var taskIDs: [Int] = []
        
        bridge.distributeHandler = { message in
            print(message)
            taskIDs.append(message.taskID)
        }
        
        bridge.call("testAction", argument: "request message")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(taskIDs, [0, 1, 2, 3, 4, 5])
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3)
    }
    
    /// 测试JSBridge.call在watch=2时，在unwatch后能够正常取消订阅，
    /// 之后native的所有回复都会在JS中报错
    func testUnwatch() throws {
        let expectation = expectation(description: "test7")
        
        bridge.append(
        """
        function testAction(message) {
            var count = 0;
            var taskID = JSBridge.call("nativeFunc", message, 2, function(param) {
                JSBridge.showLog(0, param);
        
                count += 1;
                if (count === 2) {
                    JSBridge.unwatch(taskID);
                }
            });
        }
        """
        )
        
        bridge.distributeHandler = { message in
            if message.name == "nativeFunc" {
                self.bridge.callback(taskID: message.taskID, message: "response message")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.bridge.callback(taskID: message.taskID, message: "response message")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.bridge.callback(taskID: message.taskID, message: "response message")
                }
            }
        }
        
        var results: [String] = []
        
        bridge.showLogHandler = { level, log in
            if let log = log as? String {
                results.append(log)
            }
        }
        
        bridge.logLevel = .debug
        bridge.call("testAction", argument: "request message")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            XCTAssertEqual(results, Array(repeating: "response message", count: 2))
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5)
    }
}
