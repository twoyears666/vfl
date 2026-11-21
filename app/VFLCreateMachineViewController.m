// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLCreateMachineViewController.h"

#import <math.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "VFLDistroIcon.h"
#import "VFLISOExtractor.h"
#import "VFLVMDefinition.h"

@interface VFLCreateMachineViewController () <UIDocumentPickerDelegate>

@property (nonatomic, copy) NSString *suggestedName;
@property (nonatomic, copy) NSString *selectedDistro;
@property (nonatomic, strong) NSMutableArray<UIButton *> *distroButtons;
@property (nonatomic, strong) UILabel *distroNameLabel;

@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UISlider *cpuSlider;
@property (nonatomic, strong) UILabel *cpuValueLabel;
@property (nonatomic, strong) UISlider *memorySlider;
@property (nonatomic, strong) UILabel *memoryValueLabel;
@property (nonatomic, strong) UISlider *diskSlider;
@property (nonatomic, strong) UILabel *diskValueLabel;
@property (nonatomic, strong) UITextField *kernelField;
@property (nonatomic, strong) UITextField *initrdField;
@property (nonatomic, copy) NSString *isoPath;
@property (nonatomic, strong) UILabel *isoLabel;

@end

@implementation VFLCreateMachineViewController

- (instancetype)initWithSuggestedName:(NSString *)suggestedName {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_suggestedName = [suggestedName copy];
		_selectedDistro = @"linux";
		_distroButtons = [NSMutableArray array];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = @"新建虚拟机";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.navigationItem.leftBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
													  target:self
													  action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
													  target:self
													  action:@selector(createTapped)];

	UIScrollView *scrollView = [[UIScrollView alloc] init];
	scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	scrollView.alwaysBounceVertical = YES;
	scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	[self.view addSubview:scrollView];

	UIStackView *stackView = [[UIStackView alloc] init];
	stackView.translatesAutoresizingMaskIntoConstraints = NO;
	stackView.axis = UILayoutConstraintAxisVertical;
	stackView.spacing = 16.0;
	[scrollView addSubview:stackView];

	[NSLayoutConstraint activateConstraints:@[
		[scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[stackView.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:16.0],
		[stackView.leadingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.leadingAnchor
											   constant:16.0],
		[stackView.trailingAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.trailingAnchor
												constant:-16.0],
		[stackView.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor
											   constant:-24.0],
	]];

	[stackView addArrangedSubview:[self distroCard]];
	[stackView addArrangedSubview:[self basicInfoCard]];
	[stackView addArrangedSubview:[self hardwareCard]];
	[stackView addArrangedSubview:[self storageCard]];
	[stackView addArrangedSubview:[self systemCard]];
	[stackView addArrangedSubview:[self isoCard]];

	[self updateDistroSelection];
	[self updateDoneState];
}

#pragma mark - 卡片

- (UIView *)distroCard {
	UIStackView *iconRow = [[UIStackView alloc] init];
	iconRow.axis = UILayoutConstraintAxisHorizontal;
	iconRow.spacing = 12.0;
	iconRow.distribution = UIStackViewDistributionFillEqually;
	iconRow.alignment = UIStackViewAlignmentCenter;

	NSArray<NSString *> *identifiers = [VFLDistroIcon allIdentifiers];
	for (NSUInteger index = 0; index < identifiers.count; index++) {
		NSString *identifier = identifiers[index];
		UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
		button.tag = (NSInteger)index;
		button.layer.cornerRadius = 14.0;
		button.layer.borderWidth = 2.0;
		button.layer.borderColor = UIColor.clearColor.CGColor;
		button.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.10];
		button.tintColor = UIColor.systemBlueColor;
		[button setImage:[VFLDistroIcon templateThumbnailForIdentifier:identifier size:32.0]
				forState:UIControlStateNormal];
		[button.heightAnchor constraintEqualToConstant:52.0].active = YES;
		[button addTarget:self action:@selector(distroTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.distroButtons addObject:button];
		[iconRow addArrangedSubview:button];
	}

	self.distroNameLabel = [[UILabel alloc] init];
	self.distroNameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	self.distroNameLabel.textColor = UIColor.secondaryLabelColor;
	self.distroNameLabel.textAlignment = NSTextAlignmentCenter;

	UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[ iconRow, self.distroNameLabel ]];
	column.axis = UILayoutConstraintAxisVertical;
	column.spacing = 10.0;

	return [self cardWithTitle:@"发行版图标" rows:@[ column ]];
}

