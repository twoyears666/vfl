// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 数据根目录：rootless 下是 /var/jb/var/mobile/Library/VFL，普通环境退回 /var/mobile/Library/VFL。
FOUNDATION_EXPORT NSString *VFLDataDirectory(void);
FOUNDATION_EXPORT NSString *VFLVirtualMachinesDirectory(void);
FOUNDATION_EXPORT NSString *VFLDisksDirectory(void);
/// 导入的安装镜像（ISO）统一放这里，守护进程才读得到。
FOUNDATION_EXPORT NSString *VFLImagesDirectory(void);
FOUNDATION_EXPORT NSString *VFLRunDirectory(void);
FOUNDATION_EXPORT NSString *VFLSocketPath(void);

/// 一台虚拟机的定义。GUI 和 CLI 共用同一份 JSON，守护进程只读它。
@interface VFLVMDefinition : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *kernelPath;
@property (nonatomic, copy) NSString *initrdPath;
/// 第一块是系统盘；ISO 之类的附加盘按顺序排在后面。
@property (nonatomic, copy) NSArray<NSString *> *diskPaths;
/// 只读盘的下标集合（ISO 必须只读，否则安装器会试图往里写）。
@property (nonatomic, copy) NSArray<NSNumber *> *readOnlyDisks;
@property (nonatomic, assign) unsigned long long memoryMB;
@property (nonatomic, assign) NSUInteger cpuCount;
@property (nonatomic, copy) NSString *commandLine;
/// 发行版标识（alpine/debian/ubuntu/arch/fedora/linux），只影响界面图标。
@property (nonatomic, copy) NSString *distroIdentifier;
@property (nonatomic, assign) BOOL networkEnabled;
@property (nonatomic, copy) NSString *macAddress;
/// 显示设备数量。iPadOS 上 VZ 不提供画面视图，这个值只影响客户机配置。
@property (nonatomic, assign) NSUInteger displayCount;

+ (instancetype)definitionWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;

/// 默认引导参数：串口控制台优先，装完系统后还能从 ttyAMA0 看到日志。
- (NSString *)effectiveCommandLine;

@end

/// 读写 VFLVirtualMachinesDirectory() 下的 JSON 定义。
@interface VFLVMStore : NSObject

@property (nonatomic, readonly, copy) NSString *directory;

- (instancetype)initWithDirectory:(NSString *)directory;
- (instancetype)init;

- (NSArray<VFLVMDefinition *> *)definitions;
- (nullable VFLVMDefinition *)definitionNamed:(NSString *)name;
- (BOOL)saveDefinition:(VFLVMDefinition *)definition error:(NSError **)error;
- (BOOL)deleteDefinitionNamed:(NSString *)name error:(NSError **)error;

/// 新建一块空白磁盘镜像（大小按 GB 计），已存在就不动。
+ (BOOL)createDiskImageAtPath:(NSString *)path
					sizeInGB:(unsigned long long)sizeInGB
					   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
