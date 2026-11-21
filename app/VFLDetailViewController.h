// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 选中虚拟机的详情：状态、画面入口、系统/硬件/存储/显示/网络设置，以及启停操作。
@interface VFLDetailViewController : UIViewController

/// 当前展示的虚拟机名；设为 nil 显示空状态。
@property (nonatomic, copy, nullable) NSString *vmName;

@end

NS_ASSUME_NONNULL_END