- (UIView *)basicInfoCard {
	self.nameField = [[UITextField alloc] init];
	self.nameField.text = self.suggestedName;
	self.nameField.textAlignment = NSTextAlignmentRight;
	self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
	self.nameField.returnKeyType = UIReturnKeyDone;
	self.nameField.autocorrectionType = UITextAutocorrectionTypeNo;
	self.nameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	[self.nameField addTarget:self action:@selector(nameFieldChanged:)
			 forControlEvents:UIControlEventEditingChanged];

	return [self cardWithTitle:@"基本信息" rows:@[
		[self rowWithTitle:@"名称" control:self.nameField],
	]];
}

- (UIView *)hardwareCard {
	self.cpuValueLabel = [self valueLabelWithText:@"4 核"];
	self.cpuSlider = [self sliderWithMin:1.0 max:8.0 value:4.0 action:@selector(cpuSliderChanged:)];

	NSUInteger maximumMemoryMB = [self maximumGuestMemoryMB];
	NSUInteger defaultMemoryMB = MIN((NSUInteger)2048, maximumMemoryMB);
	self.memoryValueLabel = [self valueLabelWithText:
		[NSString stringWithFormat:@"%lu MB", (unsigned long)defaultMemoryMB]];
	self.memorySlider = [self sliderWithMin:512.0
										max:(CGFloat)maximumMemoryMB
									  value:(CGFloat)defaultMemoryMB
									 action:@selector(memorySliderChanged:)];

	return [self cardWithTitle:@"硬件" rows:@[
		[self blockRowWithTitle:@"CPU 核心数" slider:self.cpuSlider valueLabel:self.cpuValueLabel],
		[self blockRowWithTitle:@"内存" slider:self.memorySlider valueLabel:self.memoryValueLabel],
	]];
}

- (UIView *)storageCard {
	self.diskValueLabel = [self valueLabelWithText:@"16 GB"];
	self.diskSlider = [self sliderWithMin:4.0 max:64.0 value:16.0 action:@selector(diskSliderChanged:)];

	UILabel *note = [[UILabel alloc] init];
	note.text = @"这是系统盘容量；磁盘是稀疏文件，创建后可在详情页添加更多磁盘";
	note.numberOfLines = 0;
	note.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	note.textColor = UIColor.secondaryLabelColor;

	return [self cardWithTitle:@"存储" rows:@[
		[self blockRowWithTitle:@"系统盘容量" slider:self.diskSlider valueLabel:self.diskValueLabel],
		note,
	]];
}

- (UIView *)systemCard {
	self.kernelField = [self textFieldWithPlaceholder:@"vmlinuz 的绝对路径"];
	self.kernelField.keyboardType = UIKeyboardTypeURL;
	[self.kernelField addTarget:self action:@selector(pathFieldChanged:)
			   forControlEvents:UIControlEventEditingChanged];

	self.initrdField = [self textFieldWithPlaceholder:@"可选"];
	self.initrdField.keyboardType = UIKeyboardTypeURL;

	UILabel *note = [[UILabel alloc] init];
	note.text = @"内核与 initrd 用设备上的绝对路径，例如 "
				@"/var/jb/var/mobile/Library/VFL/kernels/vmlinuz";
	note.numberOfLines = 0;
	note.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	note.textColor = UIColor.secondaryLabelColor;

	return [self cardWithTitle:@"系统" rows:@[
		[self rowWithTitle:@"内核" control:self.kernelField],
		[self rowWithTitle:@"初始内存盘" control:self.initrdField],
		note,
	]];
}

- (UIView *)isoCard {
	UIButton *importButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[importButton setTitle:@"从「文件」导入 ISO 安装镜像" forState:UIControlStateNormal];
	importButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	importButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
	[importButton addTarget:self action:@selector(importIsoTapped) forControlEvents:UIControlEventTouchUpInside];

	self.isoLabel = [[UILabel alloc] init];
	self.isoLabel.text = @"未选择";
	self.isoLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	self.isoLabel.textColor = UIColor.secondaryLabelColor;
	self.isoLabel.numberOfLines = 0;

	UILabel *note = [[UILabel alloc] init];
	note.text = @"ISO 会作为只读盘接到客户机；也可以用内核 + initrd 直接启动。";
	note.numberOfLines = 0;
	note.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	note.textColor = UIColor.secondaryLabelColor;

	return [self cardWithTitle:@"安装镜像" rows:@[ importButton, self.isoLabel, note ]];
}

#pragma mark - 动作

- (void)distroTapped:(UIButton *)sender {
	NSArray<NSString *> *identifiers = [VFLDistroIcon allIdentifiers];
	NSInteger index = sender.tag;
	if (index < 0 || index >= (NSInteger)identifiers.count) {
		return;
	}
	self.selectedDistro = identifiers[(NSUInteger)index];
	[self updateDistroSelection];
}

- (void)updateDistroSelection {
	NSArray<NSString *> *identifiers = [VFLDistroIcon allIdentifiers];
	NSUInteger selectedIndex = [identifiers indexOfObject:self.selectedDistro];
	for (NSUInteger index = 0; index < self.distroButtons.count; index++) {
		UIButton *button = self.distroButtons[index];
		button.layer.borderColor = index == selectedIndex
			? UIColor.systemBlueColor.CGColor : UIColor.clearColor.CGColor;
	}
	self.distroNameLabel.text = [NSString stringWithFormat:@"已选：%@",
								 [VFLDistroIcon displayNameForIdentifier:self.selectedDistro]];
}

- (void)nameFieldChanged:(UITextField *)sender {
	[self updateDoneState];
}

- (void)pathFieldChanged:(UITextField *)sender {
	[self updateDoneState];
}

- (void)cpuSliderChanged:(UISlider *)sender {
	sender.value = roundf(sender.value);
	self.cpuValueLabel.text = [NSString stringWithFormat:@"%lu 核", (unsigned long)sender.value];
}

- (void)memorySliderChanged:(UISlider *)sender {
	sender.value = roundf(sender.value / 512.0) * 512.0;
	self.memoryValueLabel.text = [NSString stringWithFormat:@"%lu MB", (unsigned long)sender.value];
}

- (void)diskSliderChanged:(UISlider *)sender {
	sender.value = roundf(sender.value / 4.0) * 4.0;
	self.diskValueLabel.text = [NSString stringWithFormat:@"%lu GB", (unsigned long)sender.value];
}

- (void)updateDoneState {
	self.navigationItem.rightBarButtonItem.enabled =
		self.nameField.text.length > 0 && self.kernelField.text.length > 0;
}

- (void)importIsoTapped {
	// SDK 没有 UTTypeISO 常量：ISO 的 UTI 是 public.iso9660，再用扩展名兜底。
	UTType *isoType = [UTType typeWithIdentifier:@"public.iso9660"]
		?: [UTType typeWithFilenameExtension:@"iso"];
	NSMutableArray<UTType *> *types = [NSMutableArray array];
	if (isoType != nil) {
		[types addObject:isoType];
	}
	if (UTTypeDiskImage != nil && ![types containsObject:UTTypeDiskImage]) {
		[types addObject:UTTypeDiskImage];
	}
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
		initForOpeningContentTypes:types
						   asCopy:YES];
	picker.delegate = self;
	picker.allowsMultipleSelection = NO;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
	didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	NSURL *sourceURL = urls.firstObject;
	if (sourceURL == nil) {
		return;
	}

	NSString *directory = VFLImagesDirectory();
	[NSFileManager.defaultManager createDirectoryAtPath:directory
						   withIntermediateDirectories:YES
											attributes:nil
												 error:NULL];

	NSString *fileName = sourceURL.lastPathComponent;
	if (fileName.length == 0) {
		fileName = @"install.iso";
	}
	NSString *destinationPath = [directory stringByAppendingPathComponent:fileName];
	if ([NSFileManager.defaultManager fileExistsAtPath:destinationPath]) {
		NSString *base = fileName.stringByDeletingPathExtension;
		NSString *extension = fileName.pathExtension;
		NSUInteger suffix = 2;
		do {
			destinationPath = [directory stringByAppendingPathComponent:
				[NSString stringWithFormat:@"%@-%lu.%@", base, (unsigned long)suffix++, extension]];
		} while ([NSFileManager.defaultManager fileExistsAtPath:destinationPath]);
	}

	NSError *error = nil;
	if (![NSFileManager.defaultManager moveItemAtURL:sourceURL
											  toURL:[NSURL fileURLWithPath:destinationPath]
											  error:&error]) {
		[self presentMessage:@"导入镜像失败" detail:error.localizedDescription ?: @"文件拷不进来"];
		return;
	}

	self.isoPath = destinationPath;
	self.isoLabel.text = destinationPath;
	self.isoLabel.textColor = UIColor.labelColor;
	[self extractBootFilesFromISOAtPath:destinationPath];
}

/// 从 ISO 里抽内核 / initrd，成功就自动填进系统卡片，省掉手动找路径。
- (void)extractBootFilesFromISOAtPath:(NSString *)isoPath {
	self.isoLabel.text = [NSString stringWithFormat:@"%@\n正在从镜像提取内核…", isoPath];
	self.isoLabel.textColor = UIColor.secondaryLabelColor;

	NSString *folder = [VFLBootDirectory() stringByAppendingPathComponent:
						isoPath.lastPathComponent.stringByDeletingPathExtension];
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSString *kernel = nil;
		NSString *initrd = nil;
		NSError *error = nil;
		BOOL ok = [VFLISOExtractor extractBootFilesFromISOAtPath:isoPath
												   intoDirectory:folder
														  kernel:&kernel
														  initrd:&initrd
														   error:&error];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (strongSelf == nil) {
				return;
			}
			if (!ok) {
				strongSelf.isoLabel.text = [NSString stringWithFormat:@"%@\n没提取到内核：%@，请手动填写系统路径。",
											isoPath, error.localizedDescription ?: @"未知原因"];
				strongSelf.isoLabel.textColor = UIColor.secondaryLabelColor;
				return;
			}
			strongSelf.kernelField.text = kernel;
			strongSelf.initrdField.text = initrd ?: @"";
			strongSelf.isoLabel.text = [NSString stringWithFormat:@"%@\n已提取：%@", isoPath,
										kernel.lastPathComponent];
			strongSelf.isoLabel.textColor = UIColor.labelColor;
			[strongSelf updateDoneState];
		});
	});
}

- (void)cancelTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 保存

