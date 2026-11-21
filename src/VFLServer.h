// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <Foundation/Foundation.h>

#import "VFLMachineSession.h"

NS_ASSUME_NONNULL_BEGIN

/// 守护进程里的 socket 服务端：管着一批 VFLMachineSession，
/// 对外用「一行一个 JSON」的协议把 list/start/control/kill/shut 都暴露出去。
/// GUI 和 CLI 都是它的客户端，所以两边看到的是同一批虚拟机、同一份控制台上下文。
@interface VFLServer : NSObject

/// 会话表（按定义顺序）。没有启动过的定义不在里面。
@property (nonatomic, readonly) NSArray<VFLMachineSession *> *sessions;

- (BOOL)startWithError:(NSError **)error;
- (void)stop;

- (nullable VFLMachineSession *)sessionNamed:(NSString *)name;
- (nullable VFLMachineSession *)ensureSessionForDefinitionName:(NSString *)name
														 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
