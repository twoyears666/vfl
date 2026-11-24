// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// iOS 上没有 Virtualization.framework 的公开头文件（它在系统里是私有的，
/// 只有带 com.apple.security.virtualization 权限的进程能用）。
/// 这里只声明本工程实际用到的那些类与方法，运行时再用 NSClassFromString 取类，
/// 所以不链接任何框架符号，也不会因为 SDK 缺头文件编译不过。

typedef NS_ENUM(NSInteger, VZVirtualMachineState) {
	VZVirtualMachineStateStopped = 0,
	VZVirtualMachineStateRunning = 1,
	VZVirtualMachineStatePaused = 2,
	VZVirtualMachineStateError = 3,
	VZVirtualMachineStateStarting = 4,
	VZVirtualMachineStatePausing = 5,
	VZVirtualMachineStateResuming = 6,
	VZVirtualMachineStateStopping = 7,
};

@interface VZVirtualMachineConfiguration : NSObject
@property (nonatomic) NSUInteger CPUCount;
@property (nonatomic) unsigned long long memorySize;
@property (nonatomic, strong) id bootLoader;
@property (nonatomic, copy) NSArray *entropyDevices;
@property (nonatomic, copy) NSArray *networkDevices;
@property (nonatomic, copy) NSArray *serialPorts;
@property (nonatomic, copy) NSArray *storageDevices;
@property (nonatomic, copy) NSArray *graphicsDevices;
@property (nonatomic, copy) NSArray *socketDevices;
- (BOOL)validateWithError:(NSError **)error;
@end

@interface VZLinuxBootLoader : NSObject
- (instancetype)initWithKernelURL:(NSURL *)kernelURL;
@property (nonatomic, copy) NSString *commandLine;
@property (nonatomic, copy, nullable) NSURL *initialRamdiskURL;
@end

/// EFI 引导器：让固件自己从 ISO / 系统盘找 EFI/BOOT/BOOTAA64.EFI。
/// 安装阶段由 ISO 的 GRUB 装系统，装完删掉 ISO 就直接从系统盘引导。
@interface VZEFIVariableStore : NSObject
- (instancetype)initWithURL:(NSURL *)URL;
- (instancetype)initCreatingVariableStoreAtURL:(NSURL *)URL
									  options:(NSUInteger)options
										error:(NSError **)error;
@end

@interface VZEFIBootLoader : NSObject
@property (nonatomic, strong) VZEFIVariableStore *variableStore;
@end

@interface VZVirtualMachine : NSObject
- (instancetype)initWithConfiguration:(VZVirtualMachineConfiguration *)configuration;
@property (nonatomic, readonly) VZVirtualMachineState state;
- (void)startWithCompletionHandler:(void (^)(NSError *_Nullable error))completionHandler;
- (void)stopWithCompletionHandler:(void (^)(NSError *_Nullable error))completionHandler;
- (BOOL)requestStopWithError:(NSError **)error;
@end

@interface VZDiskImageStorageDeviceAttachment : NSObject
- (instancetype)initWithURL:(NSURL *)URL readOnly:(BOOL)readOnly error:(NSError **)error;
@end

@interface VZVirtioBlockDeviceConfiguration : NSObject
- (instancetype)initWithAttachment:(VZDiskImageStorageDeviceAttachment *)attachment;
@end

@interface VZNATNetworkDeviceAttachment : NSObject
@end

@interface VZVirtioNetworkDeviceConfiguration : NSObject
@property (nonatomic, strong) id attachment;
@property (nonatomic, copy) id MACAddress;
@end

@interface VZMACAddress : NSObject
+ (instancetype)randomLocallyAdministeredAddress;
- (instancetype)initWithString:(NSString *)string;
@property (nonatomic, readonly, copy) NSString *string;
@end

@interface VZFileHandleSerialPortAttachment : NSObject
- (instancetype)initWithFileHandleForReading:(NSFileHandle *)fileHandleForReading
					   fileHandleForWriting:(NSFileHandle *)fileHandleForWriting;
@end

@interface VZVirtioConsoleDeviceSerialPortConfiguration : NSObject
@property (nonatomic, strong) VZFileHandleSerialPortAttachment *attachment;
@end

@interface VZVirtioEntropyDeviceConfiguration : NSObject
@end

/// 多显示设备。类是否真的存在取决于系统版本与平台，运行时探测后再用。
@interface VZVirtioGraphicsScanoutConfiguration : NSObject
- (instancetype)initWithWidthInPixels:(NSInteger)widthInPixels
					   heightInPixels:(NSInteger)heightInPixels;
@end

@interface VZVirtioGraphicsDeviceConfiguration : NSObject
@property (nonatomic, copy) NSArray *scanouts;
@end

/// 画面视图只有 macOS 才有；iOS 上一般取不到，GUI 会据此退回串口控制台。
@interface VZVirtualMachineView : NSObject
@property (nonatomic, strong) VZVirtualMachine *virtualMachine;
@property (nonatomic) BOOL capturesSystemKeys;
@end

/// 用类名安全地建实例：类不存在时返回 nil，而不是让进程在 objc_msgSend 上崩掉。
#define VFLNewInstance(className) \
	((className *)[[NSClassFromString(@#className) alloc] init])
#define VFLAlloc(classNameLiteral) \
	((id)[(NSClassFromString(classNameLiteral)) alloc])

/// 运行时加载 Virtualization.framework 并确认必需类都在。返回 NO 时 diagnostic 说明缺了什么。
BOOL VFLVirtualizationPrepare(NSString *_Nullable *_Nullable diagnostic);

/// App 自带的 EFI 固件（VZG21.fd / VZG11.fd）。VMM 默认去 /System 下找，
/// iPad 上没有，需要显式喂给它。按 VZG21 → VZG11 的顺序取第一个存在的。
NSURL *_Nullable VFLVirtualizationEFIROMURL(void);

/// 同上，但只认指定的文件名；传 nil 等价于 VFLVirtualizationEFIROMURL()。
NSURL *_Nullable VFLVirtualizationEFIROMURLWithName(NSString *_Nullable name);

/// VZ 用来区分客户机类型的常量（框架导出为 VZVirtualMachineGuestTypeLinux）。
/// 不显式设成 Linux 时，VZ 会按 macOS 客户机铺设备树，固件去 0x20000000
/// 读 PCIe ECAM 就会扑空、卡死在轮询里。取不到符号时退回字面量 @"Linux"。
NSString *VFLVirtualMachineGuestTypeLinux(void);

NS_ASSUME_NONNULL_END
