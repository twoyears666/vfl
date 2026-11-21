// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 客户机画面：把 Virtualization 的 framebuffer 层挂到普通 UIView 上，
/// 并把触摸转成 VZ 的多点触控事件。framework 缺失时 available 为 NO。
@interface VFLDisplayView : UIView

- (instancetype)initWithMachine:(id)machine NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) NSUInteger displayCount;
/// 0 起的显示设备序号；切换时重建 framebuffer 视图。
@property (nonatomic, assign) NSUInteger displayIndex;

- (void)cancelAllTouches;

@end

NS_ASSUME_NONNULL_END
