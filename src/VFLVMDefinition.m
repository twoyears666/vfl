// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLVMDefinition.h"

/// 放在 Media 下：文件 App / Filza 能直接看到虚拟机、镜像和日志。
NSString *VFLDataDirectory(void) {
	return @"/var/mobile/Media/VFL";
}

NSString *VFLVirtualMachinesDirectory(void) {
	return [VFLDataDirectory() stringByAppendingPathComponent:@"vms"];
}

NSString *VFLDisksDirectory(void) {
	return [VFLDataDirectory() stringByAppendingPathComponent:@"disks"];
}

NSString *VFLImagesDirectory(void) {
	return [VFLDataDirectory() stringByAppendingPathComponent:@"images"];
}

NSString *VFLBootDirectory(void) {
	return [VFLDataDirectory() stringByAppendingPathComponent:@"boot"];
}

NSString *VFLEFIDirectory(void) {
	return [VFLDataDirectory() stringByAppendingPathComponent:@"efi"];
}

NSString *VFLRunDirectory(void) {
	return [VFLDataDirectory() stringByAppendingPathComponent:@"run"];
}

NSString *VFLSocketPath(void) {
	return [VFLRunDirectory() stringByAppendingPathComponent:@"vfl.sock"];
}

@implementation VFLVMDefinition

- (instancetype)init {
	self = [super init];
	if (self) {
		// JSON 字典里不能出现 nil：GUI 建新对象时未必填满所有字段。
		_name = @"linux";
		_kernelPath = @"";
		_initrdPath = @"";
		_commandLine = @"";
		_distroIdentifier = @"linux";
		_macAddress = @"";
		_diskPaths = @[];
		_readOnlyDisks = @[];
		_memoryMB = 2048;
		_cpuCount = 2;
		_displayCount = 1;
		_firstBoot = YES;
	}
	return self;
}

+ (instancetype)definitionWithDictionary:(NSDictionary *)dictionary {
	VFLVMDefinition *definition = [[VFLVMDefinition alloc] init];
	definition.name = dictionary[@"name"] ?: @"linux";
	definition.kernelPath = dictionary[@"kernel"] ?: @"";
	definition.initrdPath = dictionary[@"initrd"] ?: @"";
	definition.diskPaths = dictionary[@"disks"] ?: @[];
	definition.readOnlyDisks = dictionary[@"readOnlyDisks"] ?: @[];
	definition.memoryMB = [dictionary[@"memoryMB"] unsignedLongLongValue] ?: 2048;
	definition.cpuCount = [dictionary[@"cpuCount"] unsignedIntegerValue] ?: 2;
	definition.commandLine = dictionary[@"commandLine"] ?: @"";
	definition.distroIdentifier = dictionary[@"distro"] ?: @"linux";
	definition.networkEnabled = [dictionary[@"network"] boolValue];
	definition.macAddress = dictionary[@"mac"] ?: @"";
	definition.displayCount = [dictionary[@"displays"] unsignedIntegerValue] ?: 1;
	definition.firstBoot = dictionary[@"firstBoot"] == nil
		? YES : [dictionary[@"firstBoot"] boolValue];
	// 旧定义没有 bootMode，按内核直启处理，避免升级后老虚拟机突然走 EFI。
	definition.bootMode = [dictionary[@"bootMode"] isEqualToString:@"efi"]
		? VFLBootModeEFI : VFLBootModeKernel;
	return definition;
}

- (NSDictionary *)dictionaryRepresentation {
	return @{
		@"name": self.name ?: @"linux",
		@"kernel": self.kernelPath ?: @"",
		@"initrd": self.initrdPath ?: @"",
		@"disks": self.diskPaths ?: @[],
		@"readOnlyDisks": self.readOnlyDisks ?: @[],
		@"memoryMB": @(self.memoryMB),
		@"cpuCount": @(self.cpuCount),
		@"commandLine": self.commandLine ?: @"",
		@"distro": self.distroIdentifier ?: @"linux",
		@"network": @(self.networkEnabled),
		@"mac": self.macAddress ?: @"",
		@"displays": @(self.displayCount),
		@"firstBoot": @(self.firstBoot),
		@"bootMode": self.bootMode == VFLBootModeKernel ? @"kernel" : @"efi",
	};
}

