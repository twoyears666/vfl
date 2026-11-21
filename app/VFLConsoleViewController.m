// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLConsoleViewController.h"

#import "VFLClient.h"
#import "VFLTerminalEmulator.h"
#import "VFLTerminalView.h"
#import "VFLVMDefinition.h"

#pragma mark - 硬件键盘输入

/// 不可见的 UIKeyInput：负责接硬件键盘，并在需要时切换出系统软键盘。
/// 没有它，iPad 上的硬件键盘按键根本不会进到客户机串口。
@interface VFLKeyInputView : UIView <UIKeyInput>

@property (nonatomic, copy) void (^textHandler)(NSString *text);
@property (nonatomic, copy) void (^deleteHandler)(void);
@property (nonatomic, copy) void (^commandHandler)(NSString *input);
/// NO 时 inputView 返回空视图（不弹软键盘），YES 时交还系统键盘。
@property (nonatomic, assign) BOOL showsSoftwareKeyboard;

- (void)handleUp;
- (void)handleDown;
- (void)handleLeft;
- (void)handleRight;
- (void)handleEscape;
- (void)handleTab;

@end

@implementation VFLKeyInputView

- (BOOL)canBecomeFirstResponder {
	return YES;
}

/// 恒为 YES：这样退格键一定会走 deleteBackward，而不是被当成「无可删除内容」。
- (BOOL)hasText {
	return YES;
}

- (void)insertText:(NSString *)text {
	if (self.textHandler != nil) {
		self.textHandler(text);
	}
}

- (void)deleteBackward {
	if (self.deleteHandler != nil) {
		self.deleteHandler();
	}
}

- (UIView *)inputView {
	if (self.showsSoftwareKeyboard) {
		return nil;
	}
	static UIView *emptyView = nil;
	if (emptyView == nil) {
		emptyView = [[UIView alloc] initWithFrame:CGRectZero];
	}
	return emptyView;
}

- (NSArray<UIKeyCommand *> *)keyCommands {
	UIKeyCommand *up = [UIKeyCommand keyCommandWithInput:UIKeyInputUpArrow
										  modifierFlags:0
												 action:@selector(handleUp)];
	UIKeyCommand *down = [UIKeyCommand keyCommandWithInput:UIKeyInputDownArrow
											modifierFlags:0
												   action:@selector(handleDown)];
	UIKeyCommand *left = [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow
											modifierFlags:0
												   action:@selector(handleLeft)];
	UIKeyCommand *right = [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow
											 modifierFlags:0
													action:@selector(handleRight)];
	UIKeyCommand *escape = [UIKeyCommand keyCommandWithInput:UIKeyInputEscape
											  modifierFlags:0
													 action:@selector(handleEscape)];
	UIKeyCommand *tab = [UIKeyCommand keyCommandWithInput:@"\t"
										   modifierFlags:0
												  action:@selector(handleTab)];
	for (UIKeyCommand *command in @[ up, down, left, right, escape, tab ]) {
		command.wantsPriorityOverSystemBehavior = YES;
	}
	return @[ up, down, left, right, escape, tab ];
}

- (void)forwardCommand:(NSString *)input {
	if (self.commandHandler != nil) {
		self.commandHandler(input);
	}
}

- (void)handleUp {
	[self forwardCommand:UIKeyInputUpArrow];
}

- (void)handleDown {
	[self forwardCommand:UIKeyInputDownArrow];
}

- (void)handleLeft {
	[self forwardCommand:UIKeyInputLeftArrow];
}

- (void)handleRight {
	[self forwardCommand:UIKeyInputRightArrow];
}

- (void)handleEscape {
	[self forwardCommand:UIKeyInputEscape];
}

- (void)handleTab {
	[self forwardCommand:@"\t"];
}

@end

#pragma mark - 控制台

@interface VFLConsoleViewController ()

