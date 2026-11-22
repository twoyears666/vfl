// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLBackgroundKeeper.h"

#import <AVFoundation/AVFoundation.h>

/// 生成 1 秒 16-bit 单声道静音 PCM，包成 WAV 给 AVAudioPlayer 循环播放。
static NSData *VFLCreateSilentWave(void) {
	const uint32_t sampleRate = 44100;
	const uint32_t frames = sampleRate;
	const uint32_t dataSize = frames * 2;

	NSMutableData *data = [NSMutableData data];
	void (^append)(const void *, NSUInteger) = ^(const void *bytes, NSUInteger length) {
		[data appendBytes:bytes length:length];
	};

	append("RIFF", 4);
	uint32_t riffSize = 36 + dataSize;
	append(&riffSize, 4);
	append("WAVEfmt ", 8);
	uint32_t fmtSize = 16;
	append(&fmtSize, 4);
	uint16_t format = 1;
	append(&format, 2);
	uint16_t channels = 1;
	append(&channels, 2);
	append(&sampleRate, 4);
	uint32_t byteRate = sampleRate * 2;
	append(&byteRate, 4);
	uint16_t blockAlign = 2;
	append(&blockAlign, 2);
	uint16_t bitsPerSample = 16;
	append(&bitsPerSample, 2);
	append("data", 4);
	append(&dataSize, 4);
	append([NSMutableData dataWithLength:dataSize].bytes, dataSize);
	return data;
}

@interface VFLBackgroundKeeper ()

@property (nonatomic, strong, nullable) AVAudioPlayer *player;
@property (nonatomic, assign) BOOL active;

@end

@implementation VFLBackgroundKeeper

+ (VFLBackgroundKeeper *)shared {
	static VFLBackgroundKeeper *keeper = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		keeper = [[VFLBackgroundKeeper alloc] init];
	});
	return keeper;
}

- (void)start {
	if (self.active) {
		return;
	}
	NSError *error = nil;
	AVAudioSession *session = AVAudioSession.sharedInstance;
	if (![session setCategory:AVAudioSessionCategoryPlayback
				  withOptions:AVAudioSessionCategoryOptionMixWithOthers
						error:&error]) {
		NSLog(@"[VFL] 后台音频类别设置失败：%@", error);
	}
	if (![session setActive:YES error:&error]) {
		NSLog(@"[VFL] 后台音频激活失败：%@", error);
	}
	AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:VFLCreateSilentWave() error:&error];
	if (player == nil) {
		NSLog(@"[VFL] 静音播放器创建失败：%@", error);
		return;
	}
	player.numberOfLoops = -1;
	// 音量不能是 0：完全静音时系统可能回收音频会话。
	player.volume = 0.01;
	if (![player play]) {
		NSLog(@"[VFL] 静音播放器启动失败");
		return;
	}
	self.player = player;
	self.active = YES;
	NSLog(@"[VFL] 已开启后台保活，虚拟机可以继续跑");
}

- (void)stop {
	if (!self.active) {
		return;
	}
	[self.player stop];
	self.player = nil;
	[AVAudioSession.sharedInstance setActive:NO
							 withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
								   error:NULL];
	self.active = NO;
	NSLog(@"[VFL] 已关闭后台保活");
}

@end
