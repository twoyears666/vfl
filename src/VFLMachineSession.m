// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLMachineSession.h"

#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>

#import "VFLVirtualization.h"

static const NSUInteger VFLConsoleBufferLimit = 256 * 1024;

NSString *VFLMachineStateText(VFLMachineState state) {
	switch (state) {
		case VFLMachineStateStopped: return @"stopped";
		case VFLMachineStateStarting: return @"starting";
		case VFLMachineStateRunning: return @"running";
		case VFLMachineStateStopping: return @"stopping";
		case VFLMachineStateError: return @"error";
	}
	return @"unknown";
}

@implementation VFLMachineSession {
	VZVirtualMachine *_machine;
	NSFileHandle *_consoleReader;
	int _consoleWriteFD;
	dispatch_queue_t _consoleQueue;
	dispatch_source_t _consoleSource;

	NSMutableData *_consoleBuffer;
	NSMutableArray<id<VFLSessionObserver>> *_observers;
	NSRecursiveLock *_lock;
	dispatch_source_t _stateTimer;

	VFLMachineState _state;
	NSString *_lastMessage;
}

- (instancetype)initWithDefinition:(VFLVMDefinition *)definition {
	self = [super init];
	if (self) {
		_definition = definition;
		_consoleBuffer = [NSMutableData data];
		_observers = [NSMutableArray array];
		_lock = [[NSRecursiveLock alloc] init];
		_consoleQueue = dispatch_queue_create("com.vfl.console", DISPATCH_QUEUE_SERIAL);
		_consoleWriteFD = -1;
		_state = VFLMachineStateStopped;
		_lastMessage = @"已停止";
	}
	return self;
}

- (void)dealloc {
	if (_stateTimer != nil) {
		dispatch_source_cancel(_stateTimer);
		_stateTimer = nil;
	}
	[self closeConsolePipes];
	[_machine stopWithCompletionHandler:^(NSError *error) {}];
}

#pragma mark - 只读属性

- (VFLMachineState)state {
	[_lock lock];
	VFLMachineState state = _state;
	[_lock unlock];
	return state;
}

- (NSString *)lastMessage {
	[_lock lock];
	NSString *message = [_lastMessage copy];
	[_lock unlock];
	return message;
}

- (BOOL)isActive {
	VFLMachineState state = self.state;
	return state == VFLMachineStateStarting || state == VFLMachineStateRunning
		|| state == VFLMachineStateStopping;
}

- (id)virtualMachine {
	return _machine;
}

#pragma mark - 观察者

- (void)addObserver:(id<VFLSessionObserver>)observer {
	if (observer == nil) {
		return;
	}
	[_lock lock];
	if (![_observers containsObject:observer]) {
		[_observers addObject:observer];
	}
	[_lock unlock];
}

- (void)removeObserver:(id<VFLSessionObserver>)observer {
	[_lock lock];
	[_observers removeObject:observer];
	[_lock unlock];
}

- (NSArray<id<VFLSessionObserver>> *)observerSnapshot {
	[_lock lock];
	NSArray *copy = [_observers copy];
	[_lock unlock];
	return copy;
}

#pragma mark - 状态

- (void)setState:(VFLMachineState)state message:(NSString *)message {
	[_lock lock];
	_state = state;
	_lastMessage = [message copy];
	NSArray *observers = [_observers copy];
	[_lock unlock];
	NSLog(@"[VFL] %@ 状态 %@：%@", self.definition.name, VFLMachineStateText(state), message);
	for (id<VFLSessionObserver> observer in observers) {
		[observer session:self didChangeState:state message:message];
	}
}

#pragma mark - 控制台

- (void)appendConsoleData:(NSData *)data {
	if (data.length == 0) {
		return;
	}
	NSArray *observers = nil;
	[_lock lock];
	[_consoleBuffer appendData:data];
	if (_consoleBuffer.length > VFLConsoleBufferLimit) {
		NSUInteger excess = _consoleBuffer.length - VFLConsoleBufferLimit;
		[_consoleBuffer replaceBytesInRange:NSMakeRange(0, excess) withBytes:NULL length:0];
	}
	observers = [_observers copy];
	[_lock unlock];

	for (id<VFLSessionObserver> observer in observers) {
		[observer session:self didOutputConsoleData:data];
	}
}

