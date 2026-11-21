// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLDetailViewController.h"

#import <math.h>

#import "VFLClient.h"
#import "VFLDashedPlaceholderView.h"
#import "VFLFullScreenViewController.h"
#import "VFLVMDefinition.h"

@interface VFLDetailViewController ()

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;

@property (nonatomic, strong) VFLVMDefinition *definition;
@property (nonatomic, copy) NSString *state;
@property (nonatomic, copy) NSString *statusMessage;
@property (nonatomic, strong) NSTimer *refreshTimer;

@property (nonatomic, strong) UILabel *cpuValueLabel;
@property (nonatomic, strong) UILabel *memoryValueLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *primaryButton;

@end

@implementation VFLDetailViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.scrollView = [[UIScrollView alloc] init];
	self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	self.scrollView.alwaysBounceVertical = YES;
	self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	[self.view addSubview:self.scrollView];

	self.stackView = [[UIStackView alloc] init];
	self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
	self.stackView.axis = UILayoutConstraintAxisVertical;
	self.stackView.spacing = 16.0;
	[self.scrollView addSubview:self.stackView];

	[NSLayoutConstraint activateConstraints:@[
		[self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.stackView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor
												 constant:16.0],
		[self.stackView.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor
													 constant:16.0],
		[self.stackView.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor
													  constant:-16.0],
		[self.stackView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor
													constant:-24.0],
	]];

	[self rebuildContent];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self refreshState];
	if (self.refreshTimer == nil && self.definition != nil) {
		__weak typeof(self) weakSelf = self;
		self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
														   repeats:YES
															 block:^(NSTimer *timer) {
			[weakSelf refreshState];
		}];
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;
}

- (void)setVmName:(NSString *)vmName {
	_vmName = [vmName copy];
	self.definition = vmName.length > 0
		? [[[VFLVMStore alloc] init] definitionNamed:vmName] : nil;
	self.state = @"stopped";
	self.statusMessage = @"";
	self.title = vmName.length > 0 ? vmName : @"虚拟机";
	if (self.isViewLoaded) {
		[self rebuildContent];
		[self refreshState];
	}
}

#pragma mark - 状态

- (BOOL)isMachineActive {
	return [self.state isEqualToString:@"starting"] || [self.state isEqualToString:@"running"];
}

- (void)refreshState {
	NSString *name = self.vmName;
	if (name.length == 0) {
		return;
	}
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *error = nil;
		VFLClient *client = [VFLClient connectWithError:&error];
		if (client == nil) {
			return;
		}
		NSDictionary *response = [client sendRequestWithCommand:@"list" vm:nil error:&error];
		[client close];
		if (![response[@"ok"] boolValue]) {
			return;
		}
		NSString *state = nil;
		for (NSDictionary *item in response[@"vms"]) {
			if ([item[@"name"] isEqualToString:name]) {
				state = item[@"state"];
				break;
			}
		}
		if (state == nil) {
			return;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			if (![state isEqualToString:self.state]) {
				self.state = state;
				[self rebuildContent];
			}
		});
	});
}

- (NSString *)stateText {
	if ([self.state isEqualToString:@"running"]) {
		return @"运行中";
	}
	if ([self.state isEqualToString:@"starting"]) {
		return @"启动中";
	}
	if ([self.state isEqualToString:@"stopping"]) {
		return @"关机中";
	}
	if ([self.state isEqualToString:@"error"]) {
		return @"出错";
	}
	return @"已停止";
}

#pragma mark - 内容