@property (nonatomic, copy) NSString *vmName;
@property (nonatomic, strong) VFLClient *client;
@property (nonatomic, strong) VFLTerminalEmulator *emulator;
@property (nonatomic, strong) VFLTerminalView *terminalView;
@property (nonatomic, strong) UIView *displayContainer;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) VFLKeyInputView *keyInput;
@property (nonatomic, strong) UIButton *ctrlButton;
@property (nonatomic, strong) UIButton *keyboardButton;
@property (nonatomic, strong) NSMutableData *pendingOutput;
@property (nonatomic, strong) NSLock *pendingLock;
@property (nonatomic, strong) NSTimer *drainTimer;
@property (nonatomic, copy) NSString *state;
@property (nonatomic, assign) BOOL ctrlSticky;
@property (nonatomic, assign) BOOL softwareKeyboard;
@property (nonatomic, assign) NSUInteger displayCount;
@property (nonatomic, assign) NSUInteger currentDisplay;

- (void)showMenu;
- (void)toggleKeyboard;
- (void)toggleCtrl;
- (void)focusKeyboard;
- (void)sendEscape;
- (void)sendTab;
- (void)sendReturn;
- (void)sendBackspace;
- (void)sendUp;
- (void)sendDown;
- (void)sendLeft;
- (void)sendRight;

@end

@implementation VFLConsoleViewController

- (instancetype)initWithVMName:(NSString *)name {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_vmName = [name copy];
		_pendingOutput = [NSMutableData data];
		_pendingLock = [[NSLock alloc] init];
		_displayCount = 1;
		_currentDisplay = 1;
		_state = @"unknown";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.vmName;
	self.view.backgroundColor = UIColor.blackColor;
	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithTitle:@"•••"
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(showMenu)];

	self.displayContainer = [[UIView alloc] init];
	self.displayContainer.translatesAutoresizingMaskIntoConstraints = NO;
	self.displayContainer.backgroundColor = UIColor.blackColor;
	[self.view addSubview:self.displayContainer];

	self.terminalView = [[VFLTerminalView alloc] initWithFrame:CGRectZero];
	self.terminalView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.displayContainer addSubview:self.terminalView];

	self.placeholderLabel = [[UILabel alloc] init];
	self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.placeholderLabel.numberOfLines = 0;
	self.placeholderLabel.textAlignment = NSTextAlignmentCenter;
	self.placeholderLabel.textColor = UIColor.lightGrayColor;
	self.placeholderLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	self.placeholderLabel.hidden = YES;
	[self.displayContainer addSubview:self.placeholderLabel];

	UITapGestureRecognizer *tap =
		[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusKeyboard)];
	[self.displayContainer addGestureRecognizer:tap];

	UIView *bottomBar = [[UIView alloc] init];
	bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
	bottomBar.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
	[self.view addSubview:bottomBar];

	UIScrollView *barScroll = [[UIScrollView alloc] init];
	barScroll.translatesAutoresizingMaskIntoConstraints = NO;
	barScroll.showsHorizontalScrollIndicator = NO;
	[bottomBar addSubview:barScroll];

	UIStackView *barStack = [[UIStackView alloc] init];
	barStack.translatesAutoresizingMaskIntoConstraints = NO;
	barStack.axis = UILayoutConstraintAxisHorizontal;
	barStack.spacing = 6.0;
	barStack.alignment = UIStackViewAlignmentCenter;
	[barScroll addSubview:barStack];

	self.ctrlButton = [self keyButton:@"ctrl" action:@selector(toggleCtrl)];
	self.keyboardButton = [self keyButton:@"⌨" action:@selector(toggleKeyboard)];

	NSArray<UIView *> *buttons = @[
		[self keyButton:@"esc" action:@selector(sendEscape)],
		[self keyButton:@"tab" action:@selector(sendTab)],
		self.ctrlButton,
		[self keyButton:@"↑" action:@selector(sendUp)],
		[self keyButton:@"↓" action:@selector(sendDown)],
		[self keyButton:@"←" action:@selector(sendLeft)],
		[self keyButton:@"→" action:@selector(sendRight)],
		[self keyButton:@"⌫" action:@selector(sendBackspace)],
		[self keyButton:@"⏎" action:@selector(sendReturn)],
		self.keyboardButton,
		[self keyButton:@"•••" action:@selector(showMenu)],
	];
	for (UIView *button in buttons) {
		[barStack addArrangedSubview:button];
	}

	self.keyInput = [[VFLKeyInputView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1.0, 1.0)];
	self.keyInput.alpha = 0.02;
	[self.view addSubview:self.keyInput];
	__weak typeof(self) weakSelf = self;
	self.keyInput.textHandler = ^(NSString *text) {
		[weakSelf sendText:text];
	};
	self.keyInput.deleteHandler = ^{
		[weakSelf sendBytes:(const uint8_t[]){ 0x7F } length:1];
	};
	self.keyInput.commandHandler = ^(NSString *input) {
		[weakSelf handleKeyCommand:input];
	};

	[NSLayoutConstraint activateConstraints:@[
		[self.displayContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.displayContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.displayContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.displayContainer.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor],

		[self.terminalView.topAnchor constraintEqualToAnchor:self.displayContainer.topAnchor],
		[self.terminalView.leadingAnchor constraintEqualToAnchor:self.displayContainer.leadingAnchor],
		[self.terminalView.trailingAnchor constraintEqualToAnchor:self.displayContainer.trailingAnchor],
		[self.terminalView.bottomAnchor constraintEqualToAnchor:self.displayContainer.bottomAnchor],

		[self.placeholderLabel.centerYAnchor constraintEqualToAnchor:self.displayContainer.centerYAnchor],
		[self.placeholderLabel.leadingAnchor constraintEqualToAnchor:self.displayContainer.leadingAnchor
															 constant:32.0],
		[self.placeholderLabel.trailingAnchor constraintEqualToAnchor:self.displayContainer.trailingAnchor
															  constant:-32.0],

		[bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[bottomBar.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
		[bottomBar.heightAnchor constraintEqualToConstant:56.0],

		[barScroll.topAnchor constraintEqualToAnchor:bottomBar.topAnchor],
		[barScroll.bottomAnchor constraintEqualToAnchor:bottomBar.bottomAnchor],
		[barScroll.leadingAnchor constraintEqualToAnchor:bottomBar.leadingAnchor],
		[barScroll.trailingAnchor constraintEqualToAnchor:bottomBar.trailingAnchor],

		[barStack.centerYAnchor constraintEqualToAnchor:barScroll.frameLayoutGuide.centerYAnchor],
		[barStack.leadingAnchor constraintEqualToAnchor:barScroll.contentLayoutGuide.leadingAnchor
											   constant:12.0],
		[barStack.trailingAnchor constraintEqualToAnchor:barScroll.contentLayoutGuide.trailingAnchor
												constant:-12.0],
		[barStack.heightAnchor constraintEqualToAnchor:barScroll.frameLayoutGuide.heightAnchor],
	]];
}

- (UIButton *)keyButton:(NSString *)title action:(SEL)action {
	UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
	configuration.title = title;
	configuration.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 10.0, 6.0, 10.0);
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.configuration = configuration;
	button.tintColor = UIColor.whiteColor;
	button.backgroundColor = [UIColor colorWithWhite:0.20 alpha:1.0];
	button.layer.cornerRadius = 6.0;
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	[button.heightAnchor constraintEqualToConstant:34.0].active = YES;
	return button;
}

