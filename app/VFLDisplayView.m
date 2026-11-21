// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666
//
// 画面与触摸的私有 API 用法参考 nfzerox/VirtualMacOniPad（MIT License）：
// vz/host/VirtualMacApp.m 的 prepareFramebuffer 与 VZNativeTouchInput.m。
// VZ 在 iOS 上没有公开的 VZVirtualMachineView，只能用 _VZFramebufferView，
// 而且不能把它塞进 UIView 树（AppKit/UIKit 布局 ABI 不兼容），只取它的层。

#import "VFLDisplayView.h"

#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id VFLObjectForKey(id object, NSString *key) {
	if (object == nil) {
		return nil;
	}
	@try {
		return [object valueForKey:key];
	} @catch (NSException *exception) {
		return nil;
	}
}

static NSUInteger VFLFreeTouchIndex(NSUInteger occupied) {
	for (NSUInteger index = 0; index < 10; index++) {
		if ((occupied & (1UL << index)) == 0) {
			return index;
		}
	}
	return NSNotFound;
}

@interface VFLDisplayView ()

@property (nonatomic, strong, nullable) id machine;
@property (nonatomic, strong) NSArray *framebuffers;
@property (nonatomic, strong, nullable) id touchDevice;
@property (nonatomic, strong, nullable) id framebufferView;
@property (nonatomic, weak, nullable) CALayer *displayLayer;
/// UITouch 指针 → 触控槽位（NSNumber）。
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSNumber *> *touchIndexes;
/// UITouch 指针 → 最近一次的归一化位置（NSValue 包 CGPoint）。
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSValue *> *touchPoints;
@property (nonatomic, assign) NSUInteger touchMask;

@end

@implementation VFLDisplayView

- (instancetype)initWithMachine:(id)machine {
	self = [super initWithFrame:CGRectZero];
	if (self) {
		_machine = machine;
		_touchIndexes = [NSMutableDictionary dictionary];
		_touchPoints = [NSMutableDictionary dictionary];
		_displayIndex = 0;
		self.backgroundColor = UIColor.blackColor;
		self.clipsToBounds = YES;
		self.multipleTouchEnabled = YES;
		[self reloadDevices];
		[self rebuildFramebufferView];
	}
	return self;
}

- (void)dealloc {
	[self teardownFramebufferView];
}

#pragma mark - 设备

- (void)reloadDevices {
	NSArray *graphicsDevices = VFLObjectForKey(self.machine, @"_graphicsDevices")
		?: VFLObjectForKey(self.machine, @"graphicsDevices");
	id graphicsDevice = [graphicsDevices isKindOfClass:NSArray.class] ? [graphicsDevices firstObject] : nil;
	NSArray *framebuffers = VFLObjectForKey(graphicsDevice, @"framebuffers");
	self.framebuffers = [framebuffers isKindOfClass:NSArray.class] ? framebuffers : @[];

	NSArray *touchDevices = VFLObjectForKey(self.machine, @"_multiTouchDevices");
	id device = [touchDevices isKindOfClass:NSArray.class] ? [touchDevices firstObject] : nil;
	self.touchDevice = [device respondsToSelector:NSSelectorFromString(@"sendMultiTouchEvents:")] ? device : nil;
}

- (BOOL)available {
	return self.framebufferView != nil;
}

- (NSUInteger)displayCount {
	return MAX((NSUInteger)1, self.framebuffers.count);
}

- (void)setDisplayIndex:(NSUInteger)displayIndex {
	NSUInteger limit = self.framebuffers.count;
	if (limit == 0 || displayIndex >= limit) {
		return;
	}
	if (_displayIndex == displayIndex && self.framebufferView != nil) {
		return;
	}
	_displayIndex = displayIndex;
	[self rebuildFramebufferView];
}

#pragma mark - Framebuffer

- (void)teardownFramebufferView {
	[self cancelAllTouches];
	[self.displayLayer removeFromSuperlayer];
	self.displayLayer = nil;
	self.framebufferView = nil;
}

- (void)rebuildFramebufferView {
	[self teardownFramebufferView];

	if (self.framebuffers.count == 0) {
		return;
	}
	Class viewClass = NSClassFromString(@"_VZFramebufferView");
	if (viewClass == Nil) {
		NSLog(@"[VFL] 没有 _VZFramebufferView，退回串口控制台");
		return;
	}
	id framebuffer = self.framebuffers[MIN(self.displayIndex, self.framebuffers.count - 1)];
	id view = [[viewClass alloc] initWithFrame:self.bounds];
	if (![view respondsToSelector:NSSelectorFromString(@"setFramebuffer:")]) {
		return;
	}
	@try {
		[view setValue:framebuffer forKey:@"framebuffer"];
	} @catch (NSException *exception) {
		NSLog(@"[VFL] 设置 framebuffer 失败：%@", exception.reason);
		return;
	}
	if ([view respondsToSelector:NSSelectorFromString(@"setShowsCursor:")]) {
		((void (*)(id, SEL, BOOL))objc_msgSend)(view, NSSelectorFromString(@"setShowsCursor:"), NO);
	}
	if ([view respondsToSelector:@selector(layout)]) {
		[view performSelector:@selector(layout)];
	}

	CALayer *layer = [view respondsToSelector:@selector(layer)] ? [view layer] : nil;
	if (layer == nil) {
		return;
	}
	layer.frame = self.bounds;
	[self.layer insertSublayer:layer atIndex:0];
	self.framebufferView = view;
	self.displayLayer = layer;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	self.displayLayer.frame = self.bounds;
}

