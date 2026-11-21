// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666
//
// 参考 nfzerox/VirtualMacOniPad 的 vz/host/NSViewShim.m（MIT License）。
// 只保留 vfl 用到的部分：NSView→UIView、AppKit 通知常量、CGS 空实现。

#import "VFLNSViewShim.h"

NSString *const NSApplicationWillTerminateNotification = @"NSApplicationWillTerminateNotification";
NSString *const NSWindowDidBecomeKeyNotification = @"NSWindowDidBecomeKeyNotification";
NSString *const NSWindowDidChangeOcclusionStateNotification = @"NSWindowDidChangeOcclusionStateNotification";
NSString *const NSWindowDidResignKeyNotification = @"NSWindowDidResignKeyNotification";

static BOOL VFLSuppressFrameRequests;

// macOS 触控板反馈在 iPadOS 上没有对应设备，留空实现避免首击崩溃。
uint32_t CGSMainConnectionID(void) {
	return 0;
}

int CGSActuateDeviceWithPattern(uint32_t connection,
								uint64_t device,
								uint32_t pattern,
								uint64_t options) {
	(void)connection;
	(void)device;
	(void)pattern;
	(void)options;
	return 0;
}

void VZSetNSViewFrameRequestsSuppressed(BOOL suppressed) {
	VFLSuppressFrameRequests = suppressed;
}

@implementation NSView {
	CALayer *_appKitLayer;
}

- (void)setWantsLayer:(BOOL)wantsLayer {
	(void)wantsLayer;
}

- (BOOL)wantsLayer {
	return YES;
}

- (void)setLayer:(CALayer *)layer {
	if (_appKitLayer == layer) {
		return;
	}
	[_appKitLayer removeFromSuperlayer];
	_appKitLayer = layer;
	_appKitLayer.frame = self.bounds;
	[super.layer addSublayer:_appKitLayer];
}

- (CALayer *)layer {
	return _appKitLayer ?: super.layer;
}

- (UIWindow *)window {
	UIWindow *window = super.window;
	if (window != nil) {
		return window;
	}
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) {
			continue;
		}
		for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
			if (candidate.isKeyWindow) {
				return candidate;
			}
		}
	}
	return nil;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	_appKitLayer.frame = self.bounds;
	if ([self respondsToSelector:@selector(layout)]) {
		[self performSelector:@selector(layout)];
	}
}

- (void)layout {
	// AppKit 的布局钩子；UIView 走 layoutSubviews。
}

@end

@implementation UIWindow (VFLAppKitOcclusion)

- (NSUInteger)occlusionState {
	// NSWindowOcclusionStateVisible == 2。
	return self.hidden || VFLSuppressFrameRequests ? 0 : 2;
}

@end
