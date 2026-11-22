// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 虚拟机运行时用静音音频把 App 留在后台。
/// iOS 一旦挂起 App，App 内的 VMM 子进程也会被停掉，长编译会直接断掉。
@interface VFLBackgroundKeeper : NSObject

@property (class, nonatomic, readonly) VFLBackgroundKeeper *shared;

@property (nonatomic, readonly) BOOL active;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
