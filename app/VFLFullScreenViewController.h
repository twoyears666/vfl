// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 全屏串口控制台：终端 + 键盘 + 悬浮控制条。
/// 藏起导航栏和分栏侧栏，退出去时全部还原。
@interface VFLFullScreenViewController : UIViewController

- (instancetype)initWithVMName:(NSString *)name displayCount:(NSUInteger)displayCount;

/// 退出本页后回调（详情页借此刷新状态）。
@property (nonatomic, copy, nullable) void (^dismissHandler)(void);

@end

NS_ASSUME_NONNULL_END
