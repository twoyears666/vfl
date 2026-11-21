// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLServer.h"

#import <fcntl.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <unistd.h>

#import "VFLVMDefinition.h"

/// 一条客户端连接。所有读都发生在 socket 队列上，写走自己的串行队列。
@interface VFLServerConnection : NSObject <VFLSessionObserver>
@property (nonatomic, assign) int fd;
@property (nonatomic, strong) NSMutableData *pending;
@property (nonatomic, strong) dispatch_queue_t writeQueue;
@property (nonatomic, strong) dispatch_source_t readSource;
@property (nonatomic, strong, nullable) VFLMachineSession *attachedSession;
@property (nonatomic, weak, nullable) VFLServer *server;
- (void)sendJSON:(NSDictionary *)object;
- (void)sendConsoleData:(NSData *)data;
- (void)readAvailableData;
- (void)close;
@end

@interface VFLServer ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, VFLMachineSession *> *sessionsByName;
/// 客户端连接要由服务端持有，否则 accept 返回后连接对象立刻被释放。
@property (nonatomic, strong) NSMutableArray<VFLServerConnection *> *connections;
@property (nonatomic, strong) NSRecursiveLock *lock;
@property (nonatomic, assign) int listenFD;
@property (nonatomic, strong, nullable) dispatch_source_t listenSource;
- (void)handleRequest:(NSDictionary *)request connection:(VFLServerConnection *)connection;
- (void)acceptPendingConnections;
- (void)removeConnection:(VFLServerConnection *)connection;
@end

@implementation VFLServer

- (instancetype)init {
	self = [super init];
	if (self) {
		_sessionsByName = [NSMutableDictionary dictionary];
		_connections = [NSMutableArray array];
		_lock = [[NSRecursiveLock alloc] init];
		_listenFD = -1;
	}
	return self;
}

- (void)removeConnection:(VFLServerConnection *)connection {
	if (connection == nil) {
		return;
	}
	[_lock lock];
	[self.connections removeObjectIdenticalTo:connection];
	[_lock unlock];
}

- (NSArray<VFLMachineSession *> *)sessions {
	[_lock lock];
	NSArray *all = self.sessionsByName.allValues;
	[_lock unlock];
	return [all sortedArrayUsingComparator:^NSComparisonResult(VFLMachineSession *a, VFLMachineSession *b) {
		return [a.definition.name localizedStandardCompare:b.definition.name];
	}];
}

- (VFLMachineSession *)sessionNamed:(NSString *)name {
	[_lock lock];
	VFLMachineSession *session = self.sessionsByName[name];
	[_lock unlock];
	return session;
}

- (VFLMachineSession *)ensureSessionForDefinitionName:(NSString *)name error:(NSError **)error {
	[_lock lock];
	VFLMachineSession *existing = self.sessionsByName[name];
	if (existing != nil) {
		[_lock unlock];
		return existing;
	}
	VFLVMDefinition *definition = [[[VFLVMStore alloc] init] definitionNamed:name];
	if (definition == nil) {
		[_lock unlock];
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:20
									userInfo:@{ NSLocalizedDescriptionKey:
													[NSString stringWithFormat:@"没有名为 %@ 的虚拟机", name] }];
		}
		return nil;
	}
	existing = [[VFLMachineSession alloc] initWithDefinition:definition];
	self.sessionsByName[name] = existing;
	[_lock unlock];
	return existing;
}

- (void)discardStoppedSessionNamed:(NSString *)name {
	if (name.length == 0) {
		return;
	}
	[_lock lock];
	VFLMachineSession *session = self.sessionsByName[name];
	if (session != nil && !session.isActive) {
		[self.sessionsByName removeObjectForKey:name];
	}
	[_lock unlock];
}

#pragma mark - 监听

