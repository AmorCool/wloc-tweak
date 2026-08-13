// WLOC — rootless 系统级位置模拟
//
// 原理：Apple 的网络定位（WLOC）与 GPS 最终都由 locationd 汇总后通过 XPC 分发给
// 各 App。本项目把 dylib 注入 locationd，hook CLLocation 的坐标相关方法，在守护进程
// 内部直接替换经纬度 / 精度，从而实现系统级（所有 App 共享）的位置模拟。
//
// 这与 proxypin-wloc-spoofer 的“替换 WLOC 响应里经纬度”目标一致，只是把替换点从
// 网络层（MITM 代理）搬到了 daemon 层（locationd）。
//
// “停止并重启 locationd 内存”：locationd 会在内存里缓存定位结果，导致新坐标不立即
// 生效。App 通过 Darwin notify 通知本 tweak（运行在 locationd 进程内）自杀，launchd
// 随即重启守护进程，内存缓存被清空，新的模拟坐标立即生效。

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <unistd.h>
#import <signal.h>
#import <libproc.h>

// 共享设置文件：mobile（App）写入，_locationd（tweak）读取，需 world-readable
static NSString *const kWLOCSettingsPath = @"/var/mobile/Library/Preferences/com.amorcool.wloc.plist";
static NSString *const kWLOCRestartNotify = @"com.amorcool.wloc/restart";
static NSString *const kWLOCReloadNotify  = @"com.amorcool.wloc/reload";
static NSString *const kWLOCStatusPath    = @"/var/mobile/Library/Preferences/com.amorcool.wloc.status.plist";
static NSString *const kWLOCQueryNotify   = @"com.amorcool.wloc/query";
static NSString *const kWLOCAppBundleID   = @"com.amorcool.wlocapp";

static BOOL   gEnabled = NO;
static double gLat = 0.0;
static double gLon = 0.0;
static double gAcc = 25.0;
static CFAbsoluteTime gLastLoad = 0.0;

static void WLOCLoadSettings(void) {
	@autoreleasepool {
		NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kWLOCSettingsPath];
		if (d) {
			gEnabled = [d[@"enabled"] boolValue];
			gLat = [d[@"latitude"] doubleValue];
			gLon = [d[@"longitude"] doubleValue];
			gAcc = [d[@"accuracy"] doubleValue];
			if (!isfinite(gAcc) || gAcc <= 0.0) gAcc = 25.0;
		} else {
			gEnabled = NO;
		}
	}
	gLastLoad = CFAbsoluteTimeGetCurrent();
}

// 节流：最多每 0.5s 重读一次磁盘，避免高频定位下反复读文件
static void WLOCEnsureLoaded(void) {
	if (CFAbsoluteTimeGetCurrent() - gLastLoad > 0.5) {
		WLOCLoadSettings();
	}
}

// 枚举进程，找到 locationd 的 PID（不依赖注入 locationd 本身）。
// 在“守护进程注入被环境限制”的情况下，App 内运行的 dylib 也能用它报告真实的
// locationd 运行状态与 PID，状态卡片因此照样可用。
static int WLOCFindLocationdPid(void) {
	int bufsize = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
	if (bufsize <= 0) return -1;
	NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)bufsize];
	int *pids = (int *)[data mutableBytes];
	int n = proc_listpids(PROC_ALL_PIDS, 0, pids, bufsize);
	for (int i = 0; i < n; i++) {
		int pid = pids[i];
		if (pid <= 0) continue;
		char name[256];
		if (proc_name(pid, name, sizeof(name)) > 0 && strcmp(name, "locationd") == 0) {
			return pid;
		}
	}
	return -1;
}

