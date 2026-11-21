// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 与 vfl 守护进程通信的客户端。协议是一行一个 JSON。
/// - 请求/响应：sendRequest:error:（同步）
/// - 控制台：enterControlModeWithVM:handler: 之后，事件通过 eventHandler 回调
@interface VFLClient : NSObject

@property (nonatomic, copy, nullable) void (^eventHandler)(NSDictionary *event);
/// 最近一次进入控制台时守护进程报告的虚拟机状态（stopped/running/…）。
@property (nonatomic, copy, readonly) NSString *lastState;

+ (nullable instancetype)connectWithError:(NSError **)error;

/// 同步发一条命令并等回应。vm 可以为 nil（list 之类）。
- (nullable NSDictionary *)sendRequestWithCommand:(NSString *)command
											   vm:(nullable NSString *)vm
											error:(NSError **)error;

/// 进入控制台订阅：先拿到 ok，再通过 eventHandler 收 console/state 事件。
- (BOOL)enterControlModeWithVM:(NSString *)name error:(NSError **)error;

- (void)sendConsoleInput:(NSData *)data;
- (void)detach;
- (void)close;

@end

NS_ASSUME_NONNULL_END
