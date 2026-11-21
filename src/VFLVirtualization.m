// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLVirtualization.h"

#import <dlfcn.h>

static NSString *const VFLVirtualizationRequiredClasses[] = {
	@"VZVirtualMachineConfiguration",
	@"VZLinuxBootLoader",
	@"VZVirtualMachine",
	@"VZDiskImageStorageDeviceAttachment",
	@"VZVirtioBlockDeviceConfiguration",
	@"VZVirtioNetworkDeviceConfiguration",
	@"VZNATNetworkDeviceAttachment",
	@"VZFileHandleSerialPortAttachment",
	@"VZVirtioConsoleDeviceSerialPortConfiguration",
	@"VZVirtioEntropyDeviceConfiguration",
};

BOOL VFLVirtualizationPrepare(NSString **diagnostic) {
	static dispatch_once_t once;
	static BOOL ready = NO;
	static NSString *reason = nil;
	dispatch_once(&once, ^{
		// 框架在公开目录和私有目录都可能出现，两个都试；dlopen 失败不影响已加载的系统库。
		const char *paths[] = {
			"/System/Library/Frameworks/Virtualization.framework/Virtualization",
			"/System/Library/PrivateFrameworks/Virtualization.framework/Virtualization",
		};
		void *handle = NULL;
		for (size_t index = 0; index < sizeof(paths) / sizeof(paths[0]) && handle == NULL; index++) {
			handle = dlopen(paths[index], RTLD_LAZY);
		}
		if (handle == NULL) {
			reason = @"系统里没有 Virtualization.framework（需要 iPadOS 16 及以上）";
			ready = NO;
			return;
		}

		NSMutableArray<NSString *> *missing = [NSMutableArray array];
		for (size_t index = 0;
			 index < sizeof(VFLVirtualizationRequiredClasses) / sizeof(VFLVirtualizationRequiredClasses[0]);
			 index++) {
			NSString *name = VFLVirtualizationRequiredClasses[index];
			if (NSClassFromString(name) == nil) {
				[missing addObject:name];
			}
		}
		if (missing.count > 0) {
			reason = [NSString stringWithFormat:@"Virtualization.framework 缺少类：%@",
					  [missing componentsJoinedByString:@", "]];
			ready = NO;
			return;
		}
		ready = YES;
	});

	if (diagnostic != NULL) {
		*diagnostic = reason;
	}
	return ready;
}
