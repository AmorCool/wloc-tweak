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

	NSString *html = [self htmlWithLat:self.initialLatitude lon:self.initialLongitude];
	[self.webView loadHTMLString:html baseURL:nil];
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
"<meta name='viewport' content='width=device-width,initial-scale=1'>"
"<link rel='stylesheet' href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css'>"
"<style>html,body{height:100%%;margin:0;font-family:system-ui,-apple-system,sans-serif}"
"#map{height:100%%;width:100%%}</style></head>"
"<body><div id='map'></div>"
"<script src='https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'></script>"
"<script>"
"var lat=%f,lng=%f;"
"var map=L.map('map').setView([lat,lng],15);"
"L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',{maxZoom:19}).addTo(map);"
"var marker=L.marker([lat,lng],{draggable:true}).addTo(map);"
"function emit(){var p=marker.getLatLng();window.webkit.messageHandlers.wloc.postMessage({lat:p.lat,lon:p.lng});}"
"marker.on('dragend',emit);"
"map.on('click',function(e){marker.setLatLng(e.latlng);emit();});"
"emit();"
"</script></body></html>", lat, lon];
}

@end
