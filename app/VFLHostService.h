// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <Foundation/Foundation.h>

#import "VFLMachineSession.h"

NS_ASSUME_NONNULL_BEGIN

/// App 内的 VFLServer。VZ 的画面视图必须和 VZVirtualMachine 同进程，
/// 所以 GUI 启动时把服务端拉进 App；CLI 仍然通过同一个 socket 连进来。
/// 如果 socket 被独立 daemon 占用，这里的启动会失败，GUI 自动退回串口模式。
@interface VFLHostService : NSObject

@property (class, nonatomic, readonly) VFLHostService *shared;

@property (nonatomic, readonly) BOOL hosting;
/// 启动失败的原因（成功时为 nil）。
@property (nonatomic, copy, readonly, nullable) NSString *diagnostic;

- (void)start;
- (nullable VFLMachineSession *)sessionNamed:(NSString *)name;
/// 是否有虚拟机正在启动 / 运行 / 关机。
- (BOOL)hasActiveSession;

@end

NS_ASSUME_NONNULL_END
