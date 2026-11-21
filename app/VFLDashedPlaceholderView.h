// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

/// 虚线占位框，用来标记「这里应该放一张图」。
/// vfl 的 Virtualization.framework 在 iPadOS 上没有画面视图，这里作为启动入口。
@interface VFLDashedPlaceholderView : UIView

@property (nonatomic, copy) NSString *text;

/// 点按整个占位区的回调。
@property (nonatomic, copy) void (^onTap)(void);

@end
