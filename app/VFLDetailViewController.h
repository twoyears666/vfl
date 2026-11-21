// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

/// 单台虚拟机的详情：配置、状态、启动/关机入口。
@interface VFLDetailViewController : UIViewController

- (instancetype)initWithVMName:(NSString *)name;

@end
