# JSBridge

JSBridge 是一个旨在简化 JavaScript 与客户端（OC、Swift）之间通信的通用框架。该框架提供了强大的双向通信机制，支持异步调用、回调处理和日志管理等功能。

## 功能亮点

### 由 JavaScript 发起调用

通过 `JSBridge.call` 方法，JavaScript 可以方便地向客户端发起调用，并接收异步回调。

```javascript
JSBridge.call('methodName', { param1: 'value1' }, 1, (result) => {
  console.log('回调结果:', result);
});
```

### 客户端接收 JavaScript 通知

客户端可以通过 JSBridge.onReceive 方法，接收 JavaScript 发送的通知，实现双向通信。

```javascript
// 外部（JSContext）接收到消息时调用的回调方法
function __onSyncReply__(message) {
  JSBridge.onReceive(message);
}
```

### 在 Swift（或 Objective-C）中处理 JavaScript 异步调用

在客户端中，可以方便地处理 JavaScript 发起的异步调用，实现与 JavaScript 的协同操作。

```javascript
// 处理 JavaScript 异步调用，例如异步处理后将回调结果发送回 JavaScript
func exampleFunc(taskID: Int, watch: Int, params: Any?) {
  // 处理异步操作
  jsBridge.callback(taskID: taskID, message: "result");
}
```

## 使用说明

### 初始化调用

在 JavaScript 中

```javascript
// 初始化框架
const JSBridge = (function () {
  // ...（省略初始化代码）
})();
```

在 Swift（或 Objective-C）中

```swift
// 初始化 JSBridge
let jsBridge = JSExportObject()
jsBridge.load(javascript)
```

### 发起调用

在 JavaScript 中

```javascript
JSBridge.call('methodName', { param1: 'value1' }, 1, (result) => {
  console.log('回调结果:', result);
});
```

在 Swift（或 Objective-C）中

```swift
let taskID = jsBridge.asyncCall("methodName", watch: 1, arguments: ["param1": "value1"]) { result in
    print("回调结果:", result)
}
```

### 接收通知

在 JavaScript 中

```javascript
// 客户端主动通知 JavaScript
function __onSyncReply__(message) {
  JSBridge.onReceive(message);
}
```

在 Swift（或 Objective-C）中

```swift
// 接收 JavaScript 通知
func onReceive(message: [String: Any]) {
    jsBridge.onReceive(message)
}
```

### 取消订阅

在 JavaScript 中

```javascript
JSBridge.unwatch({ taskID: 123 });
```

在 Swift（或 Objective-C）中

```swift
jsBridge.unwatch(taskID: 123)
```

### 更新日志等级

在 JavaScript 中

```javascript
__onUpdateLogLevel__(2);
```

在 Swift（或 Objective-C）中

```swift
jsBridge.logLevel = .warning
```

```swift
// 更新日志等级
func updateLogLevel(level: Int) {
    jsBridge.logLevel = JSExportObject.LogLevel(rawValue: level) ?? .warning
}
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
