// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLFullScreenViewController.h"

#import <math.h>

#import "VFLClient.h"
#import "VFLControlBar.h"
#import "VFLDisplayView.h"
#import "VFLHostService.h"
#import "VFLKeyInputView.h"
#import "VFLTerminalEmulator.h"
#import "VFLTerminalView.h"
#import "VFLVMDefinition.h"

@interface VFLFullScreenViewController ()

@property (nonatomic, copy) NSString *vmName;
@property (nonatomic, assign) NSUInteger displayCount;
@property (nonatomic, assign) NSUInteger currentDisplay;

@property (nonatomic, strong) VFLClient *client;
@property (nonatomic, strong) VFLTerminalEmulator *emulator;
@property (nonatomic, strong) VFLTerminalView *terminalView;
@property (nonatomic, strong) VFLKeyInputView *keyInputView;
@property (nonatomic, strong) VFLControlBar *controlBar;
@property (nonatomic, strong) UILabel *hudLabel;
@property (nonatomic, strong) UIView *hudContainer;

/// App 内托管时才有画面；daemon 模式下为 nil，界面保持串口控制台。
@property (nonatomic, strong, nullable) VFLDisplayView *displayView;
@property (nonatomic, assign) BOOL displayActive;
@property (nonatomic, assign) NSUInteger displayAttempts;

@property (nonatomic, copy) NSString *state;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) BOOL restoredBars;

@end

@implementation VFLFullScreenViewController

- (instancetype)initWithVMName:(NSString *)name displayCount:(NSUInteger)displayCount {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_vmName = [name copy];
		_displayCount = MAX(1, displayCount);
		_currentDisplay = 1;
		_state = @"unknown";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.blackColor;

	self.emulator = [[VFLTerminalEmulator alloc] init];

	self.terminalView = [[VFLTerminalView alloc] initWithFrame:CGRectZero];
	self.terminalView.translatesAutoresizingMaskIntoConstraints = NO;
	self.terminalView.emulator = self.emulator;
	[self.view addSubview:self.terminalView];

	self.keyInputView = [[VFLKeyInputView alloc] initWithFrame:CGRectZero];
	self.keyInputView.translatesAutoresizingMaskIntoConstraints = NO;
	__weak typeof(self) weakSelf = self;
	self.keyInputView.sendHandler = ^(NSData *data) {
		[weakSelf.client sendConsoleInput:data];
	};
	[self.view addSubview:self.keyInputView];

	self.controlBar = [[VFLControlBar alloc] initWithKeyboardHandler:^{
		[weakSelf toggleSoftwareKeyboard];
	}];
	[self.view addSubview:self.controlBar];

	self.hudContainer = [[UIView alloc] init];
	self.hudContainer.translatesAutoresizingMaskIntoConstraints = NO;
	self.hudContainer.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
	self.hudContainer.layer.cornerRadius = 10.0;
	self.hudContainer.userInteractionEnabled = NO;
	[self.view addSubview:self.hudContainer];

	self.hudLabel = [[UILabel alloc] init];
	self.hudLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.hudLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightMedium];
	self.hudLabel.textColor = UIColor.whiteColor;
	self.hudLabel.text = [NSString stringWithFormat:@"%@ · 连接中…", self.vmName];
	[self.hudContainer addSubview:self.hudLabel];

	[NSLayoutConstraint activateConstraints:@[
		[self.terminalView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
													constant:36.0],
		[self.terminalView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.terminalView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.terminalView.bottomAnchor constraintEqualToAnchor:self.keyInputView.topAnchor],

		[self.keyInputView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.keyInputView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.keyInputView.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
		[self.keyInputView.heightAnchor constraintEqualToConstant:48.0],

		[self.hudContainer.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor
														constant:12.0],
		[self.hudContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
													constant:4.0],
		[self.hudLabel.topAnchor constraintEqualToAnchor:self.hudContainer.topAnchor constant:6.0],
		[self.hudLabel.bottomAnchor constraintEqualToAnchor:self.hudContainer.bottomAnchor constant:-6.0],
		[self.hudLabel.leadingAnchor constraintEqualToAnchor:self.hudContainer.leadingAnchor constant:10.0],
		[self.hudLabel.trailingAnchor constraintEqualToAnchor:self.hudContainer.trailingAnchor constant:-10.0],
	]];

	UITapGestureRecognizer *tap =
		[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusKeyboard)];
	[self.terminalView addGestureRecognizer:tap];

	self.controlBar.menu = [self buildControlMenu];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.restoredBars = NO;
	[self.navigationController setNavigationBarHidden:YES animated:animated];
	UISplitViewController *split = self.splitViewController;
	if (split != nil) {
		split.preferredDisplayMode = UISplitViewControllerDisplayModeSecondaryOnly;
	}
	[self setNeedsStatusBarAppearanceUpdate];
	[self connect];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self prepareDisplayIfPossible];
	[self scheduleDisplayPreparation];
	[self.keyInputView focus];
	[self.terminalView becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self restoreBarsIfNeeded];
	[self tearDownDisplay];
	[self.client detach];
	[self.client close];
	self.client = nil;
	self.connected = NO;
	if (self.dismissHandler != nil) {
		self.dismissHandler();
	}
}

