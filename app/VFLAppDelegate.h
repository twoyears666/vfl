// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

@interface VFLAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
/// 切到后台时用来撑住音频启动的后台任务。
@property (nonatomic, assign) UIBackgroundTaskIdentifier backgroundTask;

@end
