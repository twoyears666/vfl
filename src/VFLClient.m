// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLClient.h"

#import <string.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

#import "VFLVMDefinition.h"

@interface VFLClient ()
@property (nonatomic, assign) int fd;
@property (nonatomic, strong) NSMutableData *pending;
@property (nonatomic, strong) NSRecursiveLock *writeLock;
@property (nonatomic, assign) BOOL streaming;
@property (nonatomic, copy, readwrite) NSString *lastState;
@end

@implementation VFLClient

- (instancetype)init {
	self = [super init];
	if (self) {
		_fd = -1;
		_pending = [NSMutableData data];
		_writeLock = [[NSRecursiveLock alloc] init];
	}
	return self;
}

- (void)dealloc {
	[self close];
}

+ (instancetype)connectWithError:(NSError **)error {
	NSString *path = VFLSocketPath();
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:30
									userInfo:@{ NSLocalizedDescriptionKey: @"无法创建 socket" }];
		}
		return nil;
	}
	struct sockaddr_un address = { 0 };
	address.sun_family = AF_UNIX;
	strlcpy(address.sun_path, path.UTF8String, sizeof(address.sun_path));
	if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
		close(fd);
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:31
									userInfo:@{ NSLocalizedDescriptionKey: @"连不上 vfl 守护进程" }];
		}
		return nil;
	}
	VFLClient *client = [[VFLClient alloc] init];
	client.fd = fd;
	return client;
}

#pragma mark - 收发

- (BOOL)writeData:(NSData *)data {
	[_writeLock lock];
	BOOL ok = YES;
	const uint8_t *bytes = data.bytes;
	NSUInteger remaining = data.length;
	while (remaining > 0) {
		ssize_t written = write(self.fd, bytes, remaining);
		if (written <= 0) {
			ok = NO;
			break;
		}
		bytes += written;
		remaining -= (NSUInteger)written;
	}
	[_writeLock unlock];
	return ok;
}

/// 读一行 JSON。阻塞。
- (nullable NSDictionary *)readLineWithError:(NSError **)error {
	while (YES) {
		const uint8_t *bytes = self.pending.bytes;
		NSUInteger length = self.pending.length;
		for (NSUInteger index = 0; index < length; index++) {
			if (bytes[index] != '\n') {
				continue;
			}
			NSData *line = [self.pending subdataWithRange:NSMakeRange(0, index)];
			[self.pending replaceBytesInRange:NSMakeRange(0, index + 1) withBytes:NULL length:0];
			NSDictionary *object = line.length > 0
				? [NSJSONSerialization JSONObjectWithData:line options:0 error:NULL] : nil;
			return [object isKindOfClass:NSDictionary.class] ? object : @{};
		}
		uint8_t buffer[4096];
		ssize_t count = read(self.fd, buffer, sizeof(buffer));
		if (count <= 0) {
			if (error != NULL) {
				*error = [NSError errorWithDomain:@"vfl" code:32
										userInfo:@{ NSLocalizedDescriptionKey: @"连接被关闭" }];
			}
			return nil;
		}
		[self.pending appendBytes:buffer length:(NSUInteger)count];
	}
}

- (BOOL)sendJSON:(NSDictionary *)object {
	NSData *body = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
	if (body == nil) {
		return NO;
	}
	NSMutableData *line = [body mutableCopy];
	[line appendBytes:"\n" length:1];
	return [self writeData:line];
}

- (NSDictionary *)sendRequestWithCommand:(NSString *)command
									  vm:(NSString *)vm
								   error:(NSError **)error {
	NSMutableDictionary *request = [@{ @"cmd": command } mutableCopy];
	if (vm.length > 0) {
		request[@"vm"] = vm;
	}
	if (![self sendJSON:request]) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:33
									userInfo:@{ NSLocalizedDescriptionKey: @"发送命令失败" }];
		}
		return nil;
	}
	return [self readLineWithError:error];
}

#pragma mark - 控制台

- (BOOL)enterControlModeWithVM:(NSString *)name error:(NSError **)error {
	NSDictionary *response = [self sendRequestWithCommand:@"control" vm:name error:error];
	if (response == nil) {
		return NO;
	}
	if (![response[@"ok"] boolValue]) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:34
									userInfo:@{ NSLocalizedDescriptionKey:
													response[@"error"] ?: @"无法进入控制台" }];
		}
		return NO;
	}
	self.streaming = YES;
	self.lastState = response[@"state"] ?: @"";
	// 后台线程持续读事件（console/state），调用方继续处理自己的输入。
	NSThread *thread = [[NSThread alloc] initWithBlock:^{
		[self runEventLoop];
	}];
	thread.name = @"vfl.console";
	[thread start];
	return YES;
}

- (void)runEventLoop {
	while (self.streaming) {
		NSError *error = nil;
		NSDictionary *event = [self readLineWithError:&error];
		if (event == nil) {
			break;
		}
		void (^handler)(NSDictionary *) = self.eventHandler;
		if (handler != nil) {
			handler(event);
		}
	}
}

- (void)sendConsoleInput:(NSData *)data {
	if (data.length == 0) {
		return;
	}
	[self sendJSON:@{ @"event": @"stdin", @"data": [data base64EncodedStringWithOptions:0] }];
}

- (void)detach {
	if (self.streaming) {
		self.streaming = NO;
		[self sendJSON:@{ @"cmd": @"detach" }];
	}
}

- (void)close {
	self.streaming = NO;
	[_writeLock lock];
	if (self.fd >= 0) {
		close(self.fd);
		self.fd = -1;
	}
	[_writeLock unlock];
}

@end