#pragma mark - 连接

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self connect];
}

- (void)dealloc {
	[_drainTimer invalidate];
	[_client close];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self.keyInput becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self disconnect];
}

- (void)connect {
	[self disconnect];

	NSError *error = nil;
	VFLClient *client = [VFLClient connectWithError:&error];
	if (client == nil) {
		[self setPrompt:[NSString stringWithFormat:@"连不上守护进程：%@",
						 error.localizedDescription ?: @"未知错误"]];
		return;
	}
	__weak typeof(self) weakSelf = self;
	client.eventHandler = ^(NSDictionary *event) {
		[weakSelf handleEvent:event];
	};
	if (![client enterControlModeWithVM:self.vmName error:&error]) {
		[self setPrompt:error.localizedDescription ?: @"无法进入控制台"];
		return;
	}
	self.client = client;
	self.emulator = [[VFLTerminalEmulator alloc] init];
	self.terminalView.emulator = self.emulator;

	[self loadDisplayCount];
	[self updateDisplayPresentation];
	[self setPrompt:[NSString stringWithFormat:@"%@ · 控制台", client.lastState]];

	// 串口数据可能一次来很多块，攒到下一帧再喂给模拟器，渲染不会被 I/O 拖住。
	__weak typeof(self) weakSelf2 = self;
	self.drainTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
													  repeats:YES
														block:^(NSTimer *timer) {
		[weakSelf2 drainPendingOutput];
	}];
	[self.keyInput becomeFirstResponder];
}