- (BOOL)startWithError:(NSError **)error {
	NSString *directory = VFLRunDirectory();
	[NSFileManager.defaultManager createDirectoryAtPath:directory
						   withIntermediateDirectories:YES
											attributes:nil
												 error:NULL];

	NSString *path = VFLSocketPath();
	unlink(path.UTF8String);

	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:21
									userInfo:@{ NSLocalizedDescriptionKey: @"无法创建 socket" }];
		}
		return NO;
	}

	struct sockaddr_un address = { 0 };
	address.sun_family = AF_UNIX;
	strlcpy(address.sun_path, path.UTF8String, sizeof(address.sun_path));
	if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
		close(fd);
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:22
									userInfo:@{ NSLocalizedDescriptionKey:
													[NSString stringWithFormat:@"无法绑定 %@", path] }];
		}
		return NO;
	}
	// GUI 以 mobile 身份连、CLI 可能以 root 身份连，权限放开到所有用户。
	chmod(path.UTF8String, 0666);
	if (listen(fd, 8) != 0) {
		close(fd);
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:23
									userInfo:@{ NSLocalizedDescriptionKey: @"listen 失败" }];
		}
		return NO;
	}
	// accept 不能阻塞，否则读事件触发后会把整个队列挂住。
	fcntl(fd, F_SETFL, O_NONBLOCK);
	_listenFD = fd;
	__weak typeof(self) weakSelf = self;
	dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0,
													 dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
	dispatch_source_set_event_handler(source, ^{
		[weakSelf acceptPendingConnections];
	});
	dispatch_resume(source);
	_listenSource = source;
	NSLog(@"[VFL] 服务端已监听 %@", path);
	return YES;
}

- (void)stop {
	if (_listenSource != nil) {
		dispatch_source_cancel(_listenSource);
		_listenSource = nil;
	}
	if (_listenFD >= 0) {
		close(_listenFD);
		_listenFD = -1;
	}
	unlink(VFLSocketPath().UTF8String);
}

- (void)acceptPendingConnections {
	while (YES) {
		int client = accept(_listenFD, NULL, NULL);
		if (client < 0) {
			return;
		}
		VFLServerConnection *connection = [[VFLServerConnection alloc] init];
		connection.fd = client;
		connection.pending = [NSMutableData data];
		connection.writeQueue = dispatch_queue_create("com.vfl.connection.write", DISPATCH_QUEUE_SERIAL);
		connection.server = self;

		dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)client, 0,
														  dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
		__weak VFLServerConnection *weakConnection = connection;
		dispatch_source_set_event_handler(source, ^{
			[weakConnection readAvailableData];
		});
		dispatch_source_set_cancel_handler(source, ^{
			[weakConnection close];
		});
		connection.readSource = source;
		[_lock lock];
		[self.connections addObject:connection];
		[_lock unlock];
		dispatch_resume(source);
	}
}

#pragma mark - 命令分发

- (void)handleRequest:(NSDictionary *)request connection:(VFLServerConnection *)connection {
	NSString *command = request[@"cmd"];
	NSString *name = request[@"vm"];

	if ([command isEqualToString:@"list"]) {
		NSMutableArray *items = [NSMutableArray array];
		for (VFLVMDefinition *definition in [[[VFLVMStore alloc] init] definitions]) {
			VFLMachineSession *session = [self sessionNamed:definition.name];
			[items addObject:@{
				@"name": definition.name,
				@"state": session != nil ? VFLMachineStateText(session.state) : @"stopped",
				@"memoryMB": @(definition.memoryMB),
				@"cpuCount": @(definition.cpuCount),
				@"displays": @(definition.displayCount),
			}];
		}
		[connection sendJSON:@{ @"ok": @YES, @"vms": items }];
		return;
	}

	if ([command isEqualToString:@"start"] || [command isEqualToString:@"control"]
		|| [command isEqualToString:@"shutdown"] || [command isEqualToString:@"kill"]) {
		// 启动前丢掉已停止的旧会话，让磁盘 / 内存等定义改动真正生效。
		if ([command isEqualToString:@"start"]) {
			[self discardStoppedSessionNamed:name];
		}
		NSError *error = nil;
		VFLMachineSession *session = [self ensureSessionForDefinitionName:name error:&error];
		if (session == nil) {
			[connection sendJSON:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"找不到虚拟机" }];
			return;
		}

		if ([command isEqualToString:@"start"]) {
			if (![session startWithError:&error]) {
				[connection sendJSON:@{ @"ok": @NO, @"error": error.localizedDescription ?: @"启动失败" }];
				return;
			}
			// 成功启动才累加，GUI 用这个次数判断是否该问「删掉安装镜像」。
			VFLVMStore *store = [[VFLVMStore alloc] init];
			VFLVMDefinition *definition = [store definitionNamed:name];
			if (definition != nil) {
				definition.bootCount += 1;
				[store saveDefinition:definition error:NULL];
			}
			[connection sendJSON:@{ @"ok": @YES, @"state": VFLMachineStateText(session.state) }];
			return;
		}

		if ([command isEqualToString:@"shutdown"]) {
			[session requestShutdown];
			[connection sendJSON:@{ @"ok": @YES }];
			return;
		}

		if ([command isEqualToString:@"kill"]) {
			[session forceStop];
			[connection sendJSON:@{ @"ok": @YES }];
			return;
		}

		// control：先回 ok，再把历史输出与后续输出都推给这条连接。
		[session addObserver:connection];
		connection.attachedSession = session;
		[connection sendJSON:@{ @"ok": @YES,
								@"state": VFLMachineStateText(session.state),
								@"message": session.lastMessage ?: @"" }];
		[connection sendConsoleData:[session consoleSnapshot]];
		return;
	}

	if ([command isEqualToString:@"detach"]) {
		[connection.attachedSession removeObserver:connection];
		connection.attachedSession = nil;
		[connection sendJSON:@{ @"ok": @YES }];
		return;
	}

	[connection sendJSON:@{ @"ok": @NO, @"error": [NSString stringWithFormat:@"未知命令 %@", command ?: @""] }];
}

