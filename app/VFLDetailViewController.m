// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLDetailViewController.h"

#import "VFLClient.h"
#import "VFLConsoleViewController.h"
#import "VFLVMDefinition.h"

@interface VFLDetailViewController ()

@property (nonatomic, copy) NSString *vmName;
@property (nonatomic, copy) NSString *state;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *consoleButton;
@property (nonatomic, strong) UIButton *shutdownButton;
@property (nonatomic, strong) UIButton *killButton;
@property (nonatomic, strong) NSTimer *refreshTimer;

@end

@implementation VFLDetailViewController

- (instancetype)initWithVMName:(NSString *)name {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_vmName = [name copy];
		_state = @"unknown";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.vmName;
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	UIScrollView *scrollView = [[UIScrollView alloc] init];
	scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	scrollView.alwaysBounceVertical = YES;
	[self.view addSubview:scrollView];

	UIStackView *stack = [[UIStackView alloc] init];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 12.0;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[scrollView addSubview:stack];

	self.stateLabel = [[UILabel alloc] init];
	self.stateLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
	self.stateLabel.text = @"读取状态…";

	self.infoLabel = [[UILabel alloc] init];
	self.infoLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
	self.infoLabel.numberOfLines = 0;
	self.infoLabel.textColor = UIColor.secondaryLabelColor;

	self.startButton = [self buttonWithTitle:@"启动" action:@selector(handleStart)];
	self.consoleButton = [self buttonWithTitle:@"进入控制台" action:@selector(handleConsole)];
	self.shutdownButton = [self buttonWithTitle:@"正常关机" action:@selector(handleShutdown)];
	self.killButton = [self buttonWithTitle:@"强制关机" action:@selector(handleKill)];

	for (UIView *view in @[ self.stateLabel, self.infoLabel, self.startButton,
						   self.consoleButton, self.shutdownButton, self.killButton ]) {
		[stack addArrangedSubview:view];
	}
	[stack setCustomSpacing:24.0 afterView:self.infoLabel];

	[NSLayoutConstraint activateConstraints:@[
		[scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:20.0],
		[stack.leadingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.leadingAnchor
											constant:20.0],
		[stack.trailingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.trailingAnchor
											 constant:-20.0],
		[stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor
										   constant:-20.0],
	]];

	[self loadDefinition];
	[self refreshState];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self refreshState];
	[self.refreshTimer invalidate];
	self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
														target:self
													  selector:@selector(refreshState)
													  userInfo:nil
													   repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
	UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
	configuration.title = title;
	configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.configuration = configuration;
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	[button.heightAnchor constraintEqualToConstant:46.0].active = YES;
	return button;
}

#pragma mark - 配置

- (void)loadDefinition {
	VFLVMDefinition *definition = [[[VFLVMStore alloc] init] definitionNamed:self.vmName];
	if (definition == nil) {
		self.infoLabel.text = @"定义文件不见了。";
		return;
	}
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	[lines addObject:[NSString stringWithFormat:@"内核：%@", definition.kernelPath]];
	if (definition.initrdPath.length > 0) {
		[lines addObject:[NSString stringWithFormat:@"initrd：%@", definition.initrdPath]];
	}
	[lines addObject:[NSString stringWithFormat:@"内存：%llu MB · CPU：%lu · 显示：%lu",
					  definition.memoryMB,
					  (unsigned long)definition.cpuCount,
					  (unsigned long)definition.displayCount]];
	[lines addObject:[NSString stringWithFormat:@"网络：%@", definition.networkEnabled ? @"NAT" : @"关闭"]];
	for (NSString *disk in definition.diskPaths) {
		[lines addObject:[NSString stringWithFormat:@"磁盘：%@", disk]];
	}
	self.infoLabel.text = [lines componentsJoinedByString:@"\n"];
}

#pragma mark - 状态

- (void)refreshState {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSError *error = nil;
		VFLClient *client = [VFLClient connectWithError:&error];
		if (client == nil) {
			[self applyState:@"unknown" message:error.localizedDescription ?: @"连不上守护进程"];
			return;
		}
		NSDictionary *response = [client sendRequestWithCommand:@"list" vm:nil error:&error];
		if (response == nil || ![response[@"ok"] boolValue]) {
			[self applyState:@"unknown" message:response[@"error"] ?: error.localizedDescription];
			return;
		}
		for (NSDictionary *item in response[@"vms"]) {
			if ([item[@"name"] isEqualToString:self.vmName]) {
				[self applyState:item[@"state"] ?: @"unknown" message:nil];
				return;
			}
		}
		[self applyState:@"unknown" message:@"守护进程里没有这台虚拟机"];
	});
}

- (void)applyState:(NSString *)state message:(NSString *)message {
	dispatch_async(dispatch_get_main_queue(), ^{
		self.state = state;
		NSString *text = [NSString stringWithFormat:@"状态：%@", state];
		if (message.length > 0) {
			text = [text stringByAppendingFormat:@"（%@）", message];
		}
		self.stateLabel.text = text;
		self.stateLabel.textColor = [state isEqualToString:@"running"]
			? UIColor.systemGreenColor : UIColor.labelColor;

		BOOL running = [state isEqualToString:@"running"] || [state isEqualToString:@"starting"];
		BOOL stopped = [state isEqualToString:@"stopped"] || [state isEqualToString:@"error"]
			|| [state isEqualToString:@"unknown"];
		self.startButton.enabled = stopped;
		self.shutdownButton.enabled = running;
		self.killButton.enabled = running;
	});
}

#pragma mark - 命令

- (void)sendCommand:(NSString *)command {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *error = nil;
		VFLClient *client = [VFLClient connectWithError:&error];
		if (client == nil) {
			[self presentError:error.localizedDescription ?: @"连不上守护进程"];
			return;
		}
		NSDictionary *response = [client sendRequestWithCommand:command
															 vm:self.vmName
														  error:&error];
		if (response == nil) {
			[self presentError:error.localizedDescription ?: @"命令失败"];
			return;
		}
		if (![response[@"ok"] boolValue]) {
			[self presentError:response[@"error"] ?: @"命令失败"];
			return;
		}
		[self refreshState];
	});
}

- (void)handleStart {
	[self sendCommand:@"start"];
}

- (void)handleShutdown {
	[self sendCommand:@"shutdown"];
}

- (void)handleKill {
	[self sendCommand:@"kill"];
}

- (void)handleConsole {
	VFLConsoleViewController *console =
		[[VFLConsoleViewController alloc] initWithVMName:self.vmName];
	[self.navigationController pushViewController:console animated:YES];
}

- (void)presentError:(NSString *)message {
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController *alert =
			[UIAlertController alertControllerWithTitle:nil
												message:message
										 preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"好"
												  style:UIAlertActionStyleDefault
												handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
	});
}

@end