- (void)restoreBarsIfNeeded {
	if (self.restoredBars) {
		return;
	}
	self.restoredBars = YES;
	[self.navigationController setNavigationBarHidden:NO animated:YES];
	UISplitViewController *split = self.splitViewController;
	if (split != nil) {
		split.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
	}
}

- (BOOL)prefersStatusBarHidden {
	return YES;
}

- (void)dealloc {
	[self.client detach];
	[self.client close];
}

#pragma mark - 连接

- (void)connect {
	if (self.client != nil) {
		return;
	}
	NSString *name = self.vmName;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *error = nil;
		VFLClient *client = [VFLClient connectWithError:&error];
		if (client == nil) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self updateHUD:@"连不上守护进程"];
			});
			return;
		}
		__weak typeof(self) weakSelf = self;
		client.eventHandler = ^(NSDictionary *event) {
			[weakSelf handleEvent:event];
		};
		if (![client enterControlModeWithVM:name error:&error]) {
			[client close];
			dispatch_async(dispatch_get_main_queue(), ^{
				[self updateHUD:error.localizedDescription ?: @"进入控制台失败"];
			});
			return;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			self.client = client;
			self.connected = YES;
			[self updateHUD:nil];
			[self.keyInputView focus];
		});
	});
}

- (void)handleEvent:(NSDictionary *)event {
	NSString *kind = event[@"event"];
	if ([kind isEqualToString:@"console"]) {
		NSString *base64 = event[@"data"];
		NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 ?: @""
														   options:0];
		if (data.length > 0) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.emulator feed:data];
				[self.terminalView setNeedsDisplay];
			});
		}
		return;
	}
	if ([kind isEqualToString:@"state"]) {
		NSString *state = event[@"state"] ?: @"unknown";
		NSString *message = event[@"message"];
		dispatch_async(dispatch_get_main_queue(), ^{
			self.state = state;
			if ([state isEqualToString:@"running"]) {
				[self prepareDisplayIfPossible];
			}
			[self updateHUD:message];
		});
	}
}

#pragma mark - 画面

/// App 内托管时才有 VZVirtualMachine；拿到 framebuffer 就把终端让位给画面。
- (void)prepareDisplayIfPossible {
	if (self.displayView != nil) {
		return;
	}
	VFLMachineSession *session = [[VFLHostService shared] sessionNamed:self.vmName];
	id machine = session.virtualMachine;
	if (machine == nil) {
		return;
	}
	VFLDisplayView *display = [[VFLDisplayView alloc] initWithMachine:machine];
	if (!display.available) {
		return;
	}
	display.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view insertSubview:display aboveSubview:self.terminalView];

	[NSLayoutConstraint activateConstraints:@[
		[display.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:36.0],
		[display.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[display.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[display.bottomAnchor constraintEqualToAnchor:self.keyInputView.topAnchor],
	]];

	self.displayView = display;
	self.displayCount = MAX(self.displayCount, display.displayCount);
	[self setDisplayActive:YES];
	[self rebuildControlMenu];
}

/// 客户机可能还在启动，framebuffer 晚一点才发布；短暂重试几次。
- (void)scheduleDisplayPreparation {
	if (self.displayView != nil || self.displayAttempts >= 6) {
		return;
	}
	self.displayAttempts += 1;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		[weakSelf prepareDisplayIfPossible];
		[weakSelf scheduleDisplayPreparation];
	});
}

- (void)setDisplayActive:(BOOL)active {
	if (self.displayView == nil) {
		return;
	}
	self.displayActive = active;
	self.displayView.hidden = !active;
	self.terminalView.hidden = active;
	[self rebuildControlMenu];
}

