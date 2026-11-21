// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666
//
// 从 macOS 提取的 Virtualization.framework 里，画面视图是 NSView 的子类。
// iOS 没有 AppKit，这里用 UIView 顶替 NSView，让这些类能正常初始化；
// 参考 nfzerox/VirtualMacOniPad 的 vz/host/NSViewShim.m（MIT）。

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSView : UIView
- (void)layout;
@end

FOUNDATION_EXPORT NSString *const NSApplicationWillTerminateNotification;
FOUNDATION_EXPORT NSString *const NSWindowDidBecomeKeyNotification;
FOUNDATION_EXPORT NSString *const NSWindowDidChangeOcclusionStateNotification;
FOUNDATION_EXPORT NSString *const NSWindowDidResignKeyNotification;

/// 关掉画面刷新请求时，occlusionState 会报「不可见」，让 VZ 暂停出帧。
FOUNDATION_EXPORT void VZSetNSViewFrameRequestsSuppressed(BOOL suppressed);

FOUNDATION_EXPORT uint32_t CGSMainConnectionID(void);
FOUNDATION_EXPORT int CGSActuateDeviceWithPattern(uint32_t connection,
												  uint64_t device,
												  uint32_t pattern,
												  uint64_t options);

NS_ASSUME_NONNULL_END
