// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLMachineSession.h"

#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>

#import "VFLVirtualization.h"
#import "VFLVMDefinition.h"

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
	// 不在这里碰 VZ：dealloc 可能发生在任意队列，而 VZ 只接受主队列调用。
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

/// 只读文件尾部，避免把几十 MB 的 VMM 日志全塞进 app.log。
static NSString *VFLLogTail(NSString *path, NSUInteger limit) {
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (data.length == 0) {
		return @"(没有内容)";
	}
	if (data.length > limit) {
		data = [data subdataWithRange:NSMakeRange(data.length - limit, limit)];
	}
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"(无法解码)";
}

/// 启动卡住时把 VMM 侧日志带进 app.log，省得再去翻 /tmp。
- (void)logVMCompositeLaunchDetail {
	NSLog(@"[VFL] 启动 20 秒仍未完成，导出 VMM 侧日志");
	NSArray<NSString *> *paths = @[
		@"/tmp/vzxpchook.log",
		@"/tmp/vmmhook.log",
		[VFLDataDirectory() stringByAppendingPathComponent:@"vmm.stderr.log"],
	];
	for (NSString *path in paths) {
		NSLog(@"[VFL] %@:\n%@", path, VFLLogTail(path, 4096));
	}
}

- (BOOL)startWithError:(NSError **)error {
	NSString *diagnostic = nil;
	NSLog(@"[VFL] 启动 %@：准备 VZ 运行时", self.definition.name);
	if (!VFLVirtualizationPrepare(&diagnostic)) {
		NSLog(@"[VFL] VZ 运行时就绪失败：%@", diagnostic);
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

	[self setState:VFLMachineStateStarting message:@"创建虚拟硬件…"];

	// 上一轮跑过的管道与旧画面都要清掉，否则重启会读到残留输出。
	[self closeConsolePipes];
	[_lock lock];
	[_consoleBuffer setLength:0];
	[_lock unlock];

	VZVirtualMachineConfiguration *configuration = VFLNewInstance(VZVirtualMachineConfiguration);
	configuration.CPUCount = MAX((NSUInteger)1, definition.cpuCount);
	configuration.memorySize = MAX((unsigned long long)512, definition.memoryMB) * 1024ULL * 1024ULL;

	// EFI 模式由固件自己找 ISO / 系统盘上的 EFI 引导器：安装阶段从 ISO 起，
	// 装完删掉 ISO 后直接从系统盘起，不需要 host 上有内核文件。
	id bootLoader = nil;
	if (definition.bootMode == VFLBootModeEFI) {
		Class storeClass = NSClassFromString(@"VZEFIVariableStore");
		Class efiLoaderClass = NSClassFromString(@"VZEFIBootLoader");
		if (storeClass == Nil || efiLoaderClass == Nil) {
			[self setState:VFLMachineStateError message:@"这套 Virtualization 不支持 EFI"];
			if (error != NULL) {
				*error = [NSError errorWithDomain:@"vfl" code:13
										userInfo:@{ NSLocalizedDescriptionKey:
														@"这套 Virtualization 框架没有 EFI 引导类" }];
			}
			return NO;
		}
		[NSFileManager.defaultManager createDirectoryAtPath:VFLEFIDirectory()
							   withIntermediateDirectories:YES
												attributes:nil
													 error:NULL];
		NSString *storePath = definition.efiVariableStorePath;
		NSURL *storeURL = [NSURL fileURLWithPath:storePath];
		NSError *storeError = nil;
		VZEFIVariableStore *store = nil;
		if ([NSFileManager.defaultManager fileExistsAtPath:storePath]) {
			store = [(VZEFIVariableStore *)[storeClass alloc] initWithURL:storeURL];
		} else {
			store = [(VZEFIVariableStore *)[storeClass alloc]
					 initCreatingVariableStoreAtURL:storeURL
										   options:0
											 error:&storeError];
		}
		if (store == nil) {
			[self setState:VFLMachineStateError message:storeError.localizedDescription ?: @"EFI 变量存储创建失败"];
			if (error != NULL) {
				*error = storeError ?: [NSError errorWithDomain:@"vfl" code:14
													 userInfo:@{ NSLocalizedDescriptionKey:
																	 @"EFI 变量存储创建失败" }];
			}
			return NO;
		}
		VZEFIBootLoader *efiLoader = [(VZEFIBootLoader *)[efiLoaderClass alloc] init];
		efiLoader.variableStore = store;
		// VMM 里 EFI 固件路径写死成 /System/.../Virtualization.framework/.../VZG21.fd，
		// iPad 上没有这个文件（日志里的 FATAL: Failed to open EFI ROM）。
		// VZEFIBootLoader 有私有 _ROMImageURL，塞进去后框架会把它当 fd 传给 VMM。
		NSURL *romURL = VFLVirtualizationEFIROMURL();
		SEL romSelector = NSSelectorFromString(@"_setROMImageURL:");
		if (romURL != nil && [efiLoader respondsToSelector:romSelector]) {
			typedef void (*VFLSetROMFunction)(id, SEL, NSURL *);
			VFLSetROMFunction setROM = (VFLSetROMFunction)[efiLoader methodForSelector:romSelector];
			setROM(efiLoader, romSelector, romURL);
			NSLog(@"[VFL] 使用自带 EFI 固件：%@", romURL.path);
		} else {
			NSLog(@"[VFL] 没有可用的自带 EFI 固件，固件大概率会启动失败");
		}
		bootLoader = efiLoader;
	} else {
		if (![NSFileManager.defaultManager fileExistsAtPath:definition.kernelPath]) {
			if (error != NULL) {
				*error = [NSError errorWithDomain:@"vfl" code:11
										userInfo:@{ NSLocalizedDescriptionKey:
														[NSString stringWithFormat:@"内核不存在：%@", definition.kernelPath] }];
			}
			return NO;
		}
		VZLinuxBootLoader *loader = [(VZLinuxBootLoader *)VFLAlloc(@"VZLinuxBootLoader")
									 initWithKernelURL:[NSURL fileURLWithPath:definition.kernelPath]];
		loader.commandLine = [definition effectiveCommandLine];
		if (definition.initrdPath.length > 0) {
			loader.initialRamdiskURL = [NSURL fileURLWithPath:definition.initrdPath];
		}
		bootLoader = loader;
	}
	configuration.bootLoader = bootLoader;

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
		NSLog(@"[VFL] 配置校验失败：%@", validationError);
		[self closeConsolePipes];
		[self setState:VFLMachineStateError message:validationError.localizedDescription ?: @"配置校验失败"];
		if (error != NULL) {
			*error = validationError;
		}
		return NO;
	}

	// 私有框架不能静态链接，必须运行时取类，否则 ld 找不到 _OBJC_CLASS_$_VZVirtualMachine。
	[self startConsoleReaderWithDescriptor:guestToHost[0]];

	// VZ 规定所有调用都必须在虚拟机创建时所在的队列上（默认主队列）。
	// 之前在 dispatch 全局队列里调 start，Virtualization 内部的
	// dispatch_assert_queue 直接抛 SIGTRAP——这就是“到 EFI 就没日志”的原因。
	__weak typeof(self) weakSelf = self;
	__block BOOL startFailed = NO;
	void (^beginStart)(void) = ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		strongSelf->_machine = [(VZVirtualMachine *)VFLAlloc(@"VZVirtualMachine")
					initWithConfiguration:configuration];
		[strongSelf startStatePolling];
		NSLog(@"[VFL] 开始启动（%@ 模式）",
			  strongSelf.definition.bootMode == VFLBootModeEFI ? @"EFI" : @"内核");
		@try {
			[strongSelf->_machine startWithCompletionHandler:^(NSError *startError) {
				typeof(self) insideSelf = weakSelf;
				if (insideSelf == nil) {
					return;
				}
				if (startError != nil) {
					NSLog(@"[VFL] 启动失败：%@", startError);
					[insideSelf setState:VFLMachineStateError
								 message:startError.localizedDescription ?: @"启动失败"];
					return;
				}
				[insideSelf setState:VFLMachineStateRunning message:@"客户机运行中"];
			}];
		} @catch (NSException *exception) {
			NSLog(@"[VFL] 启动异常：%@", exception);
			startFailed = YES;
			[strongSelf closeConsolePipes];
			[strongSelf setState:VFLMachineStateError message:exception.reason ?: @"启动异常"];
		}
	};
	if (NSThread.isMainThread) {
		beginStart();
	} else {
		dispatch_sync(dispatch_get_main_queue(), beginStart);
	}
	if (startFailed) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:@"vfl" code:11
									userInfo:@{ NSLocalizedDescriptionKey: @"启动异常" }];
		}
		return NO;
	}
	__weak typeof(self) monitorSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)),
				   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		typeof(self) strongSelf = monitorSelf;
		if (strongSelf != nil && strongSelf.state == VFLMachineStateStarting) {
			[strongSelf logVMCompositeLaunchDetail];
		}
	});
	return YES;
}

/// 客户机自己关机时 VZ 不会通知我们（iOS 上没有 delegate 头文件），轮询 state 兜底。
- (void)startStatePolling {
	if (_stateTimer != nil) {
		return;
	}
	// 轮询也在主队列：VZ 的 state getter 同样要求当前队列是虚拟机所在队列。
	_stateTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
										 dispatch_get_main_queue());
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
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		NSError *error = nil;
		if (![strongSelf->_machine requestStopWithError:&error]) {
			[strongSelf setState:VFLMachineStateRunning
						 message:error.localizedDescription ?: @"关机请求失败"];
		}
	});
}

- (void)forceStop {
	if (_machine == nil) {
		return;
	}
	[self setState:VFLMachineStateStopping message:@"强制关机…"];
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		[strongSelf->_machine stopWithCompletionHandler:^(NSError *error) {
			typeof(self) insideSelf = weakSelf;
			if (insideSelf == nil) {
				return;
			}
			if (error != nil) {
				[insideSelf setState:VFLMachineStateError
							  message:error.localizedDescription ?: @"强制关机失败"];
				return;
			}
			[insideSelf setState:VFLMachineStateStopped message:@"已停止"];
		}];
	});
}

@end