- (NSString *)efiVariableStorePath {
	NSString *base = self.name.length > 0 ? self.name : @"linux";
	return [VFLEFIDirectory() stringByAppendingPathComponent:
			[base stringByAppendingPathExtension:@"nvram"]];
}

- (NSString *)effectiveCommandLine {
	if (self.commandLine.length > 0) {
		return self.commandLine;
	}
	// PL011（ttyAMA0）与 virtio-console（hvc0）都带上，串口硬件换哪种都能出日志。
	return @"console=ttyAMA0,115200 console=hvc0 loglevel=7 panic=1";
}

@end

@implementation VFLVMStore

- (instancetype)init {
	return [self initWithDirectory:VFLVirtualMachinesDirectory()];
}

- (instancetype)initWithDirectory:(NSString *)directory {
	self = [super init];
	if (self) {
		_directory = [directory copy];
		[NSFileManager.defaultManager createDirectoryAtPath:directory
							   withIntermediateDirectories:YES
												attributes:nil
													 error:NULL];
	}
	return self;
}

- (NSArray<VFLVMDefinition *> *)definitions {
	NSError *error = nil;
	NSArray<NSString *> *names =
		[NSFileManager.defaultManager contentsOfDirectoryAtPath:self.directory error:&error];
	if (names == nil) {
		return @[];
	}
	NSMutableArray<VFLVMDefinition *> *result = [NSMutableArray array];
	for (NSString *name in [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
		if (![name.pathExtension isEqualToString:@"json"]) {
			continue;
		}
		NSString *path = [self.directory stringByAppendingPathComponent:name];
		NSData *data = [NSData dataWithContentsOfFile:path];
		if (data == nil) {
			continue;
		}
		NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
		if (dictionary == nil) {
			continue;
		}
		[result addObject:[VFLVMDefinition definitionWithDictionary:dictionary]];
	}
	return result;
}

- (VFLVMDefinition *)definitionNamed:(NSString *)name {
	if (name.length == 0) {
		return nil;
	}
	NSString *path = [self.directory stringByAppendingPathComponent:
					  [name stringByAppendingPathExtension:@"json"]];
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (data == nil) {
		return nil;
	}
	NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	return dictionary != nil ? [VFLVMDefinition definitionWithDictionary:dictionary] : nil;
}

- (BOOL)saveDefinition:(VFLVMDefinition *)definition error:(NSError **)error {
	if (definition.name.length == 0) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:1 userInfo:@{ NSLocalizedDescriptionKey: @"虚拟机名不能为空" }];
		}
		return NO;
	}
	NSData *data = [NSJSONSerialization dataWithJSONObject:definition.dictionaryRepresentation
												   options:NSJSONWritingPrettyPrinted
													 error:error];
	if (data == nil) {
		return NO;
	}
	NSString *path = [self.directory stringByAppendingPathComponent:
					  [definition.name stringByAppendingPathExtension:@"json"]];
	return [data writeToFile:path atomically:YES];
}

- (BOOL)deleteDefinitionNamed:(NSString *)name error:(NSError **)error {
	NSString *path = [self.directory stringByAppendingPathComponent:
					  [name stringByAppendingPathExtension:@"json"]];
	return [NSFileManager.defaultManager removeItemAtPath:path error:error];
}

+ (BOOL)createDiskImageAtPath:(NSString *)path
					 sizeInGB:(unsigned long long)sizeInGB
						error:(NSError **)error {
	if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
		return YES;
	}
	unsigned long long size = sizeInGB * 1024ULL * 1024ULL * 1024ULL;
	if (![NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil]) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:2
									userInfo:@{ NSLocalizedDescriptionKey: @"无法创建磁盘镜像" }];
		}
		return NO;
	}
	NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
	// 稀疏文件：truncate 只改大小，不立刻占满存储。
	[handle truncateFileAtOffset:size];
	[handle closeFile];
	NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
	BOOL ok = [attributes[NSFileSize] unsignedLongLongValue] == size;
	if (!ok && error != NULL) {
		*error = [NSError errorWithDomain:@"vfl" code:3
								userInfo:@{ NSLocalizedDescriptionKey: @"无法调整磁盘镜像大小" }];
	}
	return ok;
}

@end
