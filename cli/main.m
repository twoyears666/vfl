// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import <Foundation/Foundation.h>

#import <errno.h>
#import <fcntl.h>
#import <signal.h>
#import <string.h>
#import <sys/select.h>
#import <termios.h>
#import <unistd.h>

#import "VFLClient.h"
#import "VFLServer.h"
#import "VFLVMDefinition.h"

/// 串口是「字节流」，终端是「字符设备」：所有输出都要排进同一条队，
/// 否则后台事件线程与主线程的消息会互相插进半行。
static NSLock *VFLOutputLock(void) {
	static NSLock *lock = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		lock = [[NSLock alloc] init];
	});
	return lock;
}

static void VFLWriteData(NSData *data) {
	if (data.length == 0) {
		return;
	}
	[VFLOutputLock() lock];
	const uint8_t *bytes = data.bytes;
	NSUInteger remaining = data.length;
	while (remaining > 0) {
		ssize_t written = write(STDOUT_FILENO, bytes, remaining);
		if (written <= 0) {
			break;
		}
		bytes += written;
		remaining -= (NSUInteger)written;
	}
	[VFLOutputLock() unlock];
}

static void VFLWriteString(NSString *string) {
	VFLWriteData([string dataUsingEncoding:NSUTF8StringEncoding]);
}

static void VFLWriteError(NSString *string) {
	NSString *line = [string hasSuffix:@"\n"] ? string : [string stringByAppendingString:@"\n"];
	VFLWriteData([line dataUsingEncoding:NSUTF8StringEncoding]);
}

static NSString *VFLConnectFailure(NSError *error) {
	return [NSString stringWithFormat:@"vfl: %@", error.localizedDescription ?: @"连不上守护进程"];
}

static void VFLPrintUsage(FILE *stream) {
	fputs("用法：\n"
		  "  vfl list              列出虚拟机\n"
		  "  vfl start <名称>      启动虚拟机\n"
		  "  vfl control <名称>    连接串口控制台（Ctrl-C 退出，重连仍是同一上下文）\n"
		  "  vfl shut <名称>       正常关机\n"
		  "  vfl kill <名称>       强制关机\n"
		  "  vfl daemon            守护进程（由 LaunchDaemon 调起）\n", stream);
}

#pragma mark - 终端原始模式

static struct termios VFLSavedTermios;
static BOOL VFLTerminalIsRaw = NO;

static void VFLRestoreTerminal(void) {
	if (!VFLTerminalIsRaw) {
		return;
	}
	tcsetattr(STDIN_FILENO, TCSANOW, &VFLSavedTermios);
	VFLTerminalIsRaw = NO;
}

static void VFLSignalHandler(int signalNumber) {
	VFLRestoreTerminal();
	_exit(128 + signalNumber);
}

static BOOL VFLEnterRawMode(void) {
	if (tcgetattr(STDIN_FILENO, &VFLSavedTermios) != 0) {
		return NO;
	}
	struct termios raw = VFLSavedTermios;
	cfmakeraw(&raw);
	// 保留输出换行转换，客户机只发 \n 时终端也能回到行首。
	raw.c_oflag |= OPOST;
	if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) != 0) {
		return NO;
	}
	VFLTerminalIsRaw = YES;
	signal(SIGINT, VFLSignalHandler);
	signal(SIGTERM, VFLSignalHandler);
	signal(SIGHUP, VFLSignalHandler);
	atexit(VFLRestoreTerminal);
	return YES;
}

#pragma mark - 简单命令