- (void)rebuildContent {
	for (UIView *view in self.stackView.arrangedSubviews) {
		[self.stackView removeArrangedSubview:view];
		[view removeFromSuperview];
	}

	VFLVMDefinition *definition = self.definition;
	if (definition == nil) {
		UILabel *emptyLabel = [[UILabel alloc] init];
		emptyLabel.text = @"在左侧选择一台虚拟机。";
		emptyLabel.textColor = UIColor.secondaryLabelColor;
		emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
		[self.stackView addArrangedSubview:emptyLabel];
		return;
	}

	if ([self isMachineActive]) {
		[self.stackView addArrangedSubview:[self runningEntryCard]];
	} else {
		VFLDashedPlaceholderView *placeholder = [[VFLDashedPlaceholderView alloc] init];
		placeholder.translatesAutoresizingMaskIntoConstraints = NO;
		placeholder.text = @"点按启动虚拟机\n串口控制台会显示在独立的全屏页面里";
		__weak typeof(self) weakSelf = self;
		placeholder.onTap = ^{
			[weakSelf startTapped];
		};
		[placeholder.heightAnchor constraintEqualToAnchor:placeholder.widthAnchor multiplier:0.75].active = YES;
		[self.stackView addArrangedSubview:placeholder];
	}

	// 基本信息
	[self.stackView addArrangedSubview:[self cardWithTitle:@"基本信息" rows:@[
		[self rowWithTitle:@"名称" control:[self valueLabelWithText:definition.name]],
		[self rowWithTitle:@"状态" control:[self valueLabelWithText:[self stateText]]],
	]]];

	UISegmentedControl *bootModeControl =
		[[UISegmentedControl alloc] initWithItems:@[ @"EFI 固件", @"内核直启" ]];
	bootModeControl.selectedSegmentIndex = definition.bootMode == VFLBootModeKernel ? 1 : 0;
	[bootModeControl addTarget:self
						action:@selector(bootModeChanged:)
			  forControlEvents:UIControlEventValueChanged];

	// 系统
	[self.stackView addArrangedSubview:[self cardWithTitle:@"系统" rows:@[
		[self rowWithTitle:@"启动方式" control:bootModeControl],
		[self rowWithTitle:@"内核" control:[self textFieldWithPlaceholder:@"vmlinuz 路径"
																	text:definition.kernelPath
																  action:@selector(kernelPathChanged:)]],
		[self rowWithTitle:@"初始内存盘" control:[self textFieldWithPlaceholder:@"可选"
																			text:definition.initrdPath
																		  action:@selector(initrdPathChanged:)]],
		[self rowWithTitle:@"客户机架构" control:[self valueLabelWithText:@"arm64"]],
		[self rowWithTitle:@"内核参数" control:[self textFieldWithPlaceholder:@"留空用默认串口参数"
																		text:definition.commandLine
																	  action:@selector(commandLineChanged:)]],
	]]];

	// 硬件
	NSUInteger maximumMemoryMB = [self maximumGuestMemoryMB];
	if (definition.memoryMB > maximumMemoryMB) {
		definition.memoryMB = maximumMemoryMB;
	}
	self.cpuValueLabel = [self valueLabelWithText:
		[NSString stringWithFormat:@"%lu 核", (unsigned long)definition.cpuCount]];
	UISlider *cpuSlider = [self sliderWithMin:1.0
										  max:8.0
										value:(CGFloat)definition.cpuCount
									   action:@selector(cpuSliderChanged:)];

	self.memoryValueLabel = [self valueLabelWithText:
		[NSString stringWithFormat:@"%llu MB", definition.memoryMB]];
	UISlider *memorySlider = [self sliderWithMin:512.0
											 max:(CGFloat)maximumMemoryMB
										   value:(CGFloat)definition.memoryMB
										  action:@selector(memorySliderChanged:)];

	[self.stackView addArrangedSubview:[self cardWithTitle:@"硬件" rows:@[
		[self blockRowWithTitle:@"CPU 核心数" control:cpuSlider valueLabel:self.cpuValueLabel],
		[self blockRowWithTitle:@"内存" control:memorySlider valueLabel:self.memoryValueLabel],
	]]];

	// 存储
	NSMutableArray<UIView *> *storageRows = [NSMutableArray array];
	NSUInteger diskIndex = 0;
	for (NSString *path in definition.diskPaths) {
		BOOL readOnly = [definition.readOnlyDisks containsObject:@(diskIndex)];
		NSString *title = diskIndex == 0 ? @"系统盘" : (readOnly ? @"只读盘" : @"磁盘");
		NSString *value = [NSString stringWithFormat:@"%@ · %@",
						   path.lastPathComponent, [self sizeTextForPath:path]];
		[storageRows addObject:[self rowWithTitle:title control:[self valueLabelWithText:value]]];
		diskIndex++;
	}
	UIButton *addDiskButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[addDiskButton setTitle:@"＋ 添加磁盘" forState:UIControlStateNormal];
	addDiskButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	[addDiskButton addTarget:self action:@selector(addDiskTapped) forControlEvents:UIControlEventTouchUpInside];
	[storageRows addObject:addDiskButton];

	UILabel *diskNote = [[UILabel alloc] init];
	diskNote.text = @"磁盘镜像为稀疏文件；ISO 安装镜像作为只读盘排在其后。";
	diskNote.numberOfLines = 0;
	diskNote.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	diskNote.textColor = UIColor.secondaryLabelColor;
	[storageRows addObject:diskNote];

	[self.stackView addArrangedSubview:[self cardWithTitle:@"存储" rows:storageRows]];

	// 显示
	UIButton *displayButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[displayButton setTitle:[NSString stringWithFormat:@"%lu 台", (unsigned long)definition.displayCount]
				   forState:UIControlStateNormal];
	displayButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	displayButton.showsMenuAsPrimaryAction = YES;
	displayButton.menu = [self displayMenu];

	UILabel *displayNote = [[UILabel alloc] init];
	displayNote.text = @"Virtualization.framework 在 iPadOS 上不提供客户机画面视图，"
					   @"这里只配置客户机的显示设备数量（下次启动生效）。";
	displayNote.numberOfLines = 0;
	displayNote.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	displayNote.textColor = UIColor.secondaryLabelColor;

	[self.stackView addArrangedSubview:[self cardWithTitle:@"显示" rows:@[
		[self rowWithTitle:@"显示设备" control:displayButton],
		displayNote,
	]]];

	// 网络
	UISwitch *network = [[UISwitch alloc] init];
	network.on = definition.networkEnabled;
	[network addTarget:self action:@selector(networkChanged:) forControlEvents:UIControlEventValueChanged];

	[self.stackView addArrangedSubview:[self cardWithTitle:@"网络" rows:@[
		[self rowWithTitle:@"NAT 网络" control:network],
		[self rowWithTitle:@"MAC 地址" control:[self textFieldWithPlaceholder:@"52:54:00:12:34:56"
																		text:definition.macAddress
																	  action:@selector(macAddressChanged:)]],
	]]];

	// 启停
	BOOL active = [self isMachineActive];
	self.primaryButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.primaryButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.primaryButton setTitle:(active ? @"停止虚拟机" : @"启动虚拟机") forState:UIControlStateNormal];
	self.primaryButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
	[self.primaryButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	self.primaryButton.backgroundColor = active ? UIColor.systemRedColor : self.view.tintColor;
	self.primaryButton.layer.cornerRadius = 12.0;
	[self.primaryButton addTarget:self action:@selector(startTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.primaryButton.heightAnchor constraintEqualToConstant:50.0].active = YES;
	[self.stackView addArrangedSubview:self.primaryButton];

	if (active) {
		UIStackView *row = [[UIStackView alloc] init];
		row.axis = UILayoutConstraintAxisHorizontal;
		row.spacing = 12.0;
		row.distribution = UIStackViewDistributionFillEqually;

		UIButton *killButton = [UIButton buttonWithType:UIButtonTypeSystem];
		[killButton setTitle:@"强制关机" forState:UIControlStateNormal];
		[killButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
		[killButton addTarget:self action:@selector(killTapped) forControlEvents:UIControlEventTouchUpInside];

		UIButton *consoleButton = [UIButton buttonWithType:UIButtonTypeSystem];
		[consoleButton setTitle:@"进入控制台" forState:UIControlStateNormal];
		[consoleButton addTarget:self action:@selector(enterConsoleTapped) forControlEvents:UIControlEventTouchUpInside];

		[row addArrangedSubview:killButton];
		[row addArrangedSubview:consoleButton];
		[self.stackView addArrangedSubview:row];
	}

	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.text = self.statusMessage.length > 0 ? self.statusMessage : [self stateText];
	[self.stackView addArrangedSubview:self.statusLabel];
}

#pragma mark - 控件构造

- (UILabel *)valueLabelWithText:(NSString *)text {
	UILabel *label = [[UILabel alloc] init];
	label.text = text;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	label.textColor = UIColor.secondaryLabelColor;
	label.textAlignment = NSTextAlignmentRight;
	[label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
										   forAxis:UILayoutConstraintAxisHorizontal];
	return label;
}

- (UIView *)cardWithTitle:(NSString *)title rows:(NSArray<UIView *> *)rows {
	UIView *card = [[UIView alloc] init];
	card.translatesAutoresizingMaskIntoConstraints = NO;
	card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	card.layer.cornerRadius = 14.0;

	UIStackView *inner = [[UIStackView alloc] init];
	inner.translatesAutoresizingMaskIntoConstraints = NO;
	inner.axis = UILayoutConstraintAxisVertical;
	inner.spacing = 12.0;

	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.text = title;
	titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
	titleLabel.textColor = UIColor.labelColor;
	[inner addArrangedSubview:titleLabel];
	for (UIView *row in rows) {
		[inner addArrangedSubview:row];
	}
	[card addSubview:inner];

	[NSLayoutConstraint activateConstraints:@[
		[inner.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
		[inner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
		[inner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
		[inner.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0],
	]];
	return card;
}

- (UIView *)rowWithTitle:(NSString *)title control:(UIView *)control {
	UIStackView *row = [[UIStackView alloc] init];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = 12.0;

	UILabel *label = [[UILabel alloc] init];
	label.text = title;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;
	[label setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

	[control setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
	[control setContentCompressionResistancePriority:UILayoutPriorityRequired
											 forAxis:UILayoutConstraintAxisHorizontal];

	[row addArrangedSubview:label];
	[row addArrangedSubview:control];
	return row;
}

- (UIView *)blockRowWithTitle:(NSString *)title control:(UIView *)control valueLabel:(UILabel *)valueLabel {
	UIStackView *header = [[UIStackView alloc] init];
	header.axis = UILayoutConstraintAxisHorizontal;
	header.alignment = UIStackViewAlignmentCenter;
	header.spacing = 8.0;

	UILabel *label = [[UILabel alloc] init];
	label.text = title;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;
	[header addArrangedSubview:label];

	UIView *spacer = [[UIView alloc] init];
	[spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
	[header addArrangedSubview:spacer];

	if (valueLabel != nil) {
		[header addArrangedSubview:valueLabel];
	}

	UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[ header, control ]];
	column.axis = UILayoutConstraintAxisVertical;
	column.spacing = 8.0;
	return column;
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder text:(NSString *)text action:(SEL)action {
	UITextField *field = [[UITextField alloc] init];
	field.placeholder = placeholder;
	field.text = text;
	field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	field.textColor = UIColor.secondaryLabelColor;
	field.textAlignment = NSTextAlignmentRight;
	field.borderStyle = UITextBorderStyleNone;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.returnKeyType = UIReturnKeyDone;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	[field addTarget:self action:action forControlEvents:UIControlEventEditingChanged];
	return field;
}

- (UISlider *)sliderWithMin:(CGFloat)minimum max:(CGFloat)maximum value:(CGFloat)value action:(SEL)action {
	UISlider *slider = [[UISlider alloc] init];
	slider.minimumValue = (float)minimum;
	slider.maximumValue = (float)maximum;
	slider.value = (float)value;
	[slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];
	return slider;
}

- (NSUInteger)maximumGuestMemoryMB {
	unsigned long long physical = NSProcessInfo.processInfo.physicalMemory;
	unsigned long long bytes = physical * 3ULL / 4ULL;
	if (physical > 1024ULL * 1024ULL * 1024ULL) {
		bytes = MIN(bytes, physical - 1024ULL * 1024ULL * 1024ULL);
	}
	return (NSUInteger)MAX(512ULL, bytes / (1024ULL * 1024ULL));
}

- (NSString *)sizeTextForPath:(NSString *)path {
	NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
	unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
	if (size == 0) {
		return @"不存在";
	}
	double gigabytes = (double)size / (1024.0 * 1024.0 * 1024.0);
	return [NSString stringWithFormat:@"%.0f GB", MAX(1.0, round(gigabytes))];
}

- (UIMenu *)displayMenu {
	__weak typeof(self) weakSelf = self;
	NSMutableArray<UIAction *> *actions = [NSMutableArray array];
	for (NSUInteger count = 1; count <= 4; count++) {
		UIAction *action = [UIAction actionWithTitle:[NSString stringWithFormat:@"%lu 台", (unsigned long)count]
											  image:nil
										 identifier:nil
											handler:^(__kindof UIAction *selected) {
			weakSelf.definition.displayCount = count;
			[weakSelf saveDefinition];
			[weakSelf rebuildContent];
		}];
		action.state = weakSelf.definition.displayCount == count ? UIMenuElementStateOn : UIMenuElementStateOff;
		[actions addObject:action];
	}
	return [UIMenu menuWithTitle:@"显示设备" children:actions];
}

- (UIView *)runningEntryCard {
	UILabel *status = [[UILabel alloc] init];
	status.text = self.statusMessage.length > 0 ? self.statusMessage : [self stateText];
	status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	status.textColor = UIColor.secondaryLabelColor;
	status.numberOfLines = 0;
	[status setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
											forAxis:UILayoutConstraintAxisHorizontal];

	UIButton *enterButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[enterButton setTitle:@"进入控制台" forState:UIControlStateNormal];
	enterButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	[enterButton addTarget:self action:@selector(enterConsoleTapped) forControlEvents:UIControlEventTouchUpInside];
	[enterButton setContentHuggingPriority:UILayoutPriorityRequired
								   forAxis:UILayoutConstraintAxisHorizontal];

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ status, enterButton ]];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = 12.0;

	return [self cardWithTitle:@"虚拟机运行中" rows:@[ row ]];
}

#pragma mark - 设置变更

- (void)saveDefinition {
	NSError *error = nil;
	if (![[[VFLVMStore alloc] init] saveDefinition:self.definition error:&error]) {
		[self presentMessage:@"保存失败" detail:error.localizedDescription ?: @"定义写不进去"];
	}
}

- (void)bootModeChanged:(UISegmentedControl *)sender {
	self.definition.bootMode = sender.selectedSegmentIndex == 1 ? VFLBootModeKernel : VFLBootModeEFI;
	[self saveDefinition];
}

- (void)kernelPathChanged:(UITextField *)sender {
	self.definition.kernelPath = sender.text;
	[self saveDefinition];
}

- (void)initrdPathChanged:(UITextField *)sender {
	self.definition.initrdPath = sender.text;
	[self saveDefinition];
}

- (void)commandLineChanged:(UITextField *)sender {
	self.definition.commandLine = sender.text;
	[self saveDefinition];
}

- (void)macAddressChanged:(UITextField *)sender {
	self.definition.macAddress = sender.text;
	[self saveDefinition];
}

- (void)networkChanged:(UISwitch *)sender {
	self.definition.networkEnabled = sender.isOn;
	[self saveDefinition];
}

- (void)cpuSliderChanged:(UISlider *)sender {
	NSUInteger cores = (NSUInteger)MAX(1.0, roundf(sender.value));
	sender.value = (float)cores;
	self.definition.cpuCount = cores;
	self.cpuValueLabel.text = [NSString stringWithFormat:@"%lu 核", (unsigned long)cores];
	[self saveDefinition];
}

- (void)memorySliderChanged:(UISlider *)sender {
	unsigned long long megabytes =
		(unsigned long long)(MAX(512.0, roundf(sender.value / 512.0)) * 512.0);
	sender.value = (float)megabytes;
	self.definition.memoryMB = megabytes;
	self.memoryValueLabel.text = [NSString stringWithFormat:@"%llu MB", megabytes];
	[self saveDefinition];
}

- (void)addDiskTapped {
	NSUInteger index = self.definition.diskPaths.count;
	NSString *fileName = [NSString stringWithFormat:@"%@-%lu.img", self.definition.name,
													   (unsigned long)index];
	NSString *path = [VFLDisksDirectory() stringByAppendingPathComponent:fileName];
	NSError *error = nil;
	[NSFileManager.defaultManager createDirectoryAtPath:VFLDisksDirectory()
						   withIntermediateDirectories:YES
											attributes:nil
												 error:NULL];
	if (![VFLVMStore createDiskImageAtPath:path sizeInGB:8 error:&error]) {
		[self presentMessage:@"添加磁盘失败" detail:error.localizedDescription ?: @"镜像创建失败"];
		return;
	}
	self.definition.diskPaths = [self.definition.diskPaths arrayByAddingObject:path];
	[self saveDefinition];
	[self rebuildContent];
}

#pragma mark - 启停

- (void)startTapped {
	if ([self isMachineActive]) {
		[self sendCommand:@"shutdown" successMessage:@"正在请求关机…" completion:nil];
		return;
	}

	// 启动前重新读定义：firstBoot 由服务端在成功启动后置 NO。
	VFLVMDefinition *latest = [[[VFLVMStore alloc] init] definitionNamed:self.vmName] ?: self.definition;
	NSInteger installImageIndex = [self installImageIndexInDefinition:latest];
	if (installImageIndex >= 0 && !latest.firstBoot && latest.bootMode == VFLBootModeEFI) {
		[self confirmRemovingInstallImageAtIndex:installImageIndex definition:latest];
		return;
	}
	[self beginStart];
}

- (void)beginStart {
	NSString *name = self.vmName;
	[self sendCommand:@"start" successMessage:@"正在启动…" completion:^(BOOL ok) {
		if (ok && name.length > 0) {
			[self presentConsoleForVMNamed:name];
		}
	}];
}

/// 第一块盘是系统盘；安装镜像只可能是挂在后面的只读盘。
- (NSInteger)installImageIndexInDefinition:(VFLVMDefinition *)definition {
	NSArray<NSString *> *paths = definition.diskPaths;
	for (NSUInteger index = 1; index < paths.count; index++) {
		if ([paths[index] hasPrefix:VFLImagesDirectory()]) {
			return (NSInteger)index;
		}
	}
	return -1;
}

- (void)confirmRemovingInstallImageAtIndex:(NSInteger)index
								definition:(VFLVMDefinition *)definition {
	if (index < 0 || (NSUInteger)index >= definition.diskPaths.count) {
		return;
	}
	NSString *path = definition.diskPaths[(NSUInteger)index];
	NSString *message = [NSString stringWithFormat:
		@"这台虚拟机已经完成首次启动。若系统已安装好，安装镜像就不再需要了，要删除它吗？\n\n%@\n\n删除后无法恢复；选择「保留」则每次启动都会再问一次。",
		path.lastPathComponent];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"安装已完成？"
																  message:message
														   preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"删除镜像"
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		[weakSelf removeInstallImageAtIndex:index definition:definition];
		[weakSelf beginStart];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"保留"
											  style:UIAlertActionStyleCancel
											handler:^(UIAlertAction *action) {
		[weakSelf beginStart];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)removeInstallImageAtIndex:(NSInteger)index definition:(VFLVMDefinition *)definition {
	if (index < 0 || (NSUInteger)index >= definition.diskPaths.count) {
		return;
	}
	NSString *path = definition.diskPaths[(NSUInteger)index];
	NSMutableArray<NSString *> *paths = [definition.diskPaths mutableCopy];
	[paths removeObjectAtIndex:(NSUInteger)index];

	NSMutableArray<NSNumber *> *readOnly = [NSMutableArray array];
	for (NSNumber *number in definition.readOnlyDisks) {
		NSInteger value = number.integerValue;
		if (value == index) {
			continue;
		}
		if (value > index) {
			value -= 1;
		}
		[readOnly addObject:@(value)];
	}
	definition.diskPaths = paths;
	definition.readOnlyDisks = readOnly;
	self.definition = definition;
	[self saveDefinition];

	// 只删导入目录里的镜像，避免误删用户自己放在别处的盘。
	if ([path hasPrefix:VFLImagesDirectory()]) {
		[NSFileManager.defaultManager removeItemAtPath:path error:NULL];
		// NVRAM 里可能记着「从 ISO 启动」的引导项；删掉后让固件重新枚举，
		// 下次就会落到系统盘的 \EFI\BOOT\BOOTAA64.EFI 上。
		[NSFileManager.defaultManager removeItemAtPath:definition.efiVariableStorePath error:NULL];
	}
	self.statusMessage = @"已删除安装镜像";
	[self rebuildContent];
}

- (void)killTapped {
	[self sendCommand:@"kill" successMessage:@"已强制关机" completion:nil];
}

- (void)enterConsoleTapped {
	if (self.vmName.length > 0) {
		[self presentConsoleForVMNamed:self.vmName];
	}
}

- (void)sendCommand:(NSString *)command
	  successMessage:(NSString *)successMessage
		  completion:(void (^)(BOOL ok))completion {
	NSString *name = self.vmName;
	if (name.length == 0) {
		return;
	}
	self.statusLabel.text = @"正在处理…";
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *error = nil;
		VFLClient *client = [VFLClient connectWithError:&error];
		if (client == nil) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self presentMessage:@"连不上守护进程"
							  detail:@"请确认 VFL 已正确安装并重启过设备。"];
				if (completion != nil) {
					completion(NO);
				}
			});
			return;
		}
		NSDictionary *response = [client sendRequestWithCommand:command vm:name error:&error];
		[client close];
		BOOL ok = [response[@"ok"] boolValue];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!ok) {
				NSString *detail = response[@"error"] ?: error.localizedDescription ?: @"命令失败";
				[self presentMessage:@"操作失败" detail:detail];
				self.statusLabel.text = detail;
			} else {
				self.statusMessage = successMessage;
				self.statusLabel.text = successMessage;
				[self refreshState];
			}
			if (completion != nil) {
				completion(ok);
			}
		});
	});
}

- (void)presentConsoleForVMNamed:(NSString *)name {
	VFLFullScreenViewController *controller =
		[[VFLFullScreenViewController alloc] initWithVMName:name
												displayCount:self.definition.displayCount];
	__weak typeof(self) weakSelf = self;
	controller.dismissHandler = ^{
		[weakSelf refreshState];
	};
	if (self.navigationController != nil) {
		[self.navigationController pushViewController:controller animated:YES];
	} else {
		[self presentViewController:controller animated:YES completion:nil];
	}
}

- (void)presentMessage:(NSString *)title detail:(NSString *)detail {
	if ([self.presentedViewController isKindOfClass:UIAlertController.class]) {
		return;
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																  message:detail
														   preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"知道了"
											  style:UIAlertActionStyleDefault
											handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
