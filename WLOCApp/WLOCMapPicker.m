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

	// 关键修复：Leaflet 的 JS/CSS 从 .app 包内读出后【内联】进 HTML，
	// 不再依赖 WKWebView 的 WebContent 进程去读 /var/jb/Applications/... 下的本地文件
	//（rootless 环境里 WebContent 沙盒常常读不到该路径，导致 L is not defined、整页空白）。
	// 瓦片仍走远程（高德，失败自动切 OSM）。JS 错误会经 messageHandler 写到 webview.log 便于排错。
	NSString *html = [self htmlWithLat:self.initialLatitude lon:self.initialLongitude];
	[self.webView loadHTMLString:html baseURL:nil];
}

- (void)userContentController:(WKUserContentController *)userContentController
		 didReceiveScriptMessage:(WKScriptMessage *)message {
	NSDictionary *body = message.body;
	if (![body isKindOfClass:[NSDictionary class]]) return;
	if ([body[@"lat"] isKindOfClass:[NSNumber class]]) self.lastLat = [body[@"lat"] doubleValue];
	if ([body[@"lon"] isKindOfClass:[NSNumber class]]) self.lastLon = [body[@"lon"] doubleValue];
	if ([body[@"err"] isKindOfClass:[NSString class]]) {
		NSString *line = [NSString stringWithFormat:@"[js] %@\n", body[@"err"]];
		NSString *path = @"/var/mobile/Library/Preferences/com.amorcool.wloc.webview.log";
		NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
		if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
		else { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
	}
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	NSString *line = [NSString stringWithFormat:@"[nav] provisional fail: %@\n", error.localizedDescription];
	NSString *path = @"/var/mobile/Library/Preferences/com.amorcool.wloc.webview.log";
	NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
	if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
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
	NSString *jsPath  = [[NSBundle mainBundle] pathForResource:@"leaflet.min" ofType:@"js"];
	NSString *cssPath = [[NSBundle mainBundle] pathForResource:@"leaflet.min" ofType:@"css"];
	NSString *leafletJS  = [NSString stringWithContentsOfFile:jsPath encoding:NSUTF8StringEncoding error:nil];
	NSString *leafletCSS = [NSString stringWithContentsOfFile:cssPath encoding:NSUTF8StringEncoding error:nil];
	BOOL haveLocal = (leafletJS.length > 0 && leafletCSS.length > 0);

	NSString *cssTag = haveLocal
		? [NSString stringWithFormat:@"<style>%@</style>", leafletCSS]
		: @"<link rel='stylesheet' href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css'>";
	NSString *jsTag = haveLocal
		? [NSString stringWithFormat:@"<script>%@</script>", leafletJS]
		: @"<script src='https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'></script>";

	return [NSString stringWithFormat:
@"<!doctype html><html><head><meta charset='utf-8'>"
@"<meta name='viewport' content='width=device-width,initial-scale=1,user-scalable=no'>"
@"%@"
@"<style>html,body{height:100%%;margin:0}#map{height:100%%;width:100%%}</style>"
@"</head><body><div id='map'></div>"
@"<script>window.onerror=function(m,s,l){try{webkit.messageHandlers.wloc.postMessage({err:m+':'+s+':'+l});}catch(e){}};</script>"
@"%@"
@"<script>"
@"try{"
@"var lat=%f,lng=%f;"
@"var tiles=["
@"'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=7&x={x}&y={y}&z={z}',"
@"'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'"
@"];"
@"var tIdx=0;"
@"var map=L.map('map',{zoomControl:true}).setView([lat,lng],15);"
@"function addTile(){var url=tiles[tIdx];var layer=L.tileLayer(url,{subdomains:['1','2','3','4'],maxZoom:18,attribution:'WLOC'}).addTo(map);layer.on('tileerror',function(){if(tIdx<tiles.length-1){tIdx++;addTile();}});}"
@"addTile();"
@"var marker=L.marker([lat,lng],{draggable:true}).addTo(map);"
@"function emit(){var p=marker.getLatLng();webkit.messageHandlers.wloc.postMessage({lat:p.lat,lon:p.lng});}"
@"marker.on('dragend',emit);"
@"map.on('click',function(e){marker.setLatLng(e.latlng);emit();});"
@"emit();"
@"}catch(e){webkit.messageHandlers.wloc.postMessage({err:'init:'+e.message});}"
@"</script></body></html>", cssTag, jsTag, lat, lon];
}

@end
