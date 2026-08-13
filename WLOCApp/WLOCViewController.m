#import "WLOCViewController.h"
#import <notify.h>

static NSString *const kWLOCSettingsPath = @"/var/mobile/Library/Preferences/com.amorcool.wloc.plist";
static NSString *const kWLOCRestartNotify = @"com.amorcool.wloc/restart";
static NSString *const kWLOCReloadNotify  = @"com.amorcool.wloc/reload";

@interface WLOCViewController ()
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) UITextField *accuracyField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, assign) double latitude;
@property (nonatomic, assign) double longitude;
@property (nonatomic, assign) double accuracy;
@property (nonatomic, assign) BOOL enabled;
@end

@implementation WLOCViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor secondarySystemBackgroundColor];
	self.title = @"WLOC 位置模拟";
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

	[self loadSettings];
	[self buildUI];
	[self refreshUI];
}

#pragma mark - Settings

- (void)loadSettings {
	NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kWLOCSettingsPath];
	self.enabled  = [d[@"enabled"] boolValue];
	self.latitude = d[@"latitude"] ? [d[@"latitude"] doubleValue] : 113.94114;
	self.longitude = d[@"longitude"] ? [d[@"longitude"] doubleValue] : 22.544577;
	self.accuracy = d[@"accuracy"] ? [d[@"accuracy"] doubleValue] : 25.0;
}

- (void)persist {
	NSDictionary *d = @{
		@"enabled":  @(self.enabled),
		@"latitude": @(self.latitude),
		@"longitude": @(self.longitude),
		@"accuracy": @(self.accuracy),
	};
	[d writeToFile:kWLOCSettingsPath atomically:YES];
	chmod([kWLOCSettingsPath UTF8String], 0644);
}

- (void)postNotify:(NSString *)name {
	CFNotificationCenterPostNotification(
		CFNotificationCenterGetDarwinNotifyCenter(),
		(__bridge CFStringRef)name, NULL, NULL, YES);
}

#pragma mark - UI