- (void)tearDownDisplay {
	[self.displayView cancelAllTouches];
	[self.displayView removeFromSuperview];
	self.displayView = nil;
	self.displayActive = NO;
	self.displayAttempts = 0;
	self.terminalView.hidden = NO;
}

- (void)focusKeyboard {
	[self.keyInputView focus];
}

- (void)toggleSoftwareKeyboard {
	if (self.keyInputView.isSoftKeyboardVisible) {
		[self.keyInputView hideSoftKeyboard];
	} else {
		[self.keyInputView showSoftKeyboard];
	}
}

#pragma mark - HUD

- (void)updateHUD:(NSString *)message {
	NSString *stateText = @"未知";
	if ([self.state isEqualToString:@"running"]) {
		stateText = @"运行中";
	} else if ([self.state isEqualToString:@"starting"]) {
		stateText = @"启动中";
	} else if ([self.state isEqualToString:@"stopping"]) {
		stateText = @"关机中";
	} else if ([self.state isEqualToString:@"stopped"]) {
		stateText = @"已停止";
	} else if ([self.state isEqualToString:@"error"]) {
		stateText = @"出错";
	}
	NSString *text = [NSString stringWithFormat:@"%@ · %@ · 显示 %lu/%lu",
					  self.vmName,
					  self.connected ? stateText : @"未连接",
					  (unsigned long)self.currentDisplay,
					  (unsigned long)self.displayCount];
	if (message.length > 0) {
		text = [text stringByAppendingFormat:@"\n%@", message];
	}
	self.hudLabel.text = text;
}

#pragma mark - 控制条

- (void)rebuildControlMenu {
	self.controlBar.menu = [self buildControlMenu];
}

- (UIMenu *)buildControlMenu {
	__weak typeof(self) weakSelf = self;

	UIAction *back = [UIAction actionWithTitle:@"回到虚拟机详情"
										image:[UIImage systemImageNamed:@"chevron.left"]
								   identifier:nil
									  handler:^(__kindof UIAction *action) {
		[weakSelf exitConsole];
	}];

	NSMutableArray<UIAction *> *displayActions = [NSMutableArray array];
	for (NSUInteger index = 0; index < self.displayCount; index++) {
		NSUInteger display = index + 1;
		UIAction *action = [UIAction actionWithTitle:[NSString stringWithFormat:@"显示 %lu", (unsigned long)display]
											  image:nil
										 identifier:nil
											handler:^(__kindof UIAction *selected) {
			weakSelf.currentDisplay = display;
			weakSelf.displayView.displayIndex = display - 1;
			[weakSelf setDisplayActive:YES];
			[weakSelf updateHUD:nil];
			[weakSelf rebuildControlMenu];
		}];
		action.state = self.currentDisplay == display ? UIMenuElementStateOn : UIMenuElementStateOff;
		[displayActions addObject:action];
	}

	NSMutableArray<UIMenu *> *heavyMenus = [NSMutableArray array];
	[heavyMenus addObject:[UIMenu menuWithTitle:@"切换显示设备" children:displayActions]];

	UIAction *addDisplay = nil;
	if (self.displayCount < 4) {
		addDisplay = [UIAction actionWithTitle:@"添加显示设备"
										image:[UIImage systemImageNamed:@"plus"]
								   identifier:nil
									  handler:^(__kindof UIAction *action) {
			[weakSelf addDisplayDevice];
		}];
	}

	UIAction *ctrlC = [UIAction actionWithTitle:@"发送 Ctrl-C"
										 image:nil
									identifier:nil
									   handler:^(__kindof UIAction *action) {
		[weakSelf.client sendConsoleInput:[NSData dataWithBytes:(const uint8_t[]){ 0x03 } length:1]];
	}];

	UIAction *keyboard = [UIAction actionWithTitle:@"软件键盘"
											image:[UIImage systemImageNamed:@"keyboard"]
									   identifier:nil
										  handler:^(__kindof UIAction *action) {
		[weakSelf toggleSoftwareKeyboard];
	}];

	NSMutableArray<UIAction *> *cornerActions = [NSMutableArray array];
	NSArray<NSString *> *cornerTitles = @[ @"左上", @"右上", @"左下", @"右下" ];
	for (NSUInteger index = 0; index < cornerTitles.count; index++) {
		VFLControlBarCorner corner = (VFLControlBarCorner)index;
		UIAction *action = [UIAction actionWithTitle:cornerTitles[index]
											  image:nil
										 identifier:nil
											handler:^(__kindof UIAction *selected) {
			weakSelf.controlBar.corner = corner;
			[weakSelf rebuildControlMenu];
		}];
		action.state = weakSelf.controlBar.corner == corner ? UIMenuElementStateOn : UIMenuElementStateOff;
		[cornerActions addObject:action];
	}

	NSArray<NSNumber *> *opacities = @[ @1.0, @0.7, @0.4 ];
	NSMutableArray<UIAction *> *opacityActions = [NSMutableArray array];
	for (NSNumber *value in opacities) {
		UIAction *action = [UIAction actionWithTitle:
			[NSString stringWithFormat:@"%.0f%%", value.doubleValue * 100.0]
											  image:nil
										 identifier:nil
											handler:^(__kindof UIAction *selected) {
			weakSelf.controlBar.barOpacity = value.doubleValue;
			[weakSelf rebuildControlMenu];
		}];
		action.state = fabs(weakSelf.controlBar.barOpacity - value.doubleValue) < 0.01
			? UIMenuElementStateOn : UIMenuElementStateOff;
		[opacityActions addObject:action];
	}

	UIAction *shutdown = [UIAction actionWithTitle:@"关机"
											image:[UIImage systemImageNamed:@"power"]
									   identifier:nil
										  handler:^(__kindof UIAction *action) {
		[weakSelf sendCommand:@"shutdown"];
	}];
	shutdown.attributes = UIMenuElementAttributesDestructive;

	UIAction *kill = [UIAction actionWithTitle:@"强制关机"
										image:[UIImage systemImageNamed:@"bolt.slash"]
								   identifier:nil
									  handler:^(__kindof UIAction *action) {
		[weakSelf confirmKill];
	}];
	kill.attributes = UIMenuElementAttributesDestructive;

	NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
	[children addObject:back];
	if (self.displayView != nil) {
		UIAction *toggle = [UIAction actionWithTitle:self.displayActive ? @"切换到串口控制台" : @"切换到画面"
											  image:[UIImage systemImageNamed:
													 self.displayActive ? @"terminal" : @"display"]
										 identifier:nil
											handler:^(__kindof UIAction *selected) {
			[weakSelf setDisplayActive:!weakSelf.displayActive];
		}];
		[children addObject:toggle];
	}
	[children addObject:ctrlC];
	[children addObject:keyboard];
	[children addObjectsFromArray:heavyMenus];
	if (addDisplay != nil) {
		[children addObject:addDisplay];
	}
	[children addObject:[UIMenu menuWithTitle:@"控制条位置" children:cornerActions]];
	[children addObject:[UIMenu menuWithTitle:@"控制条透明度" children:opacityActions]];
	[children addObject:shutdown];
	[children addObject:kill];
	return [UIMenu menuWithTitle:@"" children:children];
}