@end

#pragma mark - 连接

@implementation VFLServerConnection

- (void)dealloc {
	[_attachedSession removeObserver:self];
}

- (void)readAvailableData {
	uint8_t buffer[4096];
	ssize_t count = read(self.fd, buffer, sizeof(buffer));
	if (count <= 0) {
		if (self.readSource != nil) {
			dispatch_source_cancel(self.readSource);
		}
		return;
	}
	[self.pending appendBytes:buffer length:(NSUInteger)count];

	// 协议是「一行一个 JSON」，粘包在这里拆。
	while (YES) {
		const uint8_t *bytes = self.pending.bytes;
		NSUInteger length = self.pending.length;
		NSUInteger newline = NSNotFound;
		for (NSUInteger index = 0; index < length; index++) {
			if (bytes[index] == '\n') {
				newline = index;
				break;
			}
		}
		if (newline == NSNotFound) {
			break;
		}
		NSData *line = [self.pending subdataWithRange:NSMakeRange(0, newline)];
		[self.pending replaceBytesInRange:NSMakeRange(0, newline + 1) withBytes:NULL length:0];

		NSDictionary *request = line.length > 0
			? [NSJSONSerialization JSONObjectWithData:line options:0 error:NULL] : nil;
		if (![request isKindOfClass:NSDictionary.class]) {
			continue;
		}
		if ([request[@"event"] isEqualToString:@"stdin"] && self.attachedSession != nil) {
			NSString *encoded = request[@"data"];
			NSData *payload = encoded != nil ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
			[self.attachedSession sendConsoleInput:payload ?: [NSData data]];
			continue;
		}
		[self.server handleRequest:request connection:self];
	}
}

- (void)sendJSON:(NSDictionary *)object {
	NSData *body = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL];
	if (body == nil) {
		return;
	}
	NSMutableData *line = [body mutableCopy];
	[line appendBytes:"\n" length:1];
	[self enqueueData:line];
}

- (void)sendConsoleData:(NSData *)data {
	if (data.length == 0) {
		return;
	}
	NSDictionary *event = @{ @"event": @"console",
							 @"data": [data base64EncodedStringWithOptions:0] };
	[self sendJSON:event];
}

- (void)enqueueData:(NSData *)data {
	int fd = self.fd;
	dispatch_queue_t queue = self.writeQueue;
	if (fd < 0 || queue == nil) {
		return;
	}
	dispatch_async(queue, ^{
		const uint8_t *bytes = data.bytes;
		NSUInteger remaining = data.length;
		while (remaining > 0) {
			ssize_t written = write(fd, bytes, remaining);
			if (written <= 0) {
				return;
			}
			bytes += written;
			remaining -= (NSUInteger)written;
		}
	});
}

- (void)close {
	if (self.readSource != nil) {
		dispatch_source_cancel(self.readSource);
		self.readSource = nil;
	}
	[self.attachedSession removeObserver:self];
	self.attachedSession = nil;
	if (self.fd >= 0) {
		close(self.fd);
		self.fd = -1;
	}
	// 最后再从服务端摘掉自己：这一步可能把最后一个强引用释放掉。
	[self.server removeConnection:self];
}

#pragma mark - VFLSessionObserver

- (void)session:(VFLMachineSession *)session didChangeState:(VFLMachineState)state message:(NSString *)message {
	[self sendJSON:@{ @"event": @"state",
					  @"state": VFLMachineStateText(state),
					  @"message": message ?: @"" }];
}

- (void)session:(VFLMachineSession *)session didOutputConsoleData:(NSData *)data {
	[self sendConsoleData:data];
}

@end