- (NSData *)consoleSnapshot {
	[_lock lock];
	NSData *snapshot = [_consoleBuffer copy];
	[_lock unlock];
	return snapshot;
}

- (void)sendConsoleInput:(NSData *)data {
	if (data.length == 0 || _consoleWriteFD < 0) {
		return;
	}
	NSData *payload = [data copy];
	dispatch_async(_consoleQueue, ^{
		const uint8_t *bytes = payload.bytes;
		NSUInteger remaining = payload.length;
		while (remaining > 0) {
			ssize_t written = write(self->_consoleWriteFD, bytes, remaining);
			if (written > 0) {
				bytes += written;
				remaining -= (NSUInteger)written;
				continue;
			}
			if (errno == EAGAIN || errno == EWOULDBLOCK) {
				// 客户机暂时没读，直接丢掉这一批，绝不阻塞调用方（渲染/按键）。
				NSLog(@"[VFL] 串口输入缓冲满，丢弃 %lu 字节", (unsigned long)remaining);
				return;
			}
			NSLog(@"[VFL] 串口写入失败：%s", strerror(errno));
			return;
		}
	});
}

- (void)closeConsolePipes {
	[_lock lock];
	if (_consoleSource != nil) {
		dispatch_source_cancel(_consoleSource);
		_consoleSource = nil;
	}
	if (_consoleReader != nil) {
		[_consoleReader closeFile];
		_consoleReader = nil;
	}
	if (_consoleWriteFD >= 0) {
		close(_consoleWriteFD);
		_consoleWriteFD = -1;
	}
	[_lock unlock];
}

#pragma mark - 启动