static void WLOCWriteStatus(void) {
	@autoreleasepool {
		// 只有两种情况需要写状态：① 本进程就是 locationd（daemon 注入可用时）
		// ② 本进程是 WLOCApp（daemon 注入不可用时，由 App 内 dylib 探测后报告）。
		char selfName[256] = {0};
		proc_name(getpid(), selfName, sizeof(selfName));
		BOOL inLocationd = (strcmp(selfName, "locationd") == 0);
		BOOL inApp       = [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:kWLOCAppBundleID];
		if (!inLocationd && !inApp) return;

		int locPid = inLocationd ? (int)getpid() : WLOCFindLocationdPid();
		NSDictionary *d = @{
			@"locationd_running": @(locPid > 0),
			@"locationd_pid":     @(locPid),
			@"tweak_pid":         @(getpid()),
			@"source":            inLocationd ? @"daemon" : @"probe",
			@"updated_at":        @(CFAbsoluteTimeGetCurrent()),
		};
		[d writeToFile:kWLOCStatusPath atomically:YES];
		chmod([kWLOCStatusPath UTF8String], 0644);
	}
}

%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
	WLOCEnsureLoaded();
	CLLocationCoordinate2D c = %orig;
	if (gEnabled) {
		c.latitude  = gLat;
		c.longitude = gLon;
	}
	return c;
}

- (CLLocationDegrees)latitude {
	WLOCEnsureLoaded();
	return gEnabled ? gLat : %orig;
}

- (CLLocationDegrees)longitude {
	WLOCEnsureLoaded();
	return gEnabled ? gLon : %orig;
}

- (CLLocationAccuracy)horizontalAccuracy {
	WLOCEnsureLoaded();
	return gEnabled ? gAcc : %orig;
}

- (instancetype)initWithLatitude:(CLLocationDegrees)latitude longitude:(CLLocationDegrees)longitude {
	WLOCEnsureLoaded();
	if (gEnabled) {
		return %orig(gLat, gLon);
	}
	return %orig;
}

+ (instancetype)locationWithLatitude:(CLLocationDegrees)latitude longitude:(CLLocationDegrees)longitude {
	WLOCEnsureLoaded();
	if (gEnabled) {
		return %orig(gLat, gLon);
	}
	return %orig;
}

- (instancetype)initWithCoordinate:(CLLocationCoordinate2D)coordinate
                          altitude:(double)altitude
                horizontalAccuracy:(double)hAccuracy
                  verticalAccuracy:(double)vAccuracy
                            course:(double)course
                             speed:(double)speed
                         timestamp:(NSDate *)timestamp {
	WLOCEnsureLoaded();
	if (gEnabled) {
		coordinate.latitude  = gLat;
		coordinate.longitude = gLon;
		if (hAccuracy > 0.0) hAccuracy = gAcc;
		return %orig(coordinate, altitude, hAccuracy, vAccuracy, course, speed, timestamp);
	}
	return %orig;
}

%end

static void WLOCDarwinNotify(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	NSString *n = (__bridge NSString *)name;
	if ([n isEqualToString:kWLOCRestartNotify]) {
		// 在当前 locationd 进程上下文内自杀，launchd 会自动重启守护进程，
		// 从而清空其内存中的定位缓存，使新的模拟坐标立即生效。
		kill(getpid(), SIGKILL);
	} else if ([n isEqualToString:kWLOCReloadNotify]) {
		WLOCLoadSettings();
	} else if ([n isEqualToString:kWLOCQueryNotify]) {
		WLOCWriteStatus();
	}
}

%ctor {
	WLOCEnsureLoaded();
	WLOCWriteStatus();
	CFNotificationCenterAddObserver(
		CFNotificationCenterGetDarwinNotifyCenter(),
		NULL,
		WLOCDarwinNotify,
		(__bridge CFStringRef)kWLOCRestartNotify,
		NULL,
		CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(
		CFNotificationCenterGetDarwinNotifyCenter(),
		NULL,
		WLOCDarwinNotify,
		(__bridge CFStringRef)kWLOCReloadNotify,
		NULL,
		CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(
		CFNotificationCenterGetDarwinNotifyCenter(),
		NULL,
		WLOCDarwinNotify,
		(__bridge CFStringRef)kWLOCQueryNotify,
		NULL,
		CFNotificationSuspensionBehaviorDeliverImmediately);
	%init;
}
