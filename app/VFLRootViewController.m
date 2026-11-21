// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLRootViewController.h"

#import "VFLClient.h"
#import "VFLDetailViewController.h"
#import "VFLNewVMViewController.h"
#import "VFLVMDefinition.h"

@interface VFLRootViewController ()

@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, copy) NSString *statusMessage;

@end

@implementation VFLRootViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"虚拟机";
	self.items = @[];
	self.statusMessage = @"正在读取…";
	self.tableView.rowHeight = 64.0;

	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self
							 action:@selector(handleRefresh)
				   forControlEvents:UIControlEventValueChanged];
	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
													  target:self
													  action:@selector(handleAdd)];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadData];
}

#pragma mark - 数据

- (void)handleRefresh {
	[self reloadData];
}

- (void)reloadData {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *error = nil;
		VFLClient *client = [VFLClient connectWithError:&error];
		if (client == nil) {
			[self finishReloadWithItems:nil
							   message:[NSString stringWithFormat:@"连不上守护进程：%@\n请确认 VFL 已正确安装并重启过设备。",
										error.localizedDescription ?: @"未知错误"]];
			return;
		}
		NSDictionary *response = [client sendRequestWithCommand:@"list" vm:nil error:&error];
		if (response == nil || ![response[@"ok"] boolValue]) {
			[self finishReloadWithItems:nil
							   message:response[@"error"] ?: error.localizedDescription ?: @"查询失败"];
			return;
		}
		NSArray *vms = [response[@"vms"] isKindOfClass:NSArray.class] ? response[@"vms"] : @[];
		[self finishReloadWithItems:vms
						   message:vms.count > 0 ? @"" : @"还没有虚拟机，点右上角 + 新建一台。"];
	});
}

- (void)finishReloadWithItems:(NSArray<NSDictionary *> *)items message:(NSString *)message {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (items != nil) {
			self.items = items;
		}
		self.statusMessage = message ?: @"";
		[self.refreshControl endRefreshing];
		[self.tableView reloadData];
		[self updateBackgroundView];
	});
}

- (void)updateBackgroundView {
	if (self.items.count > 0) {
		self.tableView.backgroundView = nil;
		return;
	}
	UILabel *label = [[UILabel alloc] init];
	label.text = self.statusMessage;
	label.numberOfLines = 0;
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = UIColor.secondaryLabelColor;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	label.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *container = [[UIView alloc] initWithFrame:self.tableView.bounds];
	[container addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
		[label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:32.0],
		[label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-32.0],
	]];
	self.tableView.backgroundView = container;
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"vfl.vm"];
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:@"vfl.vm"];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	NSDictionary *item = self.items[(NSUInteger)indexPath.row];
	NSString *state = item[@"state"] ?: @"unknown";
	cell.textLabel.text = item[@"name"] ?: @"";
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %llu MB · %lu vCPU · %lu 显示",
								 state,
								 [item[@"memoryMB"] unsignedLongLongValue],
								 (unsigned long)[item[@"cpuCount"] unsignedIntegerValue],
								 (unsigned long)[item[@"displays"] unsignedIntegerValue]];
	cell.detailTextLabel.textColor = [state isEqualToString:@"running"]
		? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *item = self.items[(NSUInteger)indexPath.row];
	VFLDetailViewController *detail =
		[[VFLDetailViewController alloc] initWithVMName:item[@"name"]];
	[self.navigationController pushViewController:detail animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
	trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *item = self.items[(NSUInteger)indexPath.row];
	NSString *name = item[@"name"] ?: @"";
	UIContextualAction *action =
		[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
												title:@"删除"
											  handler:^(UIContextualAction *action,
														UIView *sourceView,
														void (^completionHandler)(BOOL)) {
		if (![item[@"state"] isEqualToString:@"stopped"]) {
			[self presentMessage:[NSString stringWithFormat:@"%@ 还没关机，先关掉再删除。", name]];
			completionHandler(NO);
			return;
		}
		UIAlertController *alert = [UIAlertController
			alertControllerWithTitle:@"删除虚拟机"
							 message:[NSString stringWithFormat:@"%@ 的定义和磁盘都会被删除。", name]
					  preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"取消"
												  style:UIAlertActionStyleCancel
												handler:^(UIAlertAction *action) {
			completionHandler(NO);
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:@"删除"
												  style:UIAlertActionStyleDestructive
												handler:^(UIAlertAction *action) {
			[self deleteDefinitionNamed:name];
			completionHandler(YES);
			[self reloadData];
		}]];
		[self presentViewController:alert animated:YES completion:nil];
	}];
	return [UISwipeActionsConfiguration configurationWithActions:@[ action ]];
}

- (void)deleteDefinitionNamed:(NSString *)name {
	VFLVMStore *store = [[VFLVMStore alloc] init];
	VFLVMDefinition *definition = [store definitionNamed:name];
	NSError *error = nil;
	[store deleteDefinitionNamed:name error:&error];
	for (NSString *path in definition.diskPaths) {
		// 只删自己创建的磁盘镜像，用户指定的外部路径不动。
		if ([path hasPrefix:VFLDisksDirectory()]) {
			[NSFileManager.defaultManager removeItemAtPath:path error:NULL];
		}
	}
}

#pragma mark - 新建

- (void)handleAdd {
	VFLNewVMViewController *creator = [[VFLNewVMViewController alloc] init];
	__weak typeof(self) weakSelf = self;
	creator.completion = ^{
		[weakSelf reloadData];
	};
	UINavigationController *navigation =
		[[UINavigationController alloc] initWithRootViewController:creator];
	navigation.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigation animated:YES completion:nil];
}

- (void)presentMessage:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
																   message:message
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"好"
											  style:UIAlertActionStyleDefault
											handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