- (BOOL)startWithError:(NSError **)error {
	NSString *diagnostic = nil;
	if (!VFLVirtualizationPrepare(&diagnostic)) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:10
									userInfo:@{ NSLocalizedDescriptionKey: diagnostic ?: @"Virtualization 不可用" }];
		}
		return NO;
	}
	if (self.isActive) {
		return YES;
	}

	VFLVMDefinition *definition = self.definition;
	if (![NSFileManager.defaultManager fileExistsAtPath:definition.kernelPath]) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:11
									userInfo:@{ NSLocalizedDescriptionKey:
													[NSString stringWithFormat:@"内核不存在：%@", definition.kernelPath] }];
		}
		return NO;
	}

	[self setState:VFLMachineStateStarting message:@"创建虚拟硬件…"];

	// 上一轮跑过的管道与旧画面都要清掉，否则重启会读到残留输出。
	[self closeConsolePipes];
	[_lock lock];
	[_consoleBuffer setLength:0];
	[_lock unlock];

	VZVirtualMachineConfiguration *configuration = VFLNewInstance(VZVirtualMachineConfiguration);
	configuration.CPUCount = MAX((NSUInteger)1, definition.cpuCount);
	configuration.memorySize = MAX((unsigned long long)512, definition.memoryMB) * 1024ULL * 1024ULL;

	VZLinuxBootLoader *loader = [(VZLinuxBootLoader *)VFLAlloc(@"VZLinuxBootLoader")
								 initWithKernelURL:[NSURL fileURLWithPath:definition.kernelPath]];
	loader.commandLine = [definition effectiveCommandLine];
	if (definition.initrdPath.length > 0) {
		loader.initialRamdiskURL = [NSURL fileURLWithPath:definition.initrdPath];
	}
	configuration.bootLoader = @[ loader ];

	// 串口：hostToGuest 让客户机读，guestToHost 让客户机写。
	int hostToGuest[2] = { -1, -1 };
	int guestToHost[2] = { -1, -1 };
	if (pipe(hostToGuest) != 0 || pipe(guestToHost) != 0) {
		[self setState:VFLMachineStateError message:@"串口管道创建失败"];
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:12
									userInfo:@{ NSLocalizedDescriptionKey: @"串口管道创建失败" }];
		}
		return NO;
	}
	fcntl(hostToGuest[1], F_SETFL, O_NONBLOCK);
	[_lock lock];
	_consoleWriteFD = hostToGuest[1];
	[_lock unlock];

	NSFileHandle *reading = [[NSFileHandle alloc] initWithFileDescriptor:hostToGuest[0] closeOnDealloc:YES];
	NSFileHandle *writing = [[NSFileHandle alloc] initWithFileDescriptor:guestToHost[1] closeOnDealloc:YES];
	VZFileHandleSerialPortAttachment *attachment =
		[(VZFileHandleSerialPortAttachment *)VFLAlloc(@"VZFileHandleSerialPortAttachment")
		 initWithFileHandleForReading:reading
				 fileHandleForWriting:writing];
	VZVirtioConsoleDeviceSerialPortConfiguration *serialPort =
		VFLNewInstance(VZVirtioConsoleDeviceSerialPortConfiguration);
	serialPort.attachment = attachment;
	configuration.serialPorts = @[ serialPort ];

	NSMutableArray *storage = [NSMutableArray array];
	NSArray<NSNumber *> *readOnly = definition.readOnlyDisks;
	NSUInteger diskIndex = 0;
	for (NSString *path in definition.diskPaths) {
		if (path.length == 0) {
			diskIndex++;
			continue;
		}
		BOOL isReadOnly = [readOnly containsObject:@(diskIndex)];
		NSError *diskError = nil;
		VZDiskImageStorageDeviceAttachment *disk =
			[(VZDiskImageStorageDeviceAttachment *)VFLAlloc(@"VZDiskImageStorageDeviceAttachment")
			 initWithURL:[NSURL fileURLWithPath:path]
				readOnly:isReadOnly
				   error:&diskError];
		if (disk == nil) {
			NSLog(@"[VFL] 磁盘打开失败 %@：%@", path, diskError.localizedDescription);
			diskIndex++;
			continue;
		}
		VZVirtioBlockDeviceConfiguration *block =
			[(VZVirtioBlockDeviceConfiguration *)VFLAlloc(@"VZVirtioBlockDeviceConfiguration")
			 initWithAttachment:disk];
		[storage addObject:block];
		diskIndex++;
	}
	configuration.storageDevices = storage;

	if (definition.networkEnabled) {
		VZVirtioNetworkDeviceConfiguration *network = VFLNewInstance(VZVirtioNetworkDeviceConfiguration);
		network.attachment = VFLNewInstance(VZNATNetworkDeviceAttachment);
		// 用户填了 MAC 就固定下来，否则留给系统随机生成。
		if (definition.macAddress.length > 0 && NSClassFromString(@"VZMACAddress") != nil) {
			VZMACAddress *address = [(VZMACAddress *)VFLAlloc(@"VZMACAddress")
									 initWithString:definition.macAddress];
			if (address != nil) {
				network.MACAddress = address;
			}
		}
		configuration.networkDevices = @[ network ];
	}

	configuration.entropyDevices = @[ VFLNewInstance(VZVirtioEntropyDeviceConfiguration) ];

	// 多显示设备：只有系统里真的有 virtio-gpu 类时才配，缺类就跳过（iPadOS 上通常没有）。
	if (definition.displayCount > 0
		&& NSClassFromString(@"VZVirtioGraphicsDeviceConfiguration") != nil
		&& NSClassFromString(@"VZVirtioGraphicsScanoutConfiguration") != nil) {
		NSMutableArray *scanouts = [NSMutableArray array];
		for (NSUInteger index = 0; index < definition.displayCount; index++) {
			id scanout = [[NSClassFromString(@"VZVirtioGraphicsScanoutConfiguration") alloc]
						  initWithWidthInPixels:1280 heightInPixels:800];
			if (scanout != nil) {
				[scanouts addObject:scanout];
			}
		}
		if (scanouts.count > 0) {
			VZVirtioGraphicsDeviceConfiguration *graphics =
				VFLNewInstance(VZVirtioGraphicsDeviceConfiguration);
			graphics.scanouts = scanouts;
			configuration.graphicsDevices = @[ graphics ];
		}
	}

	NSError *validationError = nil;
	if (![configuration validateWithError:&validationError]) {
		[self closeConsolePipes];
		[self setState:VFLMachineStateError message:validationError.localizedDescription ?: @"配置校验失败"];
		if (error != NULL) {
			*error = validationError;
		}
		return NO;
	}

	// 私有框架不能静态链接，必须运行时取类，否则 ld 找不到 _OBJC_CLASS_$_VZVirtualMachine。
	_machine = [(VZVirtualMachine *)VFLAlloc(@"VZVirtualMachine")
				initWithConfiguration:configuration];
	[self startConsoleReaderWithDescriptor:guestToHost[0]];
	[self startStatePolling];

	__weak typeof(self) weakSelf = self;
	[_machine startWithCompletionHandler:^(NSError *startError) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		if (startError != nil) {
			[strongSelf setState:VFLMachineStateError message:startError.localizedDescription ?: @"启动失败"];
			return;
		}
		[strongSelf setState:VFLMachineStateRunning message:@"客户机运行中"];
	}];
	return YES;
}

