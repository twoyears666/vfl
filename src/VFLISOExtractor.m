// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLISOExtractor.h"

#import <string.h>

static const uint32_t VFLISOSectorSize = 2048;
static const NSUInteger VFLISOChunkSize = 4 * 1024 * 1024;

static NSError *VFLISOError(NSString *message) {
	return [NSError errorWithDomain:@"vfl.iso"
							   code:1
						   userInfo:@{ NSLocalizedDescriptionKey: message ?: @"镜像解析失败" }];
}

static uint32_t VFLISOLittleEndian32(const uint8_t *bytes) {
	return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8)
		| ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

#pragma mark - 候选文件

@interface VFLISOCandidate : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, assign) uint32_t extent;
@property (nonatomic, assign) uint32_t length;
@property (nonatomic, assign) NSInteger score;
@end

@implementation VFLISOCandidate
@end

static BOOL VFLISOKernelName(NSString *lowercaseName) {
	return [lowercaseName hasPrefix:@"vmlinuz"]
		|| [lowercaseName hasPrefix:@"vmlinux"]
		|| [lowercaseName hasPrefix:@"zimage"]
		|| [lowercaseName hasPrefix:@"kernel"]
		|| [lowercaseName isEqualToString:@"image"]
		|| [lowercaseName hasPrefix:@"image-"];
}

static BOOL VFLISOInitrdName(NSString *lowercaseName) {
	return [lowercaseName hasPrefix:@"initrd"]
		|| [lowercaseName hasPrefix:@"initramfs"]
		|| [lowercaseName hasPrefix:@"uinitrd"];
}

/// 目录布局打分：Ubuntu/Debian 的 casper、live 优先，其次 isolinux / pxeboot / boot。
static NSInteger VFLISOPathScore(NSString *path) {
	NSString *lowercase = path.lowercaseString;
	if ([lowercase containsString:@"/casper/"]) {
		return 50;
	}
	if ([lowercase containsString:@"/live/"]) {
		return 45;
	}
	if ([lowercase containsString:@"/images/pxeboot/"]) {
		return 40;
	}
	if ([lowercase containsString:@"/isolinux/"]) {
		return 35;
	}
	if ([lowercase containsString:@"/boot/"]) {
		return 30;
	}
	if ([lowercase containsString:@"/install"]) {
		return 20;
	}
	return 10;
}

#pragma mark - 扫描

@interface VFLISOScanner : NSObject
@property (nonatomic, strong) NSFileHandle *handle;
@property (nonatomic, strong) NSMutableArray<VFLISOCandidate *> *candidates;
@end

@implementation VFLISOScanner

- (void)scanExtent:(uint32_t)extent size:(uint32_t)size prefix:(NSString *)prefix depth:(NSUInteger)depth {
	if (size == 0 || extent == 0 || depth > 8) {
		return;
	}
	@try {
		[self.handle seekToOffset:(unsigned long long)extent * VFLISOSectorSize error:NULL];
	} @catch (NSException *exception) {
		return;
	}
	NSData *data = [self.handle readDataOfLength:size];
	if (data.length == 0) {
		return;
	}
	const uint8_t *bytes = data.bytes;
	NSUInteger offset = 0;
	while (offset + 34 <= data.length) {
		uint8_t recordLength = bytes[offset];
		if (recordLength == 0) {
			// 记录不跨扇区：0 长度表示本扇区剩余部分都是填充。
			offset = (offset / VFLISOSectorSize + 1) * VFLISOSectorSize;
			continue;
		}
		if (offset + recordLength > data.length) {
			break;
		}
		uint8_t flags = bytes[offset + 25];
		uint8_t nameLength = bytes[offset + 32];
		if (33 + nameLength > recordLength) {
			offset += recordLength;
			continue;
		}
		const uint8_t *nameBytes = bytes + offset + 33;
		// 0x00 / 0x01 是 "." 与 ".."。
		if (nameLength == 1 && (nameBytes[0] == 0x00 || nameBytes[0] == 0x01)) {
			offset += recordLength;
			continue;
		}
		NSString *name = [[NSString alloc] initWithBytes:nameBytes
												 length:nameLength
											   encoding:NSASCIIStringEncoding];
		NSRange versionRange = [name rangeOfString:@";"];
		if (versionRange.location != NSNotFound) {
			name = [name substringToIndex:versionRange.location];
		}
		if ([name hasSuffix:@"."] && name.length > 1) {
			name = [name substringToIndex:name.length - 1];
		}
		if (name.length == 0) {
			offset += recordLength;
			continue;
		}

		uint32_t recordExtent = VFLISOLittleEndian32(bytes + offset + 2);
		uint32_t recordSize = VFLISOLittleEndian32(bytes + offset + 10);
		NSString *path = [prefix stringByAppendingPathComponent:name];

		if ((flags & 0x02) != 0) {
			[self scanExtent:recordExtent size:recordSize prefix:path depth:depth + 1];
		} else {
			NSString *lowercase = name.lowercaseString;
			BOOL isKernel = VFLISOKernelName(lowercase);
			BOOL isInitrd = VFLISOInitrdName(lowercase);
			if ((isKernel || isInitrd) && recordSize > 0) {
				VFLISOCandidate *candidate = [[VFLISOCandidate alloc] init];
				candidate.path = path;
				candidate.fileName = name;
				candidate.extent = recordExtent;
				candidate.length = recordSize;
				candidate.score = VFLISOPathScore(path) + (isKernel ? 5 : 0) + (isInitrd ? 4 : 0);
				[self.candidates addObject:candidate];
			}
		}
		offset += recordLength;
	}
}

