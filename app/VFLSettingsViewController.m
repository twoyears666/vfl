// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLSettingsViewController.h"

#import "VFLVMDefinition.h"
#import "VFLVirtualization.h"

@interface VFLSettingsViewController ()

@property (nonatomic, assign) BOOL virtualizationAvailable;
@property (nonatomic, copy) NSString *virtualizationDiagnostic;

@end

@implementation VFLSettingsViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = @"设置";
	self.tableView.rowHeight = 48.0;

	self.virtualizationDiagnostic = @"";
	NSString *diagnostic = nil;
	self.virtualizationAvailable = VFLVirtualizationPrepare(&diagnostic);
	self.virtualizationDiagnostic = diagnostic ?: @"";

	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
													  target:self
													  action:@selector(closeTapped)];
}

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 数据

- (NSString *)versionString {
	NSDictionary *info = NSBundle.mainBundle.infoDictionary;
	NSString *shortVersion = info[@"CFBundleShortVersionString"] ?: @"0.0.0";
	NSString *build = info[@"CFBundleVersion"];
	return build.length > 0
		? [NSString stringWithFormat:@"%@ (%@)", shortVersion, build] : shortVersion;
}

- (NSArray<NSArray<NSArray<NSString *> *> *> *)rows {
	unsigned long long physicalMB =
		NSProcessInfo.processInfo.physicalMemory / (1024ULL * 1024ULL);
	NSString *memory = [NSString stringWithFormat:@"%llu MB", physicalMB];
	NSString *cores = [NSString stringWithFormat:@"%lu 核",
					   (unsigned long)NSProcessInfo.processInfo.processorCount];

	NSString *virtualization = self.virtualizationAvailable ? @"可用" : @"不可用";
	if (!self.virtualizationAvailable && self.virtualizationDiagnostic.length > 0) {
		virtualization = [NSString stringWithFormat:@"不可用 · %@", self.virtualizationDiagnostic];
	}

	return @[
		@[
			@[ @"版本", [self versionString] ],
			@[ @"许可证", @"Apache-2.0" ],
			@[ @"仓库", @"github.com/twoyears666/vfl" ],
		],
		@[
			@[ @"Virtualization.framework", virtualization ],
			@[ @"物理内存", memory ],
			@[ @"逻辑 CPU", cores ],
		],
		@[
			@[ @"数据目录", VFLDataDirectory() ],
			@[ @"套接字", VFLSocketPath() ],
		],
	];
}

- (NSString *)titleForSection:(NSInteger)section {
	switch (section) {
		case 0: return @"关于";
		case 1: return @"运行环境";
		case 2: return @"路径";
		default: return @"";
	}
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return [self titleForSection:section];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[self rows][(NSUInteger)section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"VFLSettingsCell"];
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
									  reuseIdentifier:@"VFLSettingsCell"];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
		cell.detailTextLabel.minimumScaleFactor = 0.7;
		cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	}

	NSArray<NSString *> *row = [self rows][(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
	cell.textLabel.text = row[0];
	cell.detailTextLabel.text = row[1];
	if ([row[0] isEqualToString:@"仓库"]) {
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else {
		cell.accessoryType = UITableViewCellAccessoryNone;
	}
	return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSArray<NSString *> *row = [self rows][(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
	if ([row[0] isEqualToString:@"仓库"]) {
		[UIApplication.sharedApplication openURL:[NSURL URLWithString:@"https://github.com/twoyears666/vfl"]
										options:@{}
							  completionHandler:nil];
		return;
	}
	// 长按/点按路径直接复制，方便在 iSH 或终端里用。
	UIPasteboard.generalPasteboard.string = row[1];
}

@end
