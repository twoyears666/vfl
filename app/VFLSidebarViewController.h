// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

@class VFLSidebarViewController;

NS_ASSUME_NONNULL_BEGIN

@protocol VFLSidebarDelegate <NSObject>
/// 选中一台虚拟机；name 为 nil 表示列表空了。
- (void)sidebarViewController:(VFLSidebarViewController *)controller
			 didSelectVMNamed:(nullable NSString *)name;
@end

@interface VFLSidebarViewController : UITableViewController

@property (nonatomic, weak, nullable) id<VFLSidebarDelegate> selectionDelegate;

- (void)reloadMachines;
- (void)selectMachineAtIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