- (void)buildUI {
	UIScrollView *scroll = [[UIScrollView alloc] init];
	scroll.translatesAutoresizingMaskIntoConstraints = NO;
	scroll.alwaysBounceVertical = YES;
	[self.view addSubview:scroll];

	UIStackView *stack = [[UIStackView alloc] init];
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 16;
	stack.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
	stack.layoutMarginsRelativeArrangement = YES;
	[scroll addSubview:stack];

	[NSLayoutConstraint activateConstraints:@[
		[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
		[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
		[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
		[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
	]];

	// 启用卡片
	[stack addArrangedSubview:[self cardWithContent:^(UIStackView *c){
		UILabel *title = [UILabel new];
		title.text = @"启用位置模拟";
		title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
		self.enableSwitch = [UISwitch new];
		[self.enableSwitch addTarget:self action:@selector(enableChanged:) forControlEvents:UIControlEventValueChanged];
		UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, self.enableSwitch]];
		row.axis = UILayoutConstraintAxisHorizontal;
		row.alignment = UIStackViewAlignmentCenter;
		[title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
		[c addArrangedSubview:row];
		UILabel *sub = [UILabel new];
		sub.text = @"注入 locationd，系统级替换经纬度";
		sub.font = [UIFont systemFontOfSize:13];
		sub.textColor = [UIColor secondaryLabelColor];
		[c addArrangedSubview:sub];
	}]];

	// 坐标卡片
	[stack addArrangedSubview:[self cardWithContent:^(UIStackView *c){
		UILabel *title = [UILabel new];
		title.text = @"目标坐标";
		title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
		[c addArrangedSubview:title];
		self.coordLabel = [UILabel new];
		self.coordLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
		self.coordLabel.textColor = [UIColor labelColor];
		self.coordLabel.numberOfLines = 0;
		[c addArrangedSubview:self.coordLabel];
		UIButton *mapBtn = [UIButton buttonWithType:UIButtonTypeSystem];
		[mapBtn setTitle:@"在地图中选择" forState:UIControlStateNormal];
		mapBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
		[mapBtn addTarget:self action:@selector(openMap) forControlEvents:UIControlEventTouchUpInside];
		[c addArrangedSubview:mapBtn];
	}]];

	// 精度卡片
	[stack addArrangedSubview:[self cardWithContent:^(UIStackView *c){
		UILabel *title = [UILabel new];
		title.text = @"精度 (米)";
		title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
		[c addArrangedSubview:title];
		self.accuracyField = [UITextField new];
		self.accuracyField.keyboardType = UIKeyboardTypeDecimalPad;
		self.accuracyField.borderStyle = UITextBorderStyleRoundedRect;
		self.accuracyField.delegate = self;
		self.accuracyField.placeholder = @"25";
		[c addArrangedSubview:self.accuracyField];
	}]];

	// 操作卡片
	[stack addArrangedSubview:[self cardWithContent:^(UIStackView *c){
		UIButton *apply = [UIButton buttonWithType:UIButtonTypeSystem];
		[apply setTitle:@"应用更改" forState:UIControlStateNormal];
		apply.backgroundColor = [UIColor systemBlueColor];
		[apply setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		apply.layer.cornerRadius = 10;
		apply.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
		[apply addTarget:self action:@selector(applyChanges) forControlEvents:UIControlEventTouchUpInside];
		UIButton *restart = [UIButton buttonWithType:UIButtonTypeSystem];
		[restart setTitle:@"停止并重启 Locationd（刷新缓存）" forState:UIControlStateNormal];
		restart.backgroundColor = [UIColor systemOrangeColor];
		[restart setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		restart.layer.cornerRadius = 10;
		restart.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
		[restart addTarget:self action:@selector(restartLocationd) forControlEvents:UIControlEventTouchUpInside];
		[c addArrangedSubview:apply];
		[c addArrangedSubview:restart];
	}]];

	self.statusLabel = [UILabel new];
	self.statusLabel.font = [UIFont systemFontOfSize:12];
	self.statusLabel.textColor = [UIColor tertiaryLabelColor];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.text = @"设置保存在 /var/mobile/Library/Preferences/com.amorcool.wloc.plist，locationd 实时读取。";
	[stack addArrangedSubview:self.statusLabel];
}

- (UIView *)cardWithContent:(void (^)(UIStackView *content))block {
	UIView *card = [[UIView alloc] init];
	card.backgroundColor = [UIColor systemBackgroundColor];
	card.layer.cornerRadius = 16;
	card.layer.shadowColor = [UIColor blackColor].CGColor;
	card.layer.shadowOpacity = 0.06;
	card.layer.shadowOffset = CGSizeMake(0, 2);
	card.layer.shadowRadius = 6;

	UIStackView *content = [[UIStackView alloc] init];
	content.translatesAutoresizingMaskIntoConstraints = NO;
	content.axis = UILayoutConstraintAxisVertical;
	content.spacing = 10;
	content.layoutMargins = UIEdgeInsetsMake(16, 16, 16, 16);
	content.layoutMarginsRelativeArrangement = YES;
	[card addSubview:content];
	[NSLayoutConstraint activateConstraints:@[
		[content.topAnchor constraintEqualToAnchor:card.topAnchor],
		[content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
		[content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
		[content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
	]];
	if (block) block(content);
	return card;
}

- (void)refreshUI {
	self.enableSwitch.on = self.enabled;
	self.coordLabel.text = [NSString stringWithFormat:@"纬度 %.6f\n经度 %.6f", self.latitude, self.longitude];
	self.accuracyField.text = [NSString stringWithFormat:@"%.0f", self.accuracy];
}

#pragma mark - Actions

- (void)enableChanged:(UISwitch *)sw {
	self.enabled = sw.on;
	[self persist];
	[self postNotify:kWLOCReloadNotify];
	self.statusLabel.text = self.enabled
		? @"已启用模拟，新坐标将立即生效（必要时重启 Locationd 刷新缓存）。"
		: @"已停止模拟，恢复真实定位。";
}

- (void)openMap {
	WLOCMapPicker *picker = [[WLOCMapPicker alloc] init];
	picker.delegate = self;
	picker.initialLatitude = self.latitude;
	picker.initialLongitude = self.longitude;
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)applyChanges {
	double acc = [self.accuracyField.text doubleValue];
	if (!isfinite(acc) || acc <= 0) acc = 25;
	self.accuracy = acc;
	[self persist];
	[self postNotify:kWLOCReloadNotify];
	[self refreshUI];
	self.statusLabel.text = @"已保存并通知 locationd 重新加载设置。";
}

- (void)restartLocationd {
	[self persist];
	[self postNotify:kWLOCRestartNotify];
	self.statusLabel.text = @"已向 locationd 发送重启信号，守护进程将停止并重启以清空内存缓存。";
}

#pragma mark - WLOCMapPickerDelegate

- (void)mapPickerDidPickLatitude:(double)lat longitude:(double)lon {
	self.latitude = lat;
	self.longitude = lon;
	[self persist];
	[self postNotify:kWLOCReloadNotify];
	[self refreshUI];
	self.statusLabel.text = [NSString stringWithFormat:@"已在地图选择：%.6f, %.6f", lat, lon];
}

- (void)mapPickerDidCancel {
	// 用户取消，不改动
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return YES;
}

@end
