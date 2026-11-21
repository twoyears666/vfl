// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 从 ISO9660 安装镜像里找内核与 initrd，抽到本地目录。
/// 支持常见 Linux 发行版的目录布局：casper / live / isolinux / boot / images/pxeboot。
@interface VFLISOExtractor : NSObject

/// 成功时 kernelPath / initrdPath 至少返回内核路径；initrd 可能没有。
+ (BOOL)extractBootFilesFromISOAtPath:(NSString *)isoPath
						intoDirectory:(NSString *)directory
							   kernel:(NSString *_Nullable *_Nullable)kernelPath
							   initrd:(NSString *_Nullable *_Nullable)initrdPath
								error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