@end

#pragma mark -

@implementation VFLISOExtractor

+ (BOOL)extractBootFilesFromISOAtPath:(NSString *)isoPath
						intoDirectory:(NSString *)directory
							   kernel:(NSString *_Nullable *_Nullable)kernelPath
							   initrd:(NSString *_Nullable *_Nullable)initrdPath
								error:(NSError **)error {
	if (kernelPath != NULL) {
		*kernelPath = nil;
	}
	if (initrdPath != NULL) {
		*initrdPath = nil;
	}
	NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:isoPath];
	if (handle == nil) {
		if (error != NULL) {
			*error = VFLISOError(@"打不开安装镜像");
		}
		return NO;
	}

	@try {
		[handle seekToOffset:16 * VFLISOSectorSize error:NULL];
	} @catch (NSException *exception) {
		if (error != NULL) {
			*error = VFLISOError(@"镜像太短，不是有效的 ISO");
		}
		return NO;
	}
	NSData *primary = [handle readDataOfLength:VFLISOSectorSize];
	if (primary.length < 190 || memcmp(primary.bytes + 1, "CD001", 5) != 0) {
		if (error != NULL) {
			*error = VFLISOError(@"不是 ISO9660 镜像（可能用了 UDF 布局）");
		}
		return NO;
	}
	const uint8_t *primaryBytes = primary.bytes;
	uint32_t rootExtent = VFLISOLittleEndian32(primaryBytes + 156 + 2);
	uint32_t rootSize = VFLISOLittleEndian32(primaryBytes + 156 + 10);

	VFLISOScanner *scanner = [[VFLISOScanner alloc] init];
	scanner.handle = handle;
	scanner.candidates = [NSMutableArray array];
	[scanner scanExtent:rootExtent size:rootSize prefix:@"/" depth:0];

	VFLISOCandidate *bestKernel = nil;
	VFLISOCandidate *bestInitrd = nil;
	for (VFLISOCandidate *candidate in scanner.candidates) {
		BOOL isInitrd = VFLISOInitrdName(candidate.fileName.lowercaseString);
		if (isInitrd) {
			if (bestInitrd == nil || candidate.score > bestInitrd.score) {
				bestInitrd = candidate;
			}
		} else if (bestKernel == nil || candidate.score > bestKernel.score) {
			bestKernel = candidate;
		}
	}
	if (bestKernel == nil) {
		if (error != NULL) {
			*error = VFLISOError(@"镜像里没找到 vmlinuz / Image 内核");
		}
		return NO;
	}

	NSError *directoryError = nil;
	if (![NSFileManager.defaultManager createDirectoryAtPath:directory
								withIntermediateDirectories:YES
												 attributes:nil
													  error:&directoryError]) {
		if (error != NULL) {
			*error = directoryError;
		}
		return NO;
	}

	NSString *kernelDestination = [directory stringByAppendingPathComponent:bestKernel.fileName];
	if (![self copyCandidate:bestKernel toPath:kernelDestination handle:handle error:error]) {
		return NO;
	}
	if (kernelPath != NULL) {
		*kernelPath = kernelDestination;
	}

	if (bestInitrd != nil) {
		NSString *initrdDestination = [directory stringByAppendingPathComponent:bestInitrd.fileName];
		if (![self copyCandidate:bestInitrd toPath:initrdDestination handle:handle error:error]) {
			return NO;
		}
		if (initrdPath != NULL) {
			*initrdPath = initrdDestination;
		}
	}
	return YES;
}

/// 分块拷贝，避免把几百 MB 的 initrd 一次性读进内存。
+ (BOOL)copyCandidate:(VFLISOCandidate *)candidate
			   toPath:(NSString *)path
			   handle:(NSFileHandle *)handle
				error:(NSError **)error {
	[NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
	NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:path];
	if (output == nil) {
		if (error != NULL) {
			*error = VFLISOError([NSString stringWithFormat:@"无法写入 %@", path]);
		}
		return NO;
	}
	@try {
		[handle seekToOffset:(unsigned long long)candidate.extent * VFLISOSectorSize error:NULL];
		uint64_t remaining = candidate.length;
		while (remaining > 0) {
			NSUInteger chunk = (NSUInteger)MIN(remaining, (uint64_t)VFLISOChunkSize);
			NSData *data = [handle readDataOfLength:chunk];
			if (data.length == 0) {
				break;
			}
			[output writeData:data];
			remaining -= data.length;
		}
		[output closeFile];
	} @catch (NSException *exception) {
		[output closeFile];
		if (error != NULL) {
			*error = VFLISOError([NSString stringWithFormat:@"抽取 %@ 失败：%@",
								  candidate.fileName, exception.reason ?: @"读写错误"]);
		}
		return NO;
	}
	if (remaining > 0) {
		if (error != NULL) {
			*error = VFLISOError([NSString stringWithFormat:@"%@ 数据不完整", candidate.fileName]);
		}
		return NO;
	}
	return YES;
}

@end
