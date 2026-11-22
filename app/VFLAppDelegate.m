// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLAppDelegate.h"

#import <execinfo.h>
#import <signal.h>
#import <stdio.h>

#import "VFLBackgroundKeeper.h"
#import "VFLHostService.h"
#import "VFLRootSplitViewController.h"
#import "VFLVMDefinition.h"

@implementation VFLAppDelegate

/// 未捕获的 Objective-C 异常先落到 app.log，闪退后至少能看到原因。
static void VFLHandleUncaughtException(NSException *exception) {
	fprintf(stderr, "[VFL] 未捕获异常：%s\n%s\n",
			exception.reason.UTF8String ?: "",
			exception.callStackSymbols.description.UTF8String ?: "");
	fflush(stderr);
}

/// VZ 内部崩溃是信号不是异常，单独抓 SIGSEGV/SIGABRT 等并打回溯。
static void VFLHandleFatalSignal(int signalNumber) {
	fprintf(stderr, "[VFL] 崩溃信号 %d (%s)\n",
			signalNumber, strsignal(signalNumber) ?: "unknown");
	void *frames[64];
	int count = backtrace(frames, 64);
	backtrace_symbols_fd(frames, count, STDERR_FILENO);
	fflush(stderr);
	signal(signalNumber, SIG_DFL);
	raise(signalNumber);
}

static void VFLInstallCrashHandlers(void) {
	NSSetUncaughtExceptionHandler(VFLHandleUncaughtException);
	for (int number = 0; number < NSIG; number++) {
		switch (number) {
			case SIGSEGV: case SIGABRT: case SIGBUS:
			case SIGILL: case SIGFPE: case SIGTRAP:
				signal(number, VFLHandleFatalSignal);
				break;
		}
	}
}

- (BOOL)application:(UIApplication *)application
	didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	[self redirectLogToFile];
	VFLInstallCrashHandlers();
	// 先抢 socket：GUI 要拿到 VZVirtualMachine 才能显示画面。
	[[VFLHostService shared] start];

	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.window.rootViewController = [[VFLRootSplitViewController alloc] init];
	[self.window makeKeyAndVisible];
	return YES;
}

/// 有虚拟机在跑时用静音音频把进程留在后台，否则挂起会把 VMM 一起停掉。
- (void)applicationDidEnterBackground:(UIApplication *)application {
	if ([[VFLHostService shared] hasActiveSession]) {
		// 音频激活本身需要一点时间，先用后台任务把这段窗口撑住。
		self.backgroundTask = [application beginBackgroundTaskWithName:@"VFL 虚拟机保活"
														expirationHandler:^{
			[application endBackgroundTask:self.backgroundTask];
			self.backgroundTask = UIBackgroundTaskInvalid;
		}];
		[[VFLBackgroundKeeper shared] start];
	}
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
	[[VFLBackgroundKeeper shared] stop];
	if (self.backgroundTask != UIBackgroundTaskInvalid) {
		[application endBackgroundTask:self.backgroundTask];
		self.backgroundTask = UIBackgroundTaskInvalid;
	}
}

/// App 不在 Xcode 下运行时 NSLog 走 stderr；重定向到 Media/VFL/app.log 方便事后排查。
- (void)redirectLogToFile {
	NSString *directory = VFLDataDirectory();
	[NSFileManager.defaultManager createDirectoryAtPath:directory
						   withIntermediateDirectories:YES
											attributes:nil
												 error:NULL];
	NSString *path = [directory stringByAppendingPathComponent:@"app.log"];
	freopen(path.fileSystemRepresentation, "a", stderr);
	fprintf(stderr, "\n===== VFL 启动 %s =====\n",
			NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String ?: "");
}

@end
