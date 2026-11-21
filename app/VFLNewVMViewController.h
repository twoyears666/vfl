// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

/// 新建虚拟机表单。保存时直接写定义 JSON 并创建系统盘镜像。
@interface VFLNewVMViewController : UITableViewController

/// 保存成功后回调（列表页用来刷新）。
@property (nonatomic, copy) void (^completion)(void);

@end