- (void)disconnect {
	[self.drainTimer invalidate];
	self.drainTimer = nil;
	[self.client detach];
	[self.client close];
	self.client = nil;
	[self.pendingLock lock];
	[self.pendingOutput setLength:0];
	[self.pendingLock unlock];
}

- (void)drainPendingOutput {
	NSData *data = nil;
	[self.pendingLock lock];
	if (self.pendingOutput.length > 0) {
		data = [self.pendingOutput copy];
		[self.pendingOutput setLength:0];
	}
	[self.pendingLock unlock];
	if (data.length > 0) {
		[self.emulator feed:data];
	}
}

- (void)handleEvent:(NSDictionary *)event {
	NSString *kind = event[@"event"];
	if ([kind isEqualToString:@"console"]) {
		NSString *encoded = event[@"data"];
		NSData *payload = encoded != nil
			? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
		if (payload.length == 0) {
			return;
		}
		// 回调在客户端线程上：只入队，绝不在这里碰 UIKit。
		[self.pendingLock lock];
		[self.pendingOutput appendData:payload];
		[self.pendingLock unlock];
		return;
	}
	if ([kind isEqualToString:@"state"]) {
		NSString *state = event[@"state"] ?: @"unknown";
		NSString *message = event[@"message"] ?: @"";
		dispatch_async(dispatch_get_main_queue(), ^{
			self.state = state;
			NSString *prompt = message.length > 0
				? [NSString stringWithFormat:@"%@ · %@", state, message]
				: [NSString stringWithFormat:@"%@ · 控制台", state];
			[self setPrompt:prompt];
		});
	}
}

- (void)setPrompt:(NSString *)prompt {
	self.navigationItem.prompt = prompt;
}

#pragma mark - 输入

- (void)sendBytes:(const uint8_t *)bytes length:(NSUInteger)length {
	if (self.client == nil || length == 0) {
		return;
	}
	[self.client sendConsoleInput:[NSData dataWithBytes:bytes length:length]];
}

