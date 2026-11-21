// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

/// 串口控制台：终端画面 + 按键条 + 显示设备切换。
/// 与 `vfl control` 连的是同一个守护进程会话，退出再进来还是同一份上下文。
@interface VFLConsoleViewController : UIViewController

- (instancetype)initWithVMName:(NSString *)name;

@end