static int VFLRunList(void) {
	NSError *error = nil;
	VFLClient *client = [VFLClient connectWithError:&error];
	if (client == nil) {
		VFLWriteError(VFLConnectFailure(error));
		return 1;
	}
	NSDictionary *response = [client sendRequestWithCommand:@"list" vm:nil error:&error];
	if (response == nil) {
		VFLWriteError(VFLConnectFailure(error));
		return 1;
	}
	if (![response[@"ok"] boolValue]) {
		VFLWriteError([NSString stringWithFormat:@"vfl: %@", response[@"error"] ?: @"查询失败"]);
		return 1;
	}
	NSArray *vms = [response[@"vms"] isKindOfClass:NSArray.class] ? response[@"vms"] : @[];
	if (vms.count == 0) {
		VFLWriteString(@"还没有虚拟机。先在 VFL App 里新建一台。\n");
		return 0;
	}
	VFLWriteString([NSString stringWithFormat:@"%-18s %-10s %9s %4s %4s\n",
					"名称", "状态", "内存", "CPU", "显示"]);
	for (NSDictionary *item in vms) {
		NSMutableString *name = [(item[@"name"] ?: @"") mutableCopy];
		while (name.length < 18) {
			[name appendString:@" "];
		}
		NSMutableString *state = [(item[@"state"] ?: @"") mutableCopy];
		while (state.length < 10) {
			[state appendString:@" "];
		}
		VFLWriteString([NSString stringWithFormat:@"%@ %@ %7lluM %4lu %4lu\n",
						name,
						state,
						[item[@"memoryMB"] unsignedLongLongValue],
						(unsigned long)[item[@"cpuCount"] unsignedIntegerValue],
						(unsigned long)[item[@"displays"] unsignedIntegerValue]]);
	}
	return 0;
}

static int VFLRunSimple(NSString *command, NSString *name) {
	NSError *error = nil;
	VFLClient *client = [VFLClient connectWithError:&error];
	if (client == nil) {
		VFLWriteError(VFLConnectFailure(error));
		return 1;
	}
	NSDictionary *response = [client sendRequestWithCommand:command vm:name error:&error];
	if (response == nil) {
		VFLWriteError(VFLConnectFailure(error));
		return 1;
	}
	if (![response[@"ok"] boolValue]) {
		VFLWriteError([NSString stringWithFormat:@"vfl: %@", response[@"error"] ?: @"命令失败"]);
		return 1;
	}
	NSString *state = response[@"state"];
	if (state.length > 0) {
		VFLWriteString([NSString stringWithFormat:@"%@：%@\n", name, state]);
	}
	return 0;
}

#pragma mark - 控制台

