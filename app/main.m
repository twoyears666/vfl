// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>
#import <signal.h>

#import "VFLAppDelegate.h"

int main(int argc, char *argv[]) {
	@autoreleasepool {
		// 往已断开的 socket 写数据时不能把 App 打死。
		signal(SIGPIPE, SIG_IGN);
		return UIApplicationMain(argc, argv, nil, NSStringFromClass(VFLAppDelegate.class));
	}
}