- (void)addDisplayDevice {
	VFLVMStore *store = [[VFLVMStore alloc] init];
	VFLVMDefinition *definition = [store definitionNamed:self.vmName];
	if (definition == nil) {
		return;
	}
	NSUInteger next = definition.displayCount + 1;
	if (next > 4) {
		return;
	}
	definition.displayCount = next;
	NSError *error = nil;
	if (![store saveDefinition:definition error:&error]) {
		[self updateHUD:error.localizedDescription ?: @"保存显示设备失败"];
		return;
	}
	self.displayCount = next;
	self.currentDisplay = next;
	[self updateHUD:@"已添加显示设备，重启虚拟机后生效"];
	[self rebuildControlMenu];
}

- (void)sendCommand:(NSString *)command {
	NSString *name = self.vmName;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *error = nil;
		VFLClient *client = [VFLClient connectWithError:&error];
		if (client == nil) {
			return;
		}
		[client sendRequestWithCommand:command vm:name error:&error];
		[client close];
	});
}

- (void)confirmKill {
	UIAlertController *alert =
		[UIAlertController alertControllerWithTitle:@"强制关机"
											message:@"客户机不会有任何收尾，未保存的数据会丢。"
									 preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"强制关机"
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		[weakSelf sendCommand:@"kill"];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"取消"
											  style:UIAlertActionStyleCancel
											handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)exitConsole {
	[self restoreBarsIfNeeded];
	[self.client detach];
	[self.client close];
	self.client = nil;
	if (self.navigationController != nil) {
		[self.navigationController popViewControllerAnimated:YES];
	} else {
		[self dismissViewControllerAnimated:YES completion:nil];
	}
}

@end