- (void)sendText:(NSString *)text {
	if (text.length == 0 || self.client == nil) {
		return;
	}
	if (self.ctrlSticky) {
		unichar character = [text characterAtIndex:0];
		if (character >= 'a' && character <= 'z') {
			character = (unichar)(character - 'a' + 1);
		} else if (character >= 'A' && character <= 'Z') {
			character = (unichar)(character - 'A' + 1);
		} else if (character == ' ') {
			character = 0;
		}
		uint8_t byte = (uint8_t)(character & 0xFF);
		[self sendBytes:&byte length:1];
		self.ctrlSticky = NO;
		[self updateCtrlButton];
		return;
	}
	// 串口控制台认 CR 作为回车，软键盘给的是 LF。
	NSString *normalized = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
	[self.client sendConsoleInput:[normalized dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)handleKeyCommand:(NSString *)input {
	if ([input isEqualToString:UIKeyInputUpArrow]) {
		[self sendUp];
	} else if ([input isEqualToString:UIKeyInputDownArrow]) {
		[self sendDown];
	} else if ([input isEqualToString:UIKeyInputLeftArrow]) {
		[self sendLeft];
	} else if ([input isEqualToString:UIKeyInputRightArrow]) {
		[self sendRight];
	} else if ([input isEqualToString:UIKeyInputEscape]) {
		[self sendEscape];
	} else if ([input isEqualToString:@"\t"]) {
		[self sendTab];
	}
}

- (void)toggleCtrl {
	self.ctrlSticky = !self.ctrlSticky;
	[self updateCtrlButton];
}

- (void)updateCtrlButton {
	self.ctrlButton.backgroundColor = self.ctrlSticky
		? UIColor.systemBlueColor : [UIColor colorWithWhite:0.20 alpha:1.0];
}

- (void)toggleKeyboard {
	self.softwareKeyboard = !self.softwareKeyboard;
	self.keyInput.showsSoftwareKeyboard = self.softwareKeyboard;
	[self.keyInput reloadInputViews];
	[self.keyInput becomeFirstResponder];
	self.keyboardButton.backgroundColor = self.softwareKeyboard
		? UIColor.systemBlueColor : [UIColor colorWithWhite:0.20 alpha:1.0];
}

- (void)focusKeyboard {
	[self.keyInput becomeFirstResponder];
}

- (void)sendEscape {
	[self sendBytes:(const uint8_t[]){ 0x1B } length:1];
}

- (void)sendTab {
	[self sendBytes:(const uint8_t[]){ 0x09 } length:1];
}

- (void)sendReturn {
	[self sendBytes:(const uint8_t[]){ 0x0D } length:1];
}

- (void)sendBackspace {
	[self sendBytes:(const uint8_t[]){ 0x7F } length:1];
}

- (void)sendUp {
	[self sendBytes:(const uint8_t[]){ 0x1B, '[', 'A' } length:3];
}

- (void)sendDown {
	[self sendBytes:(const uint8_t[]){ 0x1B, '[', 'B' } length:3];
}

- (void)sendRight {
	[self sendBytes:(const uint8_t[]){ 0x1B, '[', 'C' } length:3];
}

- (void)sendLeft {
	[self sendBytes:(const uint8_t[]){ 0x1B, '[', 'D' } length:3];
}

#pragma mark - 显示设备

- (void)loadDisplayCount {
	VFLVMDefinition *definition = [[[VFLVMStore alloc] init] definitionNamed:self.vmName];
	self.displayCount = MAX((NSUInteger)1, definition.displayCount);
	self.currentDisplay = MIN(MAX((NSUInteger)1, self.currentDisplay), self.displayCount);
}

- (void)updateDisplayPresentation {
	BOOL consoleVisible = (self.currentDisplay == 1);
	self.terminalView.hidden = !consoleVisible;
	self.placeholderLabel.hidden = consoleVisible;
	if (!consoleVisible) {
		self.placeholderLabel.text = [NSString stringWithFormat:
			@"显示 %lu\n\niPadOS 上的 Virtualization.framework 不提供画面输出，"
			@"这个显示设备只作为客户机配置存在。\n串口控制台仍在「显示 1」。",
			(unsigned long)self.currentDisplay];
	}
}

- (void)showDisplayMenu {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"显示设备"
																  message:nil
														   preferredStyle:UIAlertControllerStyleActionSheet];
	for (NSUInteger index = 1; index <= self.displayCount; index++) {
		NSString *title = index == 1
			? [NSString stringWithFormat:@"%@显示 1（串口控制台）",
			   self.currentDisplay == 1 ? @"✓ " : @""]
			: [NSString stringWithFormat:@"%@显示 %lu", self.currentDisplay == index ? @"✓ " : @"",
			   (unsigned long)index];
		[sheet addAction:[UIAlertAction actionWithTitle:title
												  style:UIAlertActionStyleDefault
												handler:^(UIAlertAction *action) {
			self.currentDisplay = index;
			[self updateDisplayPresentation];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:@"添加显示设备"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		[self addDisplay];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"取消"
											  style:UIAlertActionStyleCancel
											handler:nil]];

	sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)addDisplay {
	VFLVMStore *store = [[VFLVMStore alloc] init];
	VFLVMDefinition *definition = [store definitionNamed:self.vmName];
	if (definition == nil) {
		return;
	}
	definition.displayCount += 1;
	[store saveDefinition:definition error:NULL];
	self.displayCount = definition.displayCount;
	self.currentDisplay = definition.displayCount;
	[self updateDisplayPresentation];

	UIAlertController *alert = [UIAlertController
		alertControllerWithTitle:nil
						 message:@"已添加显示设备。新的显示数量会在下次启动虚拟机时生效。"
				  preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"好"
											  style:UIAlertActionStyleDefault
											handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 菜单

- (void)showMenu {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:self.vmName
																  message:nil
														   preferredStyle:UIAlertControllerStyleActionSheet];
	[sheet addAction:[UIAlertAction actionWithTitle:@"显示设备"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		[self showDisplayMenu];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"软键盘"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		[self toggleKeyboard];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"正常关机"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
		[self sendCommand:@"shutdown"];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"强制关机"
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		[self sendCommand:@"kill"];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"断开返回"
											  style:UIAlertActionStyleCancel
											handler:^(UIAlertAction *action) {
		[self.navigationController popViewControllerAnimated:YES];
	}]];
	sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)sendCommand:(NSString *)command {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *error = nil;
		VFLClient *client = [VFLClient connectWithError:&error];
		if (client == nil) {
			return;
		}
		[client sendRequestWithCommand:command vm:self.vmName error:&error];
		[client close];
	});
}

@end