static int VFLRunControl(NSString *name) {
	NSError *error = nil;
	VFLClient *client = [VFLClient connectWithError:&error];
	if (client == nil) {
		VFLWriteError(VFLConnectFailure(error));
		return 1;
	}

	// 事件线程要能把主线程从 select 里叫醒（虚拟机被关掉时）。
	int wake[2] = { -1, -1 };
	if (pipe(wake) != 0) {
		VFLWriteError(@"vfl: 无法创建唤醒管道");
		return 1;
	}
	int wakeReadFD = wake[0];
	int wakeWriteFD = wake[1];
	fcntl(wakeWriteFD, F_SETFL, O_NONBLOCK);

	__block volatile BOOL finished = NO;

	client.eventHandler = ^(NSDictionary *event) {
		NSString *kind = event[@"event"];
		if ([kind isEqualToString:@"console"]) {
			NSString *encoded = event[@"data"];
			NSData *payload = encoded != nil
				? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
			VFLWriteData(payload);
			return;
		}
		if ([kind isEqualToString:@"state"]) {
			NSString *state = event[@"state"] ?: @"";
			NSString *message = event[@"message"] ?: @"";
			VFLWriteString([NSString stringWithFormat:@"\r\n[vfl] %@%@%@\r\n",
							state, message.length > 0 ? @"：" : @"", message]);
			if ([state isEqualToString:@"stopped"] || [state isEqualToString:@"error"]) {
				finished = YES;
				char byte = 1;
				(void)write(wakeWriteFD, &byte, 1);
			}
		}
	};

	if (![client enterControlModeWithVM:name error:&error]) {
		VFLWriteError([NSString stringWithFormat:@"vfl: %@",
					   error.localizedDescription ?: @"无法进入控制台"]);
		return 1;
	}

	NSString *initialState = client.lastState;
	if (![initialState isEqualToString:@"running"] && ![initialState isEqualToString:@"starting"]) {
		[client detach];
		[client close];
		VFLWriteError([NSString stringWithFormat:
					   @"vfl: %@ 当前状态是 %@，请先执行 vfl start %@",
					   name, initialState.length > 0 ? initialState : @"未知", name]);
		return 1;
	}
	if (!VFLEnterRawMode()) {
		[client detach];
		[client close];
		VFLWriteError(@"vfl: 无法把终端切到原始模式");
		return 1;
	}

	VFLWriteString([NSString stringWithFormat:
					@"[vfl] 已连接 %@，Ctrl-C 退出控制台（虚拟机继续运行）\r\n", name]);

	while (!finished) {
		fd_set readSet;
		FD_ZERO(&readSet);
		FD_SET(STDIN_FILENO, &readSet);
		FD_SET(wakeReadFD, &readSet);
		int maxFD = MAX(STDIN_FILENO, wakeReadFD) + 1;

		int ready = select(maxFD, &readSet, NULL, NULL, NULL);
		if (ready < 0) {
			if (errno == EINTR) {
				continue;
			}
			break;
		}
		if (FD_ISSET(wakeReadFD, &readSet)) {
			char drain[64];
			while (read(wakeReadFD, drain, sizeof(drain)) > 0) {
			}
		}
		if (finished) {
			break;
		}
		if (!FD_ISSET(STDIN_FILENO, &readSet)) {
			continue;
		}

		uint8_t buffer[1024];
		ssize_t count = read(STDIN_FILENO, buffer, sizeof(buffer));
		if (count <= 0) {
			break;
		}
		// Ctrl-C 只退出控制台，不发给客户机。
		ssize_t cut = -1;
		for (ssize_t index = 0; index < count; index++) {
			if (buffer[index] == 0x03) {
				cut = index;
				break;
			}
		}
		NSUInteger sendLength = cut >= 0 ? (NSUInteger)cut : (NSUInteger)count;
		if (sendLength > 0) {
			[client sendConsoleInput:[NSData dataWithBytes:buffer length:sendLength]];
		}
		if (cut >= 0) {
			break;
		}
	}

	[client detach];
	[client close];
	close(wake[0]);
	close(wake[1]);
	VFLRestoreTerminal();
	VFLWriteString(@"\r\n[vfl] 已退出控制台，虚拟机仍在运行。再次 control 会回到同一上下文。\r\n");
	return 0;
}

#pragma mark - 守护进程

static int VFLRunDaemon(void) {
	// 客户端断开后 socket 写入会触发 SIGPIPE，守护进程不能因此死掉。
	signal(SIGPIPE, SIG_IGN);

	VFLServer *server = [[VFLServer alloc] init];
	NSError *error = nil;
	if (![server startWithError:&error]) {
		fprintf(stderr, "vfl daemon: %s\n", (error.localizedDescription ?: @"启动失败").UTF8String);
		return 1;
	}
	fprintf(stdout, "vfl daemon: 已监听 %s\n", VFLSocketPath().UTF8String);
	fflush(stdout);

	// Virtualization.framework 的回调依赖 RunLoop 存活。
	[[NSRunLoop currentRunLoop] run];
	[server stop];
	return 0;
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		signal(SIGPIPE, SIG_IGN);

		if (argc < 2) {
			VFLPrintUsage(stdout);
			return 0;
		}
		NSString *command = [NSString stringWithUTF8String:argv[1]];
		if ([command isEqualToString:@"daemon"]) {
			return VFLRunDaemon();
		}
		if ([command isEqualToString:@"list"]) {
			return VFLRunList();
		}
		if ([command isEqualToString:@"start"] || [command isEqualToString:@"control"]
			|| [command isEqualToString:@"shut"] || [command isEqualToString:@"kill"]) {
			if (argc < 3) {
				fprintf(stderr, "vfl: %s 需要虚拟机名称\n", argv[1]);
				return 2;
			}
			NSString *name = [NSString stringWithUTF8String:argv[2]];
			if ([command isEqualToString:@"control"]) {
				return VFLRunControl(name);
			}
			NSString *serverCommand = [command isEqualToString:@"shut"] ? @"shutdown" : command;
			return VFLRunSimple(serverCommand, name);
		}

		VFLPrintUsage(stderr);
		return 2;
	}
}
