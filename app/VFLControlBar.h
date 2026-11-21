// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, VFLControlBarCorner) {
	VFLControlBarCornerTopLeft = 0,
	VFLControlBarCornerTopRight,
	VFLControlBarCornerBottomLeft,
	VFLControlBarCornerBottomRight,
};

/// 悬浮在控制台画面上的控制条。只有「更多」时是一个圆；
/// 键盘按钮在时是左右圆、上下平的胶囊。
@interface VFLControlBar : UIView

- (instancetype)initWithKeyboardHandler:(void (^)(void))keyboardHandler;

/// 挂在「更多」按钮上的菜单。
@property (nonatomic, copy) UIMenu *menu;

/// 贴在哪个角。改这个值会重建约束。
@property (nonatomic, assign) VFLControlBarCorner corner;

/// 整体透明度，0.2–1.0。
@property (nonatomic, assign) CGFloat barOpacity;

/// 有没有键盘按钮（没接外接键盘时才有）。
@property (nonatomic, assign, getter=isKeyboardButtonVisible) BOOL keyboardButtonVisible;

@end