/// 客户机自己关机时 VZ 不会通知我们（iOS 上没有 delegate 头文件），轮询 state 兜底。
- (void)startStatePolling {
	if (_stateTimer != nil) {
		return;
	}
	_stateTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _consoleQueue);
	dispatch_source_set_timer(_stateTimer,
							  dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
							  NSEC_PER_SEC,
							  100 * NSEC_PER_MSEC);
	__weak typeof(self) weakSelf = self;
	dispatch_source_set_event_handler(_stateTimer, ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		VZVirtualMachine *machine = strongSelf->_machine;
		if (machine == nil) {
			return;
		}
		if (strongSelf.state == VFLMachineStateRunning
			&& machine.state == VZVirtualMachineStateStopped) {
			[strongSelf closeConsolePipes];
			[strongSelf setState:VFLMachineStateStopped message:@"客户机已关机"];
		}
	});
	dispatch_resume(_stateTimer);
}

- (void)startConsoleReaderWithDescriptor:(int)descriptor {	_consoleReader = [[NSFileHandle alloc] initWithFileDescriptor:descriptor closeOnDealloc:YES];
	int fd = descriptor;
	dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, _consoleQueue);
	__weak typeof(self) weakSelf = self;
	dispatch_source_set_event_handler(source, ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		uint8_t buffer[4096];
		ssize_t count = read(fd, buffer, sizeof(buffer));
		if (count > 0) {
			[strongSelf appendConsoleData:[NSData dataWithBytes:buffer length:(NSUInteger)count]];
		}
	});
	dispatch_resume(source);
	_consoleSource = source;
}

#pragma mark - 停止

- (void)requestShutdown {
	if (_machine == nil || self.state != VFLMachineStateRunning) {
		return;
	}
	[self setState:VFLMachineStateStopping message:@"正在关机…"];
	NSError *error = nil;
	if (![_machine requestStopWithError:&error]) {
		[self setState:VFLMachineStateRunning message:error.localizedDescription ?: @"关机请求失败"];
	}
}

- (void)forceStop {
	if (_machine == nil) {
		return;
	}
	[self setState:VFLMachineStateStopping message:@"强制关机…"];
	__weak typeof(self) weakSelf = self;
	[_machine stopWithCompletionHandler:^(NSError *error) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		if (error != nil) {
			[strongSelf setState:VFLMachineStateError message:error.localizedDescription ?: @"强制关机失败"];
			return;
		}
		[strongSelf setState:VFLMachineStateStopped message:@"已停止"];
	}];
}

@end
