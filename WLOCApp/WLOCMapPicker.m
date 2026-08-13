#import "WLOCMapPicker.h"
#import <WebKit/WebKit.h>

@interface WLOCMapPicker () <WKScriptMessageHandler, WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) double lastLat;
@property (nonatomic, assign) double lastLon;
@end

@implementation WLOCMapPicker

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor systemBackgroundColor];
	self.title = @"选择位置";
	self.lastLat = self.initialLatitude;
	self.lastLon = self.initialLongitude;

	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消"
		style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存"
		style:UIBarButtonItemStyleDone target:self action:@selector(save)];

	WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
	WKUserContentController *uc = [[WKUserContentController alloc] init];
	[uc addScriptMessageHandler:self name:@"wloc"];
	cfg.userContentController = uc;

	self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:cfg];
	self.webView.translatesAutoresizingMaskIntoConstraints = NO;
	self.webView.navigationDelegate = self;
	[self.view addSubview:self.webView];
	[NSLayoutConstraint activateConstraints:@[
		[self.webView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	// baseURL 指向 .app 包根目录，使 leaflet.min.css / leaflet.min.js（已打包到
	// layout/Applications/WLOCApp.app/）能以相对路径被 WKWebView 加载，
	// 完全摆脱对 unpkg 等 CDN 的依赖（在国内/受限制网络下也能出图）。
	NSString *html = [self htmlWithLat:self.initialLatitude lon:self.initialLongitude];
	[self.webView loadHTMLString:html baseURL:[[NSBundle mainBundle] bundleURL]];
}

- (void)userContentController:(WKUserContentController *)userContentController
		 didReceiveScriptMessage:(WKScriptMessage *)message {
	NSDictionary *body = message.body;
	if ([body isKindOfClass:[NSDictionary class]]) {
		if ([body[@"lat"] isKindOfClass:[NSNumber class]]) self.lastLat = [body[@"lat"] doubleValue];
		if ([body[@"lon"] isKindOfClass:[NSNumber class]]) self.lastLon = [body[@"lon"] doubleValue];
	}
}

- (void)cancel {
	[self.delegate mapPickerDidCancel];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)save {
	[self.delegate mapPickerDidPickLatitude:self.lastLat longitude:self.lastLon];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)htmlWithLat:(double)lat lon:(double)lon {
	return [NSString stringWithFormat:
@"<!doctype html><html><head><meta charset='utf-8'>"
@"<meta name='viewport' content='width=device-width,initial-scale=1,user-scalable=no'>"
@"<link rel='stylesheet' href='leaflet.min.css'>"
@"<style>html,body{height:100%%;margin:0;font-family:system-ui,-apple-system,sans-serif}"
@"#map{height:100%%;width:100%%}</style></head>"
@"<body><div id='map'></div>"
@"<script src='leaflet.min.js'></script>"
@"<script>"
@"var lat=%f,lng=%f;"
@"var map=L.map('map').setView([lat,lng],15);"
@"L.tileLayer('https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x={x}&y={y}&z={z}',{subdomains:['1','2','3','4'],maxZoom:18,attribution:'&copy; AutoNavi'}).addTo(map);"
@"var marker=L.marker([lat,lng],{draggable:true}).addTo(map);"
@"function emit(){var p=marker.getLatLng();window.webkit.messageHandlers.wloc.postMessage({lat:p.lat,lon:p.lng});}"
@"marker.on('dragend',emit);"
@"map.on('click',function(e){marker.setLatLng(e.latlng);emit();});"
@"emit();"
@"</script></body></html>", lat, lon];
}

@end