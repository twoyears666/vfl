// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLNewVMViewController.h"

#import <stdlib.h>

#import "VFLVMDefinition.h"

@interface VFLNewVMViewController ()

@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *kernelField;
@property (nonatomic, strong) UITextField *initrdField;
@property (nonatomic, strong) UITextField *diskField;
@property (nonatomic, strong) UITextField *memoryField;
@property (nonatomic, strong) UITextField *cpuField;
@property (nonatomic, strong) UITextField *displayField;
@property (nonatomic, strong) UISwitch *networkSwitch;

@end

@implementation VFLNewVMViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"新建虚拟机";
	self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 52.0;

	self.navigationItem.leftBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
													  target:self
													  action:@selector(handleCancel)];
	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
													  target:self
													  action:@selector(handleSave)];
}

#pragma mark - 表单

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder
							 keyboardType:(UIKeyboardType)keyboardType {
	UITextField *field = [[UITextField alloc] init];
	field.placeholder = placeholder;
	field.keyboardType = keyboardType;
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	field.spellCheckingType = UITextSpellCheckingTypeNo;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	field.translatesAutoresizingMaskIntoConstraints = NO;
	return field;
}

- (UITableViewCell *)cellWithField:(UITextField *)field identifier:(NSString *)identifier {
	UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:identifier];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		[cell.contentView addSubview:field];
		[NSLayoutConstraint activateConstraints:@[
			[field.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
			[field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
			[field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
			[field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
		]];
	}
	return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case 0: return @"名称";
		case 1: return @"引导";
		case 2: return @"硬件";
		case 3: return @"网络";
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 1) {
		return @"内核与 initrd 用设备上的绝对路径，例如 /var/jb/var/mobile/Library/VFL/kernels/vmlinuz。";
	}
	if (section == 2) {
		return @"磁盘镜像是稀疏文件，8 GB 不会立刻占满存储空间。";
	}
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case 0: return 1;
		case 1: return 2;
		case 2: return 4;
		case 3: return 1;
	}
	return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 3) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"vfl.new.switch"];
		if (cell == nil) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
										  reuseIdentifier:@"vfl.new.switch"];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			self.networkSwitch = [[UISwitch alloc] init];
			self.networkSwitch.on = YES;
			cell.accessoryView = self.networkSwitch;
		}
		cell.textLabel.text = @"NAT 网络";
		return cell;
	}

	switch (indexPath.section) {
		case 0:
			if (self.nameField == nil) {
				self.nameField = [self textFieldWithPlaceholder:@"linux1"
												   keyboardType:UIKeyboardTypeDefault];
			}
			return [self cellWithField:self.nameField identifier:@"vfl.new.name"];
		case 1:
			if (indexPath.row == 0) {
				if (self.kernelField == nil) {
					self.kernelField = [self textFieldWithPlaceholder:@"内核 vmlinuz 的绝对路径"
														 keyboardType:UIKeyboardTypeURL];
				}
				return [self cellWithField:self.kernelField identifier:@"vfl.new.kernel"];
			}
			if (self.initrdField == nil) {
				self.initrdField = [self textFieldWithPlaceholder:@"initrd（可留空）"
													 keyboardType:UIKeyboardTypeURL];
			}
			return [self cellWithField:self.initrdField identifier:@"vfl.new.initrd"];
		default:
			break;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"vfl.new.number"];
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"vfl.new.number"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	UITextField *field = nil;
	switch (indexPath.row) {
		case 0:
			cell.textLabel.text = @"磁盘大小（GB）";
			if (self.diskField == nil) {
				self.diskField = [self textFieldWithPlaceholder:@"8" keyboardType:UIKeyboardTypeNumberPad];
			}
			field = self.diskField;
			break;
		case 1:
			cell.textLabel.text = @"内存（MB）";
			if (self.memoryField == nil) {
				self.memoryField = [self textFieldWithPlaceholder:@"2048"
													 keyboardType:UIKeyboardTypeNumberPad];
			}
			field = self.memoryField;
			break;
		case 2:
			cell.textLabel.text = @"CPU 核数";
			if (self.cpuField == nil) {
				self.cpuField = [self textFieldWithPlaceholder:@"2" keyboardType:UIKeyboardTypeNumberPad];
			}
			field = self.cpuField;
			break;
		default:
			cell.textLabel.text = @"显示设备";
			if (self.displayField == nil) {
				self.displayField = [self textFieldWithPlaceholder:@"1"
													  keyboardType:UIKeyboardTypeNumberPad];
			}
			field = self.displayField;
			break;
	}
	field.textAlignment = NSTextAlignmentRight;
	cell.accessoryView = field;
	field.frame = CGRectMake(0.0, 0.0, 110.0, 32.0);
	return cell;
}

#pragma mark - 保存

- (unsigned long long)unsignedValueOfField:(UITextField *)field fallback:(unsigned long long)fallback {
	NSString *text = [field.text stringByTrimmingCharactersInSet:
					  NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (text.length == 0) {
		return fallback;
	}
	unsigned long long value = strtoull(text.UTF8String, NULL, 10);
	return value > 0 ? value : fallback;
}

- (void)handleSave {
	NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:
					  NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *kernel = [self.kernelField.text stringByTrimmingCharactersInSet:
						NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (name.length == 0) {
		[self presentMessage:@"请先给虚拟机起个名字。"];
		return;
	}
	if (kernel.length == 0) {
		[self presentMessage:@"内核路径不能为空。"];
		return;
	}
	VFLVMStore *store = [[VFLVMStore alloc] init];
	if ([store definitionNamed:name] != nil) {
		[self presentMessage:[NSString stringWithFormat:@"%@ 已经存在，换个名字。", name]];
		return;
	}

	unsigned long long sizeInGB = MAX(1ULL, [self unsignedValueOfField:self.diskField fallback:8]);
	NSString *diskPath =
		[VFLDisksDirectory() stringByAppendingPathComponent:
		 [name stringByAppendingPathExtension:@"img"]];
	[NSFileManager.defaultManager createDirectoryAtPath:VFLDisksDirectory()
						   withIntermediateDirectories:YES
											attributes:nil
												 error:NULL];
	NSError *error = nil;
	if (![VFLVMStore createDiskImageAtPath:diskPath sizeInGB:sizeInGB error:&error]) {
		[self presentMessage:error.localizedDescription ?: @"创建磁盘失败"];
		return;
	}

	VFLVMDefinition *definition = [[VFLVMDefinition alloc] init];
	definition.name = name;
	definition.kernelPath = kernel;
	definition.initrdPath = [self.initrdField.text stringByTrimmingCharactersInSet:
							 NSCharacterSet.whitespaceAndNewlineCharacterSet];
	definition.diskPaths = @[ diskPath ];
	definition.readOnlyDisks = @[];
	definition.memoryMB = MAX(512ULL, [self unsignedValueOfField:self.memoryField fallback:2048]);
	definition.cpuCount = (NSUInteger)MAX(1ULL, [self unsignedValueOfField:self.cpuField fallback:2]);
	definition.displayCount =
		(NSUInteger)MAX(1ULL, [self unsignedValueOfField:self.displayField fallback:1]);
	definition.networkEnabled = self.networkSwitch.isOn;
	if (![store saveDefinition:definition error:&error]) {
		[self presentMessage:error.localizedDescription ?: @"保存定义失败"];
		return;
	}

	void (^completion)(void) = self.completion;
	[self dismissViewControllerAnimated:YES completion:^{
		if (completion != nil) {
			completion();
		}
	}];
}

- (void)handleCancel {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)presentMessage:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
																   message:message
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
