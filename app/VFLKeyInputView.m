// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 twoyears666

#import "VFLKeyInputView.h"

#pragma mark - 按键映射

/// HID 用法号 → 终端要发送的字符序列。
static NSString *VFLTextForHIDUsage(uint16_t usage) {
	switch (usage) {
		case 0x29: return @"\x1b";    // Esc
		case 0x2B: return @"\t";      // Tab
		case 0x28: return @"\r";      // Return
		case 0x58: return @"\r";      // 小键盘回车
		case 0x2A: return @"\x7f";    // Backspace
		case 0x4C: return @"\x1b[3~"; // Delete
		case 0x4F: return @"\x1b[C";  // Right
		case 0x50: return @"\x1b[D";  // Left
		case 0x51: return @"\x1b[B";  // Down
		case 0x52: return @"\x1b[A";  // Up
		case 0x4A: return @"\x1b[H";  // Home
		case 0x4D: return @"\x1b[F";  // End
		case 0x4B: return @"\x1b[5~"; // PageUp
		case 0x4E: return @"\x1b[6~"; // PageDown
		default: return nil;
	}
}

/// 控制字符（退格、回车、Tab、Esc）→ 终端字符。
static NSString *VFLTextForControlCharacter(unichar character) {
	switch (character) {
		case 0x08: case 0x7F: return @"\x7f";
		case 0x0D: case 0x0A: return @"\r";
		case 0x09: return @"\t";
		case 0x1B: return @"\x1b";
	}
	return nil;
}

/// 这些键需要长按连发。
static BOOL VFLUsageRepeats(uint16_t usage) {
	switch (usage) {
		case 0x2A: case 0x4C:
		case 0x4F: case 0x50: case 0x51: case 0x52:
		case 0x4A: case 0x4D: case 0x4B: case 0x4E:
			return YES;
	}
	return NO;
}

/// 把十六进制字符串还原成字节。
static NSData *VFLDataFromHexString(NSString *hex) {
	NSUInteger length = hex.length / 2;
	NSMutableData *data = [NSMutableData dataWithLength:length];
	uint8_t *bytes = data.mutableBytes;
	for (NSUInteger index = 0; index < length; index++) {
		unsigned int value = 0;
		[[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(index * 2, 2)]] scanHexInt:&value];
		bytes[index] = (uint8_t)value;
	}
	return data;
}

#pragma mark -

@interface VFLKeyInputView () <UITextFieldDelegate>

/// 已按下、还没抬起的键（HID 用法号）。
@property (nonatomic, strong) NSMutableSet<NSNumber *> *pressedUsages;
@property (nonatomic, strong) UITextField *softKeyboardField;
@property (nonatomic, strong) NSTimer *keyRepeatTimer;
@property (nonatomic, assign) uint16_t repeatingUsage;

@end

@implementation VFLKeyInputView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_pressedUsages = [NSMutableSet set];
		self.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.94];
		[self buildKeys];
		self.userInteractionEnabled = YES;
	}
	return self;
}

- (BOOL)canBecomeFirstResponder {
	return YES;
}

- (BOOL)resignFirstResponder {
	[self stopKeyRepeat];
	return [super resignFirstResponder];
}

- (void)dealloc {
	[_keyRepeatTimer invalidate];
}

- (void)focus {
	if (self.softKeyboardField.isFirstResponder) {
		return;
	}
	[self becomeFirstResponder];
}

- (void)showSoftKeyboard {
	if (self.softKeyboardField == nil) {
		UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(-8.0, -8.0, 1.0, 1.0)];
		field.delegate = self;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.spellCheckingType = UITextSpellCheckingTypeNo;
		field.smartQuotesType = UITextSmartQuotesTypeNo;
		field.smartDashesType = UITextSmartDashesTypeNo;
		field.keyboardAppearance = UIKeyboardAppearanceDark;
		field.textColor = UIColor.clearColor;
		field.tintColor = UIColor.clearColor;
		// 常驻一个空格：内容为空时退格不会触发 delegate。
		field.text = @" ";
		[self addSubview:field];
		self.softKeyboardField = field;
	}
	[self.softKeyboardField becomeFirstResponder];
}

- (void)hideSoftKeyboard {
	[self.softKeyboardField resignFirstResponder];
	[self becomeFirstResponder];
}

