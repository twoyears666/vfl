// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <UIKit/UIKit.h>

/// 发行版图标映射：优先用 Resources/logos 里的官方 PNG，缺失时退回 SF Symbol。
@interface VFLDistroIcon : NSObject

+ (NSArray<NSString *> *)allIdentifiers;

+ (NSString *)displayNameForIdentifier:(NSString *)identifier;
+ (NSString *)symbolNameForIdentifier:(NSString *)identifier;
+ (UIColor *)colorForIdentifier:(NSString *)identifier;

+ (UIImage *)imageForIdentifier:(NSString *)identifier;
+ (UIImage *)thumbnailForIdentifier:(NSString *)identifier size:(CGFloat)size;

/// 蓝色剪影版：只取图标轮廓，由调用方用 tintColor 上色。
+ (UIImage *)templateThumbnailForIdentifier:(NSString *)identifier size:(CGFloat)size;

+ (UIImage *)thumbnailForImage:(UIImage *)image size:(CGFloat)size;

@end
