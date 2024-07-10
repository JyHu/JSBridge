// JSBridge 是一个模块，旨在简化 JavaScript 与客户端（OC、Swift）之间的通信。
// 它允许 JavaScript 调用客户端并在返回数据时接收数据。

// JSConnecter 是在 JSContext 中注册的对象，它使 JavaScript 能够调用 OC 或 Swift 方法。

// 定义一个模块，封装相关功能。
const JSBridge = (function () {
    // 日志等级
    //   debug = 0      /// 调试日志
    //   info = 1       /// 普通日志
    //   warning = 2    /// 警告信息
    //   error = 3      /// 错误信息
    var logLevel = 2;
    
    // 用于跟踪最后一个任务 ID 的私有变量。
    let lastTaskID = 0;
        
    // 与事件关联的所有回调对象的缓存。
    const callbackMap = {};
    
    // 用于存储由 native 端发送过来的所有消息
    // key 为 taskID，value 为 native 传来的 message
    const messages = {};
    
    // 模块暴露的公共方法。
    return {
        // 由 JS 调用与客户端交互的方法。
        // name: 协议名称
        // params: 参数
        // watch: 是否监听事件
        //   0: 仅用于通知，不会缓存回调信息
        //   1: 仅需要接收一次消息，接收后立即移除对应缓存
        //   2: 需要接收多次消息，需要主动取消订阅
        // callback: 回调方法
        call: function (name, params, watch, callback) {
            var currentTaskID = lastTaskID
            lastTaskID ++;

            // 如果 watch 不为 0，则将回调信息存储在 callbackMap 对象中
            if (watch !== 0) {
                callbackMap[currentTaskID] = { name, watch, callback };
            }
            
            // 构建发送给客户端的消息对象
            const args = { name, watch, taskID: currentTaskID };

            // 如果 params 不为 null，则将其添加到消息对象中
            if (params !== null) {
                args['params'] = params;
            }

            // 将消息发送到客户端
            JSConnecter.call(args);

            // 自增消息 ID
            return currentTaskID
        },
        
        // 由客户端调用通知 JS 的方法。
        // message: 消息
        //   - taskID: 任务 ID，在缓存中查找对应的回调缓存信息
        //   - result: 客户端处理的结果信息
        onReceive: function (message) {
            // 解构 message 对象，获取 taskID 和 result
            const { taskID, result } = message;

            // 检查 taskID 是否有效
            if (taskID !== undefined && typeof taskID === "number" && taskID >= 0) {
                // 从 callbackMap 中获取对应的回调信息
                const callback = callbackMap[taskID];
                                
                // 如果回调信息存在
                if (callback !== undefined) {
                    // 如果是一次性监听的回调信息，移除对应的缓存
                    if (callback.watch === 1) {
                        delete callbackMap[taskID];
                    }

                    // 调用回调方法，并将结果传递给它
                    callback.callback(result);
                }
            }
        },

        // 由 JS 业务方主动取消订阅的方法。
        // message: 消息
        //   - taskID: 任务 ID
        unwatch: function (taskID) {
            // 检查 taskID 是否有效
            if (taskID !== undefined) {
                // 删除 callbackMap 中对应的订阅信息
                delete callbackMap[taskID];
                
                // 通知客户端取消订阅
                JSConnecter.unwatchJSRequestWith(taskID);
            }
        },
        
        // JS 内部根据消息等级输出日志信息
        // lv: 消息等级
        // log: 输出的日志内容
        showLog: function (lv, log) {
            // 如果消息等级大于等于当前设置的日志等级，输出日志
            if (lv >= logLevel) {
                JSConnecter.showLog(lv, log);
            }
        },
        
        // js 中回传 asyncCall 的数据的时候，由 bridge 方回传出去
        reply: function (taskID, resultMessage) {
            // 从 messages 中找到缓存的消息
            const message = messages[taskID];
            
            // 如果消息存在且为一次性监听，移除缓存
            if (message !== undefined && message.watch == 1) {
                delete messages[taskID];
            }
            
            // 调用客户端的 asyncReply 方法，将结果传递给客户端
            JSConnecter.asyncReply({ taskID, result: resultMessage });
        },
        
        asyncAfter: function (seconds, callback) {
            JSConnecter.asyncAfter(seconds, callback);
        },
        
        // 设置日志等级
        setLogLevel: function (level) {
            logLevel = level;
        },
        
        cacheMessage: function (taskID, message) {
            messages[taskID] = message;
        }
    };
})();

// 更新日志输出等级
// level: 日志等级
function __onUpdateLogLevel__(level) {
    // 更新 JSBridge 的 logLevel 属性
    JSBridge.setLogLevel(level);
}

// 外部（JSContext）接收到消息时调用的回调方法。
// 消息格式必须为：
//   {
//       "taskID": xxx,
//       "result": xxx
//   }
function __onReply__(message) {
    // 调用 JSBridge 的 onReceive 方法处理接收到的消息
    JSBridge.onReceive(message);
}

// 外部（JSContext）发起请求，由 JS 中异步处理，在处理完成后异步回调给外部
// 消息格式必须是：
//  {
//      "taskID": xxx,
//      "func": xxxx,
//      "watch": 0 | 1 | 2
//      "params": xxx
//  }
//
// 然后接收事件的方法必须有除了 func 以外的三个参数，如：
//   function exampleFunc(taskID, watch, params) {
//      // async operation
//      JSConnecter.asyncReply({"taskID": taskID, "result": "result"});
//   }
// 在一定异步处理后，通过 asyncReply 将结果回调到外部
function __onAsyncCall__(message) {
    // 解构 message 对象，获取 taskID, func, watch 和 params
    const { taskID, func, watch, params } = message;
    
    // 如果 func 或 taskID 未定义，直接返回
    if (func === undefined || taskID === undefined) {
        return;
    }

    // 根据 watch 类型决定是否缓存数据
    if (watch != 0) {
        JSBridge.cacheMessage(taskID, message);
    }

    // 使用对象的属性名动态调用函数
    if (typeof this[func] === 'function') {
        // 调用对应的函数，并传递参数
        this[func](taskID, watch, params);
    } else {
        // 如果函数不存在，输出日志
        JSBridge.showLog(0, "no func");
    }
}

// swift 侧取消自己的数据订阅的同时，告知一下 JS，标明 JS 侧一些轮询的处理可以停掉了
// message: 消息对象
//   - taskID: 任务 ID
function __removeNativeTask__(message) {
    // 解构 message 对象，获取 taskID
    const { taskID } = message;
    
    // 如果 taskID 未定义，直接返回
    if (taskID === undefined) {
        return;
    }
    
    // 移除 JS 中的缓存数据
    delete JSBridge.messages[taskID];
}
