// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 新建虚拟机：发行版图标、名称、硬件、系统盘、内核与可选安装镜像。
@interface VFLCreateMachineViewController : UIViewController

- (instancetype)initWithSuggestedName:(NSString *)suggestedName;

/// 保存成功后回调虚拟机名。
@property (nonatomic, copy, nullable) void (^completion)(NSString *name);

@end

NS_ASSUME_NONNULL_END
