// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <Foundation/Foundation.h>

#import "VFLVMDefinition.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VFLMachineState) {
	VFLMachineStateStopped = 0,
	VFLMachineStateStarting,
	VFLMachineStateRunning,
	VFLMachineStateStopping,
	VFLMachineStateError,
};

FOUNDATION_EXPORT NSString *VFLMachineStateText(VFLMachineState state);

@class VFLMachineSession;

@protocol VFLSessionObserver <NSObject>
/// 状态变化。回调可能来自任意队列，UI 侧自己切回主线程。
- (void)session:(VFLMachineSession *)session didChangeState:(VFLMachineState)state message:(NSString *)message;
/// 客户机串口输出。回调来自串口专用队列，写 socket 之类的操作请自行串行化。
- (void)session:(VFLMachineSession *)session didOutputConsoleData:(NSData *)data;
@end

/// 一台真正跑在 Virtualization.framework 上的虚拟机。
/// 串口读写走独立队列与非阻塞管道：客户机有画面时也不会被控制台 I/O 卡住。
@interface VFLMachineSession : NSObject

@property (nonatomic, readonly) VFLVMDefinition *definition;
@property (nonatomic, readonly) VFLMachineState state;
@property (nonatomic, readonly) NSString *lastMessage;
@property (nonatomic, readonly) BOOL isActive;

- (instancetype)initWithDefinition:(VFLVMDefinition *)definition;

/// 建配置并启动。返回 NO 时 error 说明哪一步不成立（内核不存在、权限缺失……）。
- (BOOL)startWithError:(NSError **)error;
/// 优雅关机：走客户机的 ACPI / PSCI，等同 `vfl shut`。
- (void)requestShutdown;
/// 强制断电：等同 `vfl kill`。
- (void)forceStop;

/// 往客户机串口写数据（CLI 的 control 与 GUI 的按键都走这里）。
- (void)sendConsoleInput:(NSData *)data;
/// 启动以来累计的控制台输出（最多保留 256 KB），重新 attach 时用来还原上下文。
- (NSData *)consoleSnapshot;

- (void)addObserver:(id<VFLSessionObserver>)observer;
- (void)removeObserver:(id<VFLSessionObserver>)observer;

@end

NS_ASSUME_NONNULL_END
