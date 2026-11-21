// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLVirtualization.h"

#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <sys/utsname.h>
#import <unistd.h>

#import "VFLVMDefinition.h"

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

/// 自带框架的加载顺序：被依赖的库必须先 RTLD_GLOBAL 加载，
/// 否则 Virtualization 解析不到 Hypervisor / PVG 的符号。
static NSString *const VFLBundledImages[] = {
	@"vmnet.framework/vmnet",
	@"Hypervisor.framework/Hypervisor",
	@"MetalSerializer.framework/MetalSerializer",
	@"ParavirtualizedGraphics.framework/ParavirtualizedGraphics",
	@"Virtualization.framework/Virtualization",
};

static NSString *VFLBundleRelativePath(NSString *relative) {
	NSString *frameworks = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks"];
	return [frameworks stringByAppendingPathComponent:relative];
}

/// 依次尝试：App 自带 Frameworks → 常见 rootless/rootful 安装目录 → 系统框架。
static void *VFLOpenImage(NSString *relative, NSMutableArray<NSString *> *failures) {
	NSMutableArray<NSString *> *candidates = [NSMutableArray array];
	[candidates addObject:VFLBundleRelativePath(relative)];

	NSString *top = relative.pathComponents.firstObject;
	NSString *inner = [relative substringFromIndex:MIN(relative.length, top.length + 1)];
	if ([relative containsString:@".framework/"]) {
		[candidates addObject:[@"/var/jb/System/Library/Frameworks" stringByAppendingPathComponent:relative]];
		[candidates addObject:[@"/System/Library/Frameworks" stringByAppendingPathComponent:relative]];
		[candidates addObject:[@"/var/jb/System/Library/PrivateFrameworks" stringByAppendingPathComponent:relative]];
		[candidates addObject:[@"/System/Library/PrivateFrameworks" stringByAppendingPathComponent:relative]];
	} else if (inner.length > 0) {
		[candidates addObject:[@"/var/jb/usr/lib" stringByAppendingPathComponent:inner]];
		[candidates addObject:[@"/usr/lib" stringByAppendingPathComponent:inner]];
	}

	for (NSString *path in candidates) {
		if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
			continue;
		}
		void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
		if (handle != NULL) {
			return handle;
		}
		const char *error = dlerror();
		[failures addObject:[NSString stringWithFormat:@"%@：%s", path, error ?: "未知错误"]];
	}
	return NULL;
}

/// macOS 提取出来的 VZ 需要把 Objective-C 方法里的若干直接调用重绑到 iOS 版本；
/// 这一步由 VMOI 的 VZHostCompat 提供（MIT），没有它 VZ 一启动就会崩。
static void VFLRebindVirtualization(void *hookHandle, NSMutableArray<NSString *> *failures) {
	Class machineClass = NSClassFromString(@"VZVirtualMachine");
	SEL selector = NSSelectorFromString(@"startWithCompletionHandler:");
	Method method = machineClass != Nil ? class_getInstanceMethod(machineClass, selector) : NULL;
	Dl_info image = { 0 };
	if (method == NULL || !dladdr((const void *)method_getImplementation(method), &image) || image.dli_fbase == NULL) {
		[failures addObject:@"无法定位 Virtualization 的镜像基址"];
		return;
	}
	int (*rebind)(void *) = (int (*)(void *))dlsym(hookHandle, "vz_rebind_virtualization");
	if (rebind == NULL) {
		[failures addObject:@"VZHostCompat 缺少 vz_rebind_virtualization"];
		return;
	}
	if (rebind(image.dli_fbase) != 0) {
		[failures addObject:@"VZHostCompat 重绑失败（版本不匹配）"];
	}
}