- (void)createTapped {
	NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:
					  NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *kernel = [self.kernelField.text stringByTrimmingCharactersInSet:
						NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (name.length == 0 || kernel.length == 0) {
		return;
	}

	VFLVMStore *store = [[VFLVMStore alloc] init];
	if ([store definitionNamed:name] != nil) {
		[self presentMessage:@"名字重复" detail:[NSString stringWithFormat:@"%@ 已经存在，换个名字。", name]];
		return;
	}

	[NSFileManager.defaultManager createDirectoryAtPath:VFLDisksDirectory()
						   withIntermediateDirectories:YES
											attributes:nil
												 error:NULL];
	NSString *diskPath = [VFLDisksDirectory() stringByAppendingPathComponent:
						  [name stringByAppendingPathExtension:@"img"]];
	NSError *error = nil;
	if (![VFLVMStore createDiskImageAtPath:diskPath
								 sizeInGB:(unsigned long long)self.diskSlider.value
									error:&error]) {
		[self presentMessage:@"创建磁盘失败" detail:error.localizedDescription ?: @"镜像写不出来"];
		return;
	}

	VFLVMDefinition *definition = [[VFLVMDefinition alloc] init];
	definition.name = name;
	definition.kernelPath = kernel;
	definition.initrdPath = [self.initrdField.text stringByTrimmingCharactersInSet:
							 NSCharacterSet.whitespaceAndNewlineCharacterSet];
	definition.memoryMB = (unsigned long long)self.memorySlider.value;
	definition.cpuCount = (NSUInteger)self.cpuSlider.value;
	definition.distroIdentifier = self.selectedDistro;
	definition.networkEnabled = YES;
	definition.displayCount = 1;
	if (self.isoPath.length > 0) {
		definition.diskPaths = @[ diskPath, self.isoPath ];
		definition.readOnlyDisks = @[ @1 ];
	} else {
		definition.diskPaths = @[ diskPath ];
		definition.readOnlyDisks = @[];
	}

	if (![store saveDefinition:definition error:&error]) {
		[self presentMessage:@"保存定义失败" detail:error.localizedDescription ?: @"JSON 写不进去"];
		return;
	}

	void (^completion)(NSString *) = self.completion;
	[self dismissViewControllerAnimated:YES completion:^{
		if (completion != nil) {
			completion(name);
		}
	}];
}

#pragma mark - 控件构造

- (NSUInteger)maximumGuestMemoryMB {
	unsigned long long physical = NSProcessInfo.processInfo.physicalMemory;
	unsigned long long bytes = physical * 3ULL / 4ULL;
	if (physical > 1024ULL * 1024ULL * 1024ULL) {
		bytes = MIN(bytes, physical - 1024ULL * 1024ULL * 1024ULL);
	}
	return (NSUInteger)MAX(512ULL, bytes / (1024ULL * 1024ULL));
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder {
	UITextField *field = [[UITextField alloc] init];
	field.placeholder = placeholder;
	field.textAlignment = NSTextAlignmentRight;
	field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.returnKeyType = UIReturnKeyDone;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	return field;
}

- (UILabel *)valueLabelWithText:(NSString *)text {
	UILabel *label = [[UILabel alloc] init];
	label.text = text;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	label.textColor = UIColor.secondaryLabelColor;
	label.textAlignment = NSTextAlignmentRight;
	return label;
}

- (UISlider *)sliderWithMin:(CGFloat)minimum max:(CGFloat)maximum value:(CGFloat)value action:(SEL)action {
	UISlider *slider = [[UISlider alloc] init];
	slider.minimumValue = minimum;
	slider.maximumValue = maximum;
	slider.value = value;
	[slider addTarget:self action:action forControlEvents:UIControlEventValueChanged];
	return slider;
}

- (UIView *)rowWithTitle:(NSString *)title control:(UIView *)control {
	UILabel *label = [[UILabel alloc] init];
	label.text = title;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;
	[label setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ label, control ]];
	row.axis = UILayoutConstraintAxisHorizontal;
	row.spacing = 12.0;
	row.alignment = UIStackViewAlignmentCenter;
	[control setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
	return row;
}

- (UIView *)blockRowWithTitle:(NSString *)title slider:(UISlider *)slider valueLabel:(UILabel *)valueLabel {
	UILabel *label = [[UILabel alloc] init];
	label.text = title;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.textColor = UIColor.labelColor;

	UIView *spacer = [[UIView alloc] init];
	[spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

	UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[ label, spacer, valueLabel ]];
	header.axis = UILayoutConstraintAxisHorizontal;
	header.spacing = 12.0;
	header.alignment = UIStackViewAlignmentCenter;

	UIStackView *block = [[UIStackView alloc] initWithArrangedSubviews:@[ header, slider ]];
	block.axis = UILayoutConstraintAxisVertical;
	block.spacing = 6.0;
	return block;
}

- (UIView *)cardWithTitle:(NSString *)title rows:(NSArray<UIView *> *)rows {
	UIView *card = [[UIView alloc] init];
	card.translatesAutoresizingMaskIntoConstraints = NO;
	card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	card.layer.cornerRadius = 14.0;

	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.text = title;
	titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
	titleLabel.textColor = UIColor.labelColor;

	UIStackView *inner = [[UIStackView alloc] init];
	inner.translatesAutoresizingMaskIntoConstraints = NO;
	inner.axis = UILayoutConstraintAxisVertical;
	inner.spacing = 12.0;
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

- (void)presentMessage:(NSString *)title detail:(NSString *)detail {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																  message:detail
														   preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
