// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLSidebarViewController.h"

#import "VFLCreateMachineViewController.h"
#import "VFLClient.h"
#import "VFLDistroIcon.h"
#import "VFLSettingsViewController.h"
#import "VFLVMDefinition.h"

static NSString *const VFLSidebarCellIdentifier = @"VFLSidebarCellIdentifier";

@interface VFLSidebarViewController ()

@property (nonatomic, strong) NSArray<VFLVMDefinition *> *machines;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *states;

@end

@implementation VFLSidebarViewController

- (instancetype)init {
	return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = @"虚拟机";
	self.machines = @[];
	self.states = @{};

	self.tableView.rowHeight = 64.0;
	self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

	UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
	[refreshControl addTarget:self
					   action:@selector(reloadMachines)
			 forControlEvents:UIControlEventValueChanged];
	self.refreshControl = refreshControl;

	UIBarButtonItem *addItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
													  target:self
													  action:@selector(addTapped)];
	UIBarButtonItem *settingsItem =
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(settingsTapped)];
	self.navigationItem.rightBarButtonItems = @[ addItem, settingsItem ];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadMachines];
}

- (void)settingsTapped {
	VFLSettingsViewController *settings = [[VFLSettingsViewController alloc] init];
	UINavigationController *navigationController =
		[[UINavigationController alloc] initWithRootViewController:settings];
	navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigationController animated:YES completion:nil];
}

- (void)selectMachineAtIndex:(NSUInteger)index {
	[self loadViewIfNeeded];
	if (index >= self.machines.count) {
		return;
	}
	[self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]
								animated:NO
						  scrollPosition:UITableViewScrollPositionNone];
}

#pragma mark - 数据

- (void)reloadMachines {
	VFLVMStore *store = [[VFLVMStore alloc] init];
	self.machines = [store definitions];
	[self.tableView reloadData];

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError *error = nil;
		VFLClient *client = [VFLClient connectWithError:&error];
		if (client == nil) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.refreshControl endRefreshing];
			});
			return;
		}
		NSDictionary *response = [client sendRequestWithCommand:@"list" vm:nil error:&error];
		[client close];
		if (![response[@"ok"] boolValue]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.refreshControl endRefreshing];
			});
			return;
		}
		NSMutableDictionary<NSString *, NSString *> *states = [NSMutableDictionary dictionary];
		for (NSDictionary *item in response[@"vms"]) {
			if ([item isKindOfClass:NSDictionary.class] && item[@"name"] != nil) {
				states[item[@"name"]] = item[@"state"] ?: @"stopped";
			}
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			self.states = states;
			[self.tableView reloadData];
			[self.refreshControl endRefreshing];
		});
	});
}

- (NSString *)stateForMachine:(VFLVMDefinition *)machine {
	return self.states[machine.name] ?: @"stopped";
}

- (NSString *)stateText:(NSString *)state {
	if ([state isEqualToString:@"running"]) {
		return @"运行中";
	}
	if ([state isEqualToString:@"starting"]) {
		return @"启动中";
	}
	if ([state isEqualToString:@"stopping"]) {
		return @"关机中";
	}
	if ([state isEqualToString:@"error"]) {
		return @"出错";
	}
	return @"已停止";
}

#pragma mark - 新建