- (BOOL)isSoftKeyboardVisible {
	return self.softKeyboardField.isFirstResponder;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
	shouldChangeCharactersInRange:(NSRange)range
				replacementString:(NSString *)string {
	if (string.length == 0) {
		[self sendText:@"\x7f"];
	} else {
		[self sendText:string];
	}
	// 文本只借它来触发回调，内容不留。
	textField.text = @" ";
	return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[self sendText:@"\r"];
	return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
	[self becomeFirstResponder];
}

#pragma mark - 底部单键

- (void)buildKeys {
	NSArray<NSArray<NSString *> *> *specs = @[
		@[ @"Esc", @"1b" ], @[ @"Tab", @"09" ], @[ @"←", @"1b5b44" ], @[ @"↑", @"1b5b41" ],
		@[ @"↓", @"1b5b42" ], @[ @"→", @"1b5b43" ], @[ @"⏎", @"0d" ], @[ @"⌫", @"7f" ],
	];
	UIStackView *row = [[UIStackView alloc] init];
	row.translatesAutoresizingMaskIntoConstraints = NO;
	row.axis = UILayoutConstraintAxisHorizontal;
	row.distribution = UIStackViewDistributionFillEqually;
	row.spacing = 6.0;
	[self addSubview:row];

	[NSLayoutConstraint activateConstraints:@[
		[row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8.0],
		[row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
		[row.topAnchor constraintEqualToAnchor:self.topAnchor constant:4.0],
		[row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4.0],
	]];

	for (NSArray<NSString *> *spec in specs) {
		UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
		[button setTitle:spec[0] forState:UIControlStateNormal];
		button.titleLabel.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightMedium];
		[button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
		button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
		button.layer.cornerRadius = 6.0;
		button.accessibilityIdentifier = spec[1];
		[button addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
		[row addArrangedSubview:button];
	}
}

- (void)keyTapped:(UIButton *)sender {
	// 点完按钮把第一响应者抢回来，否则外接键盘的按键会断。
	[self becomeFirstResponder];
	[self sendData:VFLDataFromHexString(sender.accessibilityIdentifier)];
}

#pragma mark - 发送

- (void)sendData:(NSData *)data {
	if (data.length == 0) {
		return;
	}
	if (self.sendHandler != nil) {
		self.sendHandler(data);
	}
}

- (void)sendText:(NSString *)text {
	[self sendData:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)sendUsage:(uint16_t)usage {
	NSString *text = VFLTextForHIDUsage(usage);
	if (text.length > 0) {
		[self sendText:text];
	}
}

#pragma mark - 长按重复

- (void)startKeyRepeatForUsage:(uint16_t)usage {
	[self stopKeyRepeat];
	if (!VFLUsageRepeats(usage)) {
		return;
	}
	self.repeatingUsage = usage;
	__weak typeof(self) weakSelf = self;
	NSTimer *timer = [NSTimer timerWithTimeInterval:0.45 repeats:NO block:^(NSTimer *fired) {
		[weakSelf beginRepeatingUsage];
	}];
	[NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
	self.keyRepeatTimer = timer;
}

- (void)beginRepeatingUsage {
	uint16_t usage = self.repeatingUsage;
	if (usage == 0) {
		return;
	}
	__weak typeof(self) weakSelf = self;
	NSTimer *timer = [NSTimer timerWithTimeInterval:0.09 repeats:YES block:^(NSTimer *fired) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf != nil) {
			[strongSelf sendUsage:usage];
		}
	}];
	[NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
	self.keyRepeatTimer = timer;
}

- (void)stopKeyRepeat {
	[self.keyRepeatTimer invalidate];
	self.keyRepeatTimer = nil;
	self.repeatingUsage = 0;
}

#pragma mark - 硬件键盘

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	BOOL consumed = NO;
	for (UIPress *press in presses) {
		UIKey *key = press.key;
		if (key == nil) {
			continue;
		}
		consumed = YES;
		uint16_t usage = (uint16_t)key.keyCode;
		if (VFLTextForHIDUsage(usage) != nil) {
			if ([self.pressedUsages containsObject:@(usage)]) {
				continue;
			}
			[self.pressedUsages addObject:@(usage)];
			[self sendUsage:usage];
			[self startKeyRepeatForUsage:usage];
			continue;
		}
		[self stopKeyRepeat];
		NSString *characters = key.characters;
		if (characters.length == 0) {
			continue;
		}
		if (characters.length == 1) {
			NSString *control = VFLTextForControlCharacter([characters characterAtIndex:0]);
			if (control.length > 0) {
				[self sendText:control];
				continue;
			}
		}
		NSMutableString *printable = [NSMutableString string];
		for (NSUInteger index = 0; index < characters.length; index++) {
			unichar character = [characters characterAtIndex:index];
			if (character >= 0x20 && character != 0x7F) {
				[printable appendFormat:@"%C", character];
			}
		}
		[self sendText:printable];
	}
	if (!consumed) {
		[super pressesBegan:presses withEvent:event];
	}
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
	BOOL consumed = NO;
	for (UIPress *press in presses) {
		UIKey *key = press.key;
		if (key == nil) {
			continue;
		}
		uint16_t usage = (uint16_t)key.keyCode;
		if ([self.pressedUsages containsObject:@(usage)]) {
			consumed = YES;
			[self.pressedUsages removeObject:@(usage)];
			if (self.repeatingUsage == usage) {
				[self stopKeyRepeat];
			}
		}
	}
	if (!consumed) {
		[super pressesEnded:presses withEvent:event];
	}
}

- (void)pressesCancelled:(NSSet<UIPress> *)presses withEvent:(UIPressesEvent *)event {
	[self pressesEnded:presses withEvent:event];
}

@end