#pragma mark - 触摸

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:[touches allObjects]];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:[touches allObjects]];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:[touches allObjects]];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self sendTouches:[touches allObjects]];
}

- (void)cancelAllTouches {
	if (self.touchIndexes.count == 0 || self.touchDevice == nil) {
		[self.touchIndexes removeAllObjects];
		[self.touchPoints removeAllObjects];
		self.touchMask = 0;
		return;
	}
	NSMutableArray<NSDictionary *> *frame = [NSMutableArray array];
	for (NSValue *key in self.touchIndexes) {
		CGPoint point = [self.touchPoints[key] CGPointValue];
		[frame addObject:@{ @"index": self.touchIndexes[key], @"phase": @4,
							@"x": @(point.x), @"y": @(point.y) }];
	}
	[self sendFrame:frame];
	[self.touchIndexes removeAllObjects];
	[self.touchPoints removeAllObjects];
	self.touchMask = 0;
}

- (void)sendTouches:(NSArray<UITouch *> *)touches {
	if (self.touchDevice == nil) {
		return;
	}

	NSMutableSet<NSValue *> *present = [NSMutableSet set];
	NSMutableArray<NSDictionary *> *frame = [NSMutableArray array];

	for (UITouch *touch in touches) {
		if (touch.type != UITouchTypeDirect) {
			continue;
		}
		NSValue *key = [NSValue valueWithPointer:(__bridge const void *)touch];
		[present addObject:key];

		NSInteger phase = (NSInteger)touch.phase;
		if (phase < 0 || phase > 4) {
			continue;
		}
		NSNumber *index = self.touchIndexes[key];
		if (phase == 0) {
			if (index != nil) {
				continue;
			}
			NSUInteger slot = VFLFreeTouchIndex(self.touchMask);
			if (slot == NSNotFound) {
				continue;
			}
			index = @(slot);
			self.touchIndexes[key] = index;
			self.touchMask |= (1UL << slot);
		}
		if (index == nil) {
			continue;
		}
		CGPoint point = [touch locationInView:self];
		CGFloat width = MAX(self.bounds.size.width, 1.0);
		CGFloat height = MAX(self.bounds.size.height, 1.0);
		CGPoint normalized = CGPointMake(fmin(1.0, fmax(0.0, point.x / width)),
										 fmin(1.0, fmax(0.0, point.y / height)));
		self.touchPoints[key] = [NSValue valueWithCGPoint:normalized];
		[frame addObject:@{
			@"index": index,
			@"phase": @(phase),
			@"x": @(normalized.x),
			@"y": @(normalized.y),
		}];
	}

	// 这一帧里没出现的手指保持按住，否则客户机会当成全部抬起。
	for (NSValue *key in self.touchIndexes) {
		if ([present containsObject:key]) {
			continue;
		}
		CGPoint point = [self.touchPoints[key] CGPointValue];
		[frame addObject:@{ @"index": self.touchIndexes[key], @"phase": @2,
							@"x": @(point.x), @"y": @(point.y) }];
	}

	[self sendFrame:frame];

	for (UITouch *touch in touches) {
		if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
			continue;
		}
		NSValue *key = [NSValue valueWithPointer:(__bridge const void *)touch];
		NSNumber *index = self.touchIndexes[key];
		if (index == nil) {
			continue;
		}
		self.touchMask &= ~(1UL << index.unsignedIntegerValue);
		[self.touchIndexes removeObjectForKey:key];
		[self.touchPoints removeObjectForKey:key];
	}
}

- (void)sendFrame:(NSArray<NSDictionary *> *)frame {
	if (frame.count == 0 || self.touchDevice == nil) {
		return;
	}
	Class touchClass = NSClassFromString(@"_VZTouch");
	Class eventClass = NSClassFromString(@"_VZMultiTouchEvent");
	if (touchClass == Nil || eventClass == Nil) {
		return;
	}

	NSMutableSet *touchObjects = [NSMutableSet set];
	for (NSDictionary *entry in frame) {
		CGPoint location = CGPointMake([entry[@"x"] doubleValue], [entry[@"y"] doubleValue]);
		id (*makeTouch)(id, SEL, unsigned char, NSInteger, CGPoint, NSInteger, double) =
			(id (*)(id, SEL, unsigned char, NSInteger, CGPoint, NSInteger, double))objc_msgSend;
		// class_createInstance 不受 ARC 管理，+1 由下面的 CFRelease 平衡。
		__unsafe_unretained id raw = class_createInstance(touchClass, 0);
		__unsafe_unretained id touch = makeTouch(raw,
												 NSSelectorFromString(@"initWithIndex:phase:location:swipeAim:timestamp:"),
												 (unsigned char)[entry[@"index"] unsignedIntegerValue],
												 [entry[@"phase"] integerValue],
												 location,
												 0,
												 NSProcessInfo.processInfo.systemUptime);
		if (touch != nil) {
			[touchObjects addObject:touch];
			CFRelease((__bridge CFTypeRef)touch);
		}
	}
	if (touchObjects.count == 0) {
		return;
	}

	id (*makeEvent)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
	__unsafe_unretained id rawEvent = class_createInstance(eventClass, 0);
	__unsafe_unretained id multiTouchEvent = makeEvent(rawEvent,
													   NSSelectorFromString(@"initWithTouches:"),
													   touchObjects);
	if (multiTouchEvent == nil) {
		return;
	}
	((void (*)(id, SEL, id))objc_msgSend)(self.touchDevice,
										 NSSelectorFromString(@"sendMultiTouchEvents:"),
										 @[ multiTouchEvent ]);
	CFRelease((__bridge CFTypeRef)multiTouchEvent);
}

@end
