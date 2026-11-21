// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLRootSplitViewController.h"

#import "VFLDetailViewController.h"
#import "VFLSidebarViewController.h"
#import "VFLVMDefinition.h"

@interface VFLRootSplitViewController () <VFLSidebarDelegate>

@property (nonatomic, strong) VFLSidebarViewController *sidebarViewController;
@property (nonatomic, strong) VFLDetailViewController *detailViewController;

@end

@implementation VFLRootSplitViewController

- (instancetype)init {
	return [self initWithStyle:UISplitViewControllerStyleDoubleColumn];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
	self.preferredSplitBehavior = UISplitViewControllerSplitBehaviorTile;

	self.sidebarViewController = [[VFLSidebarViewController alloc] init];
	self.sidebarViewController.selectionDelegate = self;

	self.detailViewController = [[VFLDetailViewController alloc] init];

	UINavigationController *primary =
		[[UINavigationController alloc] initWithRootViewController:self.sidebarViewController];
	primary.navigationBar.prefersLargeTitles = YES;

	UINavigationController *secondary =
		[[UINavigationController alloc] initWithRootViewController:self.detailViewController];
	secondary.navigationBar.prefersLargeTitles = YES;

	self.viewControllers = @[ primary, secondary ];

	NSArray<VFLVMDefinition *> *machines = [[[VFLVMStore alloc] init] definitions];
	if (machines.count > 0) {
		self.detailViewController.vmName = machines.firstObject.name;
		[self.sidebarViewController selectMachineAtIndex:0];
	}
}

#pragma mark - VFLSidebarDelegate

- (void)sidebarViewController:(VFLSidebarViewController *)controller
			 didSelectVMNamed:(NSString *)name {
	self.detailViewController.vmName = name;
	if (self.isCollapsed) {
		[self showDetailViewController:self.detailViewController sender:nil];
		return;
	}
	// 展开态把侧栏收起，直接看详情。
	[self showDetailViewController:self.viewControllers.lastObject sender:nil];
}

@end