BOOL VFLVirtualizationPrepare(NSString **diagnostic) {
	static dispatch_once_t once;
	static BOOL ready = NO;
	static NSString *reason = nil;
	dispatch_once(&once, ^{
		NSMutableArray<NSString *> *failures = [NSMutableArray array];

		// iPadOS 16.4 起内核移除了 Hypervisor；此时 VZ 一启动就会崩，提前拦住并给出原因。
		NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
		struct utsname systemInfo = { 0 };
		uname(&systemInfo);
		NSLog(@"[VFL] 设备 %s，系统 %ld.%ld.%ld", systemInfo.machine,
			  (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion);
		if (os.majorVersion > 16 || (os.majorVersion == 16 && os.minorVersion >= 4)) {
			reason = @"iPadOS 16.4 起内核已移除 Hypervisor 支持，无法硬件虚拟化";
			ready = NO;
			return;
		}

		// 1. 先加载 host hook：它给 VZ 提供 iOS 缺失的 API 与 XPC 桥。
		NSString *bundlePath = NSBundle.mainBundle.bundlePath;
		// hook 默认去找 /var/root/VirtualMac/payload；我们用 App 自带的副本。
		NSString *vmmBinary = [bundlePath stringByAppendingPathComponent:
			@"VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine"];
		if ([NSFileManager.defaultManager fileExistsAtPath:vmmBinary]) {
			setenv("VZ_VMM_BIN", vmmBinary.fileSystemRepresentation, 1);
		}
		NSString *installationBinary = [bundlePath stringByAppendingPathComponent:
			@"Installation.xpc/Contents/MacOS/com.apple.Virtualization.Installation"];
		if ([NSFileManager.defaultManager fileExistsAtPath:installationBinary]) {
			setenv("VZ_INSTALLATION_BIN", installationBinary.fileSystemRepresentation, 1);
		}
		// VMOI 用这几个环境变量绕开 VMM 工厂初始化竞态，并把子进程日志留在设备上。
		setenv("VMM_FACTORY_SETTLE_USEC", "100000", 1);
		setenv("VZ_DEBUG_LOGGING", "1", 1);
		NSString *vmmStderr = [VFLDataDirectory() stringByAppendingPathComponent:@"vmm.stderr.log"];
		setenv("VZ_VMM_STDERR_LOG", vmmStderr.fileSystemRepresentation, 1);
		NSString *booter = [bundlePath stringByAppendingPathComponent:
			@"Frameworks/Virtualization.framework/Resources/AVPBooter.vmapple2.bin"];
		if ([NSFileManager.defaultManager fileExistsAtPath:booter]) {
			setenv("VZ_AVP_BOOTER", booter.fileSystemRepresentation, 1);
		}
		// 每次启动都从空日志开始，避免把上一轮的内容当成这次失败的原因。
		unlink("/tmp/vzxpchook.log");
		unlink("/tmp/vmmhook.log");
		unlink(vmmStderr.fileSystemRepresentation);

		void *hook = NULL;
		NSString *hookPath = [bundlePath stringByAppendingPathComponent:@"VZHostCompat.dylib"];
		if ([NSFileManager.defaultManager fileExistsAtPath:hookPath]) {
			hook = dlopen(hookPath.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
			if (hook == NULL) {
				[failures addObject:[NSString stringWithFormat:@"VZHostCompat：%s", dlerror() ?: "加载失败"]];
			}
		}

		// 2. 按依赖顺序加载自带框架；系统里已有的镜像会直接命中缓存。
		for (size_t index = 0; index < sizeof(VFLBundledImages) / sizeof(VFLBundledImages[0]); index++) {
			NSString *relative = VFLBundledImages[index];
			void *handle = VFLOpenImage(relative, failures);
			if (handle == NULL) {
				if ([relative hasPrefix:@"Virtualization.framework/"]) {
					reason = [NSString stringWithFormat:@"Virtualization.framework 不可用：%@",
							  [failures.lastObject ?: @"未找到" description]];
					ready = NO;
					return;
				}
				// Hypervisor / PVG / vmnet 缺失时继续，交给后面的类检查报错。
				continue;
			}
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

		if (hook != NULL) {
			VFLRebindVirtualization(hook, failures);
		}

		if (failures.count > 0) {
			NSLog(@"[VFL] Virtualization 加载警告：%@", [failures componentsJoinedByString:@"；"]);
		}
		ready = YES;
	});

	if (diagnostic != NULL) {
		*diagnostic = reason;
	}
	return ready;
}
