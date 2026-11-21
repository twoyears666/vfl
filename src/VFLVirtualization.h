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
@property (nonatomic, copy) NSArray *bootLoader;
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

NS_ASSUME_NONNULL_END