- (void)addTapped {
	NSString *suggestedName =
		[NSString stringWithFormat:@"虚拟机 %lu", (unsigned long)self.machines.count + 1];
	VFLCreateMachineViewController *creator =
		[[VFLCreateMachineViewController alloc] initWithSuggestedName:suggestedName];

	__weak typeof(self) weakSelf = self;
	creator.completion = ^(NSString *name) {
		[weakSelf reloadMachines];
		NSUInteger index = [weakSelf.machines indexOfObjectPassingTest:
			^BOOL(VFLVMDefinition *definition, NSUInteger idx, BOOL *stop) {
				return [definition.name isEqualToString:name];
			}];
		if (index == NSNotFound) {
			return;
		}
		[weakSelf selectMachineAtIndex:index];
		[weakSelf.selectionDelegate sidebarViewController:weakSelf didSelectVMNamed:name];
	};

	UINavigationController *navigationController =
		[[UINavigationController alloc] initWithRootViewController:creator];
	navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.machines.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:VFLSidebarCellIdentifier];
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:VFLSidebarCellIdentifier];
	}

	VFLVMDefinition *machine = self.machines[(NSUInteger)indexPath.row];
	NSString *state = [self stateForMachine:machine];
	cell.textLabel.text = machine.name;
	cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %llu MB · %lu vCPU · %lu 显示",
								 [self stateText:state],
								 machine.memoryMB,
								 (unsigned long)machine.cpuCount,
								 (unsigned long)machine.displayCount];
	cell.detailTextLabel.textColor = [state isEqualToString:@"running"]
		? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
	cell.imageView.image = [VFLDistroIcon thumbnailForIdentifier:machine.distroIdentifier size:28.0];
	cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
	cell.accessoryType = UITableViewCellAccessoryNone;
	return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	VFLVMDefinition *machine = self.machines[(NSUInteger)indexPath.row];
	[self.selectionDelegate sidebarViewController:self didSelectVMNamed:machine.name];
}

#pragma mark - 左滑删除

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
	trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	UIContextualAction *deleteAction =
		[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
												title:@"删除"
											  handler:^(UIContextualAction *action,
														UIView *sourceView,
														void (^completionHandler)(BOOL)) {
		completionHandler(YES);
		dispatch_async(dispatch_get_main_queue(), ^{
			[self confirmDeleteAtIndex:(NSUInteger)indexPath.row];
		});
	}];
	deleteAction.image = [UIImage systemImageNamed:@"trash"];
	return [UISwipeActionsConfiguration configurationWithActions:@[ deleteAction ]];
}

- (void)confirmDeleteAtIndex:(NSUInteger)index {
	if (index >= self.machines.count) {
		return;
	}
	VFLVMDefinition *machine = self.machines[index];
	if (![[self stateForMachine:machine] isEqualToString:@"stopped"]) {
		UIAlertController *alert =
			[UIAlertController alertControllerWithTitle:@"虚拟机还在运行"
												message:[NSString stringWithFormat:@"「%@」先关机再删除。", machine.name]
										 preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}

	UIAlertController *alert =
		[UIAlertController alertControllerWithTitle:@"删除虚拟机"
											message:[NSString stringWithFormat:
													 @"「%@」以及它自己创建的磁盘镜像都会被永久删除，无法恢复。",
													 machine.name]
									 preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"删除"
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
		[weakSelf deleteMachineAtIndex:index];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"取消"
											  style:UIAlertActionStyleCancel
											handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteMachineAtIndex:(NSUInteger)index {
	if (index >= self.machines.count) {
		return;
	}
	VFLVMDefinition *machine = self.machines[index];
	BOOL wasSelected = self.tableView.indexPathForSelectedRow != nil &&
		self.tableView.indexPathForSelectedRow.row == (NSInteger)index;

	VFLVMStore *store = [[VFLVMStore alloc] init];
	NSError *error = nil;
	if (![store deleteDefinitionNamed:machine.name error:&error]) {
		UIAlertController *alert =
			[UIAlertController alertControllerWithTitle:@"删除失败"
												message:error.localizedDescription ?: @"定义文件删不掉。"
										 preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	for (NSString *path in machine.diskPaths) {
		// 只删自己目录里的镜像，用户指定的外部路径不动。
		if ([path hasPrefix:VFLDisksDirectory()]) {
			[NSFileManager.defaultManager removeItemAtPath:path error:NULL];
		}
	}

	self.machines = [store definitions];
	[self.tableView deleteRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:(NSInteger)index inSection:0] ]
						  withRowAnimation:UITableViewRowAnimationAutomatic];

	if (self.machines.count == 0) {
		[self.selectionDelegate sidebarViewController:self didSelectVMNamed:nil];
		return;
	}
	if (!wasSelected) {
		return;
	}
	NSUInteger target = MIN(index, self.machines.count - 1);
	[self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)target inSection:0]
								animated:NO
						  scrollPosition:UITableViewScrollPositionNone];
	[self.selectionDelegate sidebarViewController:self
								 didSelectVMNamed:self.machines[target].name];
}

@end
