// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLHostService.h"

#import "VFLServer.h"

@interface VFLHostService ()

@property (nonatomic, strong) VFLServer *server;
@property (nonatomic, assign) BOOL hosting;
@property (nonatomic, copy, nullable) NSString *diagnostic;

@end

@implementation VFLHostService

+ (VFLHostService *)shared {
	static VFLHostService *service = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		service = [[VFLHostService alloc] init];
	});
	return service;
}

- (void)start {
	if (self.hosting) {
		return;
	}
	VFLServer *server = [[VFLServer alloc] init];
	NSError *error = nil;
	if (![server startWithError:&error]) {
		self.diagnostic = error.localizedDescription ?: @"无法启动内置服务";
		NSLog(@"[VFL] 内置虚拟机服务启动失败：%@", self.diagnostic);
		return;
	}
	self.server = server;
	self.hosting = YES;
	self.diagnostic = nil;
	NSLog(@"[VFL] 内置虚拟机服务已启动，虚拟机将运行在 App 进程内");
}

- (VFLMachineSession *)sessionNamed:(NSString *)name {
	if (!self.hosting || name.length == 0) {
		return nil;
	}
	return [self.server sessionNamed:name];
}

@end
