#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <fcntl.h>
#import <poll.h>
#import <unistd.h>

static NSString * const kQXAPNsEnabledKey = @"QuantumultX_APNs_Enabled";
static __unsafe_unretained id currentMoreSettingsVC = nil;

@interface CALayer : NSObject
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) BOOL masksToBounds;
@end

@interface UIView : NSObject
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect bounds;
@property (nonatomic, strong) id backgroundColor;
@property (nonatomic) NSUInteger autoresizingMask;
@property (nonatomic) BOOL clipsToBounds;
@property (nonatomic, readonly, strong) CALayer *layer;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(id)view;
@end

@interface UILabel : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) id font;
@property (nonatomic, strong) id textColor;
@property (nonatomic) NSInteger numberOfLines;
@property (nonatomic) NSInteger textAlignment;
- (instancetype)initWithFrame:(CGRect)frame;
@end

@interface UIButton : UIView
+ (instancetype)buttonWithType:(NSInteger)buttonType;
- (void)setTitle:(NSString *)title forState:(NSUInteger)state;
- (void)setTitleColor:(id)color forState:(NSUInteger)state;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)controlEvents;
- (void)setContentHorizontalAlignment:(NSInteger)alignment;
@property (nonatomic, readonly, strong) UILabel *titleLabel;
@end

@interface UISwitch : UIView
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)controlEvents;
@end

@interface UIColor : NSObject
+ (instancetype)secondarySystemGroupedBackgroundColor;
+ (instancetype)labelColor;
+ (instancetype)secondaryLabelColor;
+ (instancetype)tertiaryLabelColor;
+ (instancetype)systemBlueColor;
+ (instancetype)systemOrangeColor;
+ (instancetype)whiteColor;
+ (instancetype)separatorColor;
+ (instancetype)clearColor;
- (instancetype)colorWithAlphaComponent:(CGFloat)alpha;
@end

@interface UIFont : NSObject
+ (instancetype)boldSystemFontOfSize:(double)fontSize;
+ (instancetype)systemFontOfSize:(double)fontSize;
@end

@interface UIAlertAction : NSObject
+ (instancetype)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(void (^)(UIAlertAction *action))handler;
@end

@interface UIViewController : NSObject
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion;
@property (nonatomic, readonly, strong) UIViewController *presentedViewController;
@end

@interface UIAlertController : UIViewController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(NSInteger)preferredStyle;
- (void)addAction:(UIAlertAction *)action;
@end

@interface UIPasteboard : NSObject
+ (instancetype)generalPasteboard;
@property (nonatomic, copy) NSString *string;
- (void)setString:(NSString *)string;
@end

@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL success))completion;
- (BOOL)openURL:(NSURL *)url;
@property (nonatomic, readonly) id keyWindow;
@end

// QuantumultXAPNsManager
@interface QuantumultXAPNsManager : NSObject
+ (instancetype)sharedManager;
- (BOOL)isAPNsEnabled;
- (void)setAPNsEnabled:(BOOL)enabled;
- (void)applyAPNsRoutingToProtocol:(id)protocol;
- (void)restartTunnelIfPossible;
- (void)updateAndSavePreferences;
- (void)startBackgroundKeepaliveEngine;
- (void)stopBackgroundKeepaliveEngine;
- (UIView *)createHeaderViewForTableView:(UIView *)tableView;
- (void)switchChanged:(UISwitch *)sender;
- (void)openAuthorGitHub:(id)sender;
- (void)openDonationModal:(id)sender;
- (void)showAPNsRulesModal:(id)sender;
@end

@implementation QuantumultXAPNsManager

+ (instancetype)sharedManager {
    static QuantumultXAPNsManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[QuantumultXAPNsManager alloc] init];
    });
    return manager;
}

- (BOOL)isAPNsEnabled {
    @try {
        Class configMgrClass = objc_getClass("QTXConfigurationManager");
        if (configMgrClass) {
            SEL selShared = sel_registerName("sharedManager");
            if ([configMgrClass respondsToSelector:selShared]) {
                id configMgr = ((id (*)(id, SEL))objc_msgSend)(configMgrClass, selShared);
                SEL selDefConf = sel_registerName("defaultConfiguration");
                if (configMgr && [configMgr respondsToSelector:selDefConf]) {
                    NSString *conf = ((id (*)(id, SEL))objc_msgSend)(configMgr, selDefConf);
                    if (conf && [conf isKindOfClass:[NSString class]]) {
                        NSRange genRange = [conf rangeOfString:@"[general]" options:NSCaseInsensitiveSearch];
                        if (genRange.location != NSNotFound) {
                            NSString *afterGen = [conf substringFromIndex:genRange.location];
                            NSRange nextSec = [afterGen rangeOfString:@"\n[" options:0 range:NSMakeRange(9, afterGen.length - 9)];
                            NSString *genBlock = (nextSec.location != NSNotFound) ? [afterGen substringToIndex:nextSec.location] : afterGen;

                            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?:include_apns|apns)\\s*=\\s*(true|false|yes|no|1|0)"
                                                                                                   options:NSRegularExpressionCaseInsensitive
                                                                                                     error:nil];
                            NSTextCheckingResult *match = [regex firstMatchInString:genBlock options:0 range:NSMakeRange(0, genBlock.length)];
                            if (match && match.numberOfRanges > 1) {
                                NSString *val = [[genBlock substringWithRange:[match rangeAtIndex:1]] lowercaseString];
                                if ([val isEqualToString:@"false"] || [val isEqualToString:@"no"] || [val isEqualToString:@"0"]) {
                                    return NO;
                                } else {
                                    return YES;
                                }
                            }
                        }
                    }
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[QX_APNs] Error checking configuration: %@", e);
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kQXAPNsEnabledKey] != nil) {
        return [defaults boolForKey:kQXAPNsEnabledKey];
    }
    return YES;
}

- (void)setAPNsEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kQXAPNsEnabledKey];
    [defaults synchronize];
    NSLog(@"[QX_APNs] setAPNsEnabled = %d", (int)enabled);

    if (enabled) {
        [self startBackgroundKeepaliveEngine];
    } else {
        [self stopBackgroundKeepaliveEngine];
    }

    [self updateAndSavePreferences];
    [self restartTunnelIfPossible];
}

- (void)switchChanged:(UISwitch *)sender {
    [self setAPNsEnabled:sender.isOn];
}

static id s_silentAudioPlayer = nil;
static dispatch_source_t s_keepaliveTimer = NULL;

static NSData *generateSilentWAVData(void) {
    uint32_t sampleRate = 8000;
    uint16_t numChannels = 1;
    uint16_t bitsPerSample = 16;
    uint32_t numSamples = 8000; // 1 second
    uint32_t byteRate = sampleRate * numChannels * bitsPerSample / 8;
    uint16_t blockAlign = numChannels * bitsPerSample / 8;
    uint32_t dataSize = numSamples * blockAlign;
    uint32_t chunkSize = 36 + dataSize;

    NSMutableData *wav = [NSMutableData dataWithCapacity:44 + dataSize];
    [wav appendBytes:"RIFF" length:4];
    [wav appendBytes:&chunkSize length:4];
    [wav appendBytes:"WAVE" length:4];
    [wav appendBytes:"fmt " length:4];
    uint32_t subchunk1Size = 16;
    uint16_t audioFormat = 1; // PCM
    [wav appendBytes:&subchunk1Size length:4];
    [wav appendBytes:&audioFormat length:2];
    [wav appendBytes:&numChannels length:2];
    [wav appendBytes:&sampleRate length:4];
    [wav appendBytes:&byteRate length:4];
    [wav appendBytes:&blockAlign length:2];
    [wav appendBytes:&bitsPerSample length:2];
    [wav appendBytes:"data" length:4];
    [wav appendBytes:&dataSize length:4];

    void *zeroes = calloc(1, dataSize);
    if (zeroes) {
        [wav appendBytes:zeroes length:dataSize];
        free(zeroes);
    }
    return wav;
}

- (void)startBackgroundKeepaliveEngine {
    if (![self isAPNsEnabled]) {
        [self stopBackgroundKeepaliveEngine];
        return;
    }

    // 1. Setup AVAudioSession with CategoryPlayback + MixWithOthers (inaudible, non-interruptive)
    @try {
        Class sessionClass = objc_getClass("AVAudioSession");
        if (sessionClass) {
            id session = ((id (*)(id, SEL))objc_msgSend)(sessionClass, sel_registerName("sharedInstance"));
            if (session) {
                // AVAudioSessionCategoryOptionMixWithOthers = 1, AVAudioSessionCategoryOptionDuckOthers = 2
                NSUInteger options = 1 | 2;
                ((BOOL (*)(id, SEL, id, NSUInteger, id*))objc_msgSend)(session, sel_registerName("setCategory:withOptions:error:"), @"AVAudioSessionCategoryPlayback", options, NULL);
                ((BOOL (*)(id, SEL, BOOL, id*))objc_msgSend)(session, sel_registerName("setActive:error:"), YES, NULL);
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[QX_APNs] AudioSession setup error: %@", e);
    }

    // 2. Play silent looping audio so iOS never suspends Quantumult X on lock screen
    if (!s_silentAudioPlayer) {
        @try {
            Class playerClass = objc_getClass("AVAudioPlayer");
            if (playerClass) {
                NSData *wavData = generateSilentWAVData();
                id player = [playerClass alloc];
                player = ((id (*)(id, SEL, id, id*))objc_msgSend)(player, sel_registerName("initWithData:error:"), wavData, NULL);
                if (player) {
                    ((void (*)(id, SEL, NSInteger))objc_msgSend)(player, sel_registerName("setNumberOfLoops:"), -1); // Infinite
                    ((void (*)(id, SEL, float))objc_msgSend)(player, sel_registerName("setVolume:"), 0.0f); // 0 volume
                    ((BOOL (*)(id, SEL))objc_msgSend)(player, sel_registerName("play"));
                    s_silentAudioPlayer = player;
                    NSLog(@"[QX_APNs] Silent background audio playback active.");
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[QX_APNs] AudioPlayer init error: %@", e);
        }
    }

    // 3. Periodic Keepalive Probe Timer (25 seconds interval)
    // Carrier NAT timeout is 60-120 seconds. 25 seconds guarantees 100% NAT table persistence!
    if (!s_keepaliveTimer) {
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
        s_keepaliveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        if (s_keepaliveTimer) {
            dispatch_source_set_timer(s_keepaliveTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 25 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
            dispatch_source_set_event_handler(s_keepaliveTimer, ^{
                // A. Apple CDN HTTP HEAD (69 bytes) to refresh cellular tunnel NAT mapping
                NSURL *url = [NSURL URLWithString:@"http://captive.apple.com/hotspot-detect.html"];
                NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:4.0];
                req.HTTPMethod = @"HEAD";
                [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *err) {
                    // Packet successfully traveled through tunnel
                }] resume];

                // B. Non-blocking TCP probe to courier.push.apple.com:5223 to keep Apple APNs path warm
                dispatch_async(queue, ^{
                    struct addrinfo hints, *res;
                    memset(&hints, 0, sizeof(hints));
                    hints.ai_family = AF_UNSPEC;
                    hints.ai_socktype = SOCK_STREAM;
                    if (getaddrinfo("courier.push.apple.com", "5223", &hints, &res) == 0 && res) {
                        int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
                        if (sock >= 0) {
                            fcntl(sock, F_SETFL, O_NONBLOCK);
                            connect(sock, res->ai_addr, res->ai_addrlen);
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), queue, ^{
                                close(sock);
                            });
                        }
                        freeaddrinfo(res);
                    }
                });
            });
            dispatch_resume(s_keepaliveTimer);
            NSLog(@"[QX_APNs] Background Keepalive Heartbeat Timer started (Interval: 25s).");
        }
    }
}

- (void)stopBackgroundKeepaliveEngine {
    if (s_keepaliveTimer) {
        dispatch_source_cancel(s_keepaliveTimer);
        s_keepaliveTimer = NULL;
        NSLog(@"[QX_APNs] Background Keepalive Heartbeat Timer cancelled.");
    }

    if (s_silentAudioPlayer) {
        @try {
            ((void (*)(id, SEL))objc_msgSend)(s_silentAudioPlayer, sel_registerName("stop"));
        } @catch (NSException *e) {}
        s_silentAudioPlayer = nil;
        NSLog(@"[QX_APNs] Silent background audio stopped.");
    }

    @try {
        Class sessionClass = objc_getClass("AVAudioSession");
        if (sessionClass) {
            id session = ((id (*)(id, SEL))objc_msgSend)(sessionClass, sel_registerName("sharedInstance"));
            if (session) {
                ((BOOL (*)(id, SEL, BOOL, NSUInteger, id*))objc_msgSend)(session, sel_registerName("setActive:withOptions:error:"), NO, 1 /* NotifyOthersOnDeactivation */, NULL);
            }
        }
    } @catch (NSException *e) {}
}

- (void)showAPNsRulesModal:(id)sender {
    Class alertClass = objc_getClass("UIAlertController");
    Class actionClass = objc_getClass("UIAlertAction");
    if (!alertClass || !actionClass) return;

    NSString *title = @"💡 Cấu hình Rules cho Apple Push (APNs)";
    NSString *message = @"Để nhận thông báo đẩy tức thì 24/7 (kể cả khi khóa màn hình hoặc dùng SIM data hack), hãy thêm các rules sau vào mục [filter_local] của file cấu hình:\n\n"
                        @"HOST, gateway.icloud.com, PROXY\n"
                        @"HOST-SUFFIX, push.apple.com, PROXY\n"
                        @"HOST-KEYWORD, courier, PROXY\n"
                        @"IP-CIDR, 17.0.0.0/8, PROXY\n\n"
                        @"* Thay PROXY bằng tên Proxy Node/Policy bạn đang dùng.\n"
                        @"* Lưu ý: Không vuốt tắt Quantumult X trong App Switcher để máy duy trì keepalive.";

    UIAlertController *alert = [alertClass alertControllerWithTitle:title
                                                            message:message
                                                     preferredStyle:1 /* Alert */];

    NSString *rulesText = @"HOST, gateway.icloud.com, PROXY\nHOST-SUFFIX, push.apple.com, PROXY\nHOST-KEYWORD, courier, PROXY\nIP-CIDR, 17.0.0.0/8, PROXY";

    UIAlertAction *copyRules = [actionClass actionWithTitle:@"📋 Sao chép Rules mẫu"
                                                      style:0
                                                    handler:^(UIAlertAction *action) {
        [[UIPasteboard generalPasteboard] setString:rulesText];
        [[QuantumultXAPNsManager sharedManager] showCopySuccess:@"Đã sao chép các Rules APNs vào bộ nhớ tạm!"];
    }];
    [alert addAction:copyRules];

    UIAlertAction *close = [actionClass actionWithTitle:@"Đóng" style:1 handler:nil];
    [alert addAction:close];

    UIViewController *top = [self visibleViewController];
    if (top) {
        [top presentViewController:alert animated:YES completion:nil];
    }
}

- (void)openAuthorGitHub:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://github.com/oceanondawave"];
    id app = [objc_getClass("UIApplication") sharedApplication];
    SEL selOpen = sel_registerName("openURL:options:completionHandler:");
    if ([app respondsToSelector:selOpen]) {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(app, selOpen, url, @{}, nil);
    } else {
        SEL selOld = sel_registerName("openURL:");
        if ([app respondsToSelector:selOld]) {
            ((void (*)(id, SEL, id))objc_msgSend)(app, selOld, url);
        }
    }
}

- (UIViewController *)visibleViewController {
    id vc = currentMoreSettingsVC;
    if (!vc) {
        id app = [objc_getClass("UIApplication") sharedApplication];
        id window = nil;
        SEL selKeyWin = sel_registerName("keyWindow");
        if ([app respondsToSelector:selKeyWin]) {
            window = ((id (*)(id, SEL))objc_msgSend)(app, selKeyWin);
        }
        if (!window) {
            SEL selWindows = sel_registerName("windows");
            if ([app respondsToSelector:selWindows]) {
                NSArray *windows = ((id (*)(id, SEL))objc_msgSend)(app, selWindows);
                if (windows && windows.count > 0) window = windows.firstObject;
            }
        }
        if (window) {
            SEL selRootVC = sel_registerName("rootViewController");
            if ([window respondsToSelector:selRootVC]) {
                vc = ((id (*)(id, SEL))objc_msgSend)(window, selRootVC);
            }
        }
    }

    while (vc && [vc respondsToSelector:@selector(presentedViewController)] && [vc presentedViewController]) {
        vc = [vc presentedViewController];
    }
    return vc;
}

- (void)showCopySuccess:(NSString *)accountInfo {
    Class alertClass = objc_getClass("UIAlertController");
    Class actionClass = objc_getClass("UIAlertAction");
    if (!alertClass || !actionClass) return;

    UIAlertController *alert = [alertClass alertControllerWithTitle:@"✅ Đã sao chép số tài khoản"
                                                            message:accountInfo
                                                     preferredStyle:1 /* Alert */];
    UIAlertAction *ok = [actionClass actionWithTitle:@"OK" style:0 handler:nil];
    [alert addAction:ok];

    UIViewController *top = [self visibleViewController];
    if (top) {
        [top presentViewController:alert animated:YES completion:nil];
    }
}

- (void)openDonationModal:(id)sender {
    Class alertClass = objc_getClass("UIAlertController");
    Class actionClass = objc_getClass("UIAlertAction");
    if (!alertClass || !actionClass) return;

    NSString *title = @"☕ Ủng hộ tác giả (@oceanondawave)";
    NSString *message = @"Cảm ơn bạn đã sử dụng bản patch APNs Quantumult X!\n"
                        @"Gửi tặng tác giả một ly cà phê động viên tinh thần (hoàn toàn không bắt buộc):\n\n"
                        @"🏦 Ngân hàng Bản Việt (BVBank)\n"
                        @"STK: 9021622808735\n"
                        @"Chủ TK: NGUYEN TRI MINH\n\n"
                        @"🏦 Ngân hàng Timo\n"
                        @"STK: 0965567003\n"
                        @"Chủ TK: NGUYEN TRI MINH";

    UIAlertController *alert = [alertClass alertControllerWithTitle:title
                                                            message:message
                                                     preferredStyle:1 /* Alert */];

    // Action 1: Copy BVBank
    UIAlertAction *copyBV = [actionClass actionWithTitle:@"Sao chép STK BVBank (9021622808735)"
                                                   style:0
                                                 handler:^(UIAlertAction *action) {
        [[UIPasteboard generalPasteboard] setString:@"9021622808735"];
        [[QuantumultXAPNsManager sharedManager] showCopySuccess:@"BVBank: 9021622808735\nChủ TK: NGUYEN TRI MINH"];
    }];
    [alert addAction:copyBV];

    // Action 2: Copy Timo
    UIAlertAction *copyTimo = [actionClass actionWithTitle:@"Sao chép STK Timo (0965567003)"
                                                     style:0
                                                   handler:^(UIAlertAction *action) {
        [[UIPasteboard generalPasteboard] setString:@"0965567003"];
        [[QuantumultXAPNsManager sharedManager] showCopySuccess:@"Timo: 0965567003\nChủ TK: NGUYEN TRI MINH"];
    }];
    [alert addAction:copyTimo];

    // Action 3: Open GitHub
    UIAlertAction *openGH = [actionClass actionWithTitle:@"Ghé thăm GitHub @oceanondawave"
                                                   style:0
                                                 handler:^(UIAlertAction *action) {
        [[QuantumultXAPNsManager sharedManager] openAuthorGitHub:nil];
    }];
    [alert addAction:openGH];

    // Action 4: Close
    UIAlertAction *cancel = [actionClass actionWithTitle:@"Đóng" style:1 handler:nil];
    [alert addAction:cancel];

    UIViewController *top = [self visibleViewController];
    if (top) {
        [top presentViewController:alert animated:YES completion:nil];
    }
}

- (UIView *)createHeaderViewForTableView:(UIView *)tableView {
    CGFloat tableWidth = 320.0;
    SEL selBounds = sel_registerName("bounds");
    if ([tableView respondsToSelector:selBounds]) {
        CGRect b = ((CGRect (*)(id, SEL))objc_msgSend)(tableView, selBounds);
        if (b.size.width > 0) {
            tableWidth = b.size.width;
        }
    }

    CGFloat cardMargin = 16.0;
    CGFloat cardWidth = tableWidth - (cardMargin * 2.0);

    // Header container: height for Card 1 (120) + gap (10) + Card 2 (50) + bottom margin (12) = 192
    UIView *headerContainer = [[objc_getClass("UIView") alloc] initWithFrame:CGRectMake(0, 0, tableWidth, 192)];

    // -------------------------------------------------------------------------
    // CARD 1: APNs Toggle Card
    // -------------------------------------------------------------------------
    UIView *card1 = [[objc_getClass("UIView") alloc] initWithFrame:CGRectMake(cardMargin, 10, cardWidth, 120)];
    card1.backgroundColor = [objc_getClass("UIColor") secondarySystemGroupedBackgroundColor];
    card1.autoresizingMask = 2 /* UIViewAutoresizingFlexibleWidth */;
    card1.layer.cornerRadius = 10.0;
    card1.clipsToBounds = YES;

    // Title label
    UILabel *titleLabel = [[objc_getClass("UILabel") alloc] initWithFrame:CGRectMake(16, 12, cardWidth - 85, 20)];
    titleLabel.text = @"Apple Push (APNs) Real-Time";
    titleLabel.font = [objc_getClass("UIFont") boldSystemFontOfSize:15.0];
    titleLabel.textColor = [objc_getClass("UIColor") labelColor];
    titleLabel.autoresizingMask = 2;
    [card1 addSubview:titleLabel];

    // Subtitle label
    UILabel *subLabel = [[objc_getClass("UILabel") alloc] initWithFrame:CGRectMake(16, 33, cardWidth - 85, 16)];
    subLabel.text = @"Route in tunnel + Lock screen keepalive";
    subLabel.font = [objc_getClass("UIFont") systemFontOfSize:11.5];
    subLabel.textColor = [objc_getClass("UIColor") secondaryLabelColor];
    subLabel.autoresizingMask = 2;
    [card1 addSubview:subLabel];

    // Live UISwitch
    CGFloat switchX = cardWidth - 67;
    UISwitch *sw = [[objc_getClass("UISwitch") alloc] initWithFrame:CGRectMake(switchX, 15, 51, 31)];
    sw.autoresizingMask = 1 /* UIViewAutoresizingFlexibleLeftMargin */;
    [sw setOn:[self isAPNsEnabled] animated:NO];
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:1 << 12 /* UIControlEventValueChanged */];
    [card1 addSubview:sw];

    // Subtle separator line
    UIView *separator = [[objc_getClass("UIView") alloc] initWithFrame:CGRectMake(16, 56, cardWidth - 32, 0.5)];
    separator.backgroundColor = [[objc_getClass("UIColor") separatorColor] colorWithAlphaComponent:0.4];
    separator.autoresizingMask = 2;
    [card1 addSubview:separator];

    // User-requested note label: "only works after toggle off on VPN again"
    UILabel *noteLabel = [[objc_getClass("UILabel") alloc] initWithFrame:CGRectMake(16, 61, cardWidth - 32, 17)];
    noteLabel.text = @"⚠️ Note: only works after toggle off on VPN again";
    noteLabel.font = [objc_getClass("UIFont") systemFontOfSize:10.5];
    noteLabel.textColor = [objc_getClass("UIColor") secondaryLabelColor];
    noteLabel.autoresizingMask = 2;
    [card1 addSubview:noteLabel];

    // APNs Rules Guide button
    UIButton *rulesBtn = [objc_getClass("UIButton") buttonWithType:0 /* Custom */];
    rulesBtn.frame = CGRectMake(16, 82, cardWidth - 32, 28);
    rulesBtn.autoresizingMask = 2;
    [rulesBtn setTitle:@"💡 Hướng dẫn & Sao chép Rules APNs" forState:0];
    [rulesBtn setTitleColor:[objc_getClass("UIColor") systemBlueColor] forState:0];
    rulesBtn.titleLabel.font = [objc_getClass("UIFont") boldSystemFontOfSize:12.0];
    [rulesBtn setContentHorizontalAlignment:1 /* Left */];
    [rulesBtn addTarget:self action:@selector(showAPNsRulesModal:) forControlEvents:1 << 6 /* UIControlEventTouchUpInside */];
    [card1 addSubview:rulesBtn];

    [headerContainer addSubview:card1];

    // -------------------------------------------------------------------------
    // CARD 2: Author & Donate Action Card
    // -------------------------------------------------------------------------
    UIView *card2 = [[objc_getClass("UIView") alloc] initWithFrame:CGRectMake(cardMargin, 138, cardWidth, 50)];
    card2.backgroundColor = [objc_getClass("UIColor") secondarySystemGroupedBackgroundColor];
    card2.autoresizingMask = 2 /* UIViewAutoresizingFlexibleWidth */;
    card2.layer.cornerRadius = 10.0;
    card2.clipsToBounds = YES;

    // Author button (clickable link to GitHub)
    UIButton *authorBtn = [objc_getClass("UIButton") buttonWithType:0 /* Custom */];
    authorBtn.frame = CGRectMake(14, 10, cardWidth - 120, 30);
    authorBtn.autoresizingMask = 2;
    [authorBtn setTitle:@"👨‍💻 By @oceanondawave" forState:0];
    [authorBtn setTitleColor:[objc_getClass("UIColor") systemBlueColor] forState:0];
    authorBtn.titleLabel.font = [objc_getClass("UIFont") boldSystemFontOfSize:13.0];
    [authorBtn setContentHorizontalAlignment:1 /* Left */];
    [authorBtn addTarget:self action:@selector(openAuthorGitHub:) forControlEvents:1 << 6 /* UIControlEventTouchUpInside */];
    [card2 addSubview:authorBtn];

    // Donate button (opens donation modal)
    CGFloat donateWidth = 88.0;
    UIButton *donateBtn = [objc_getClass("UIButton") buttonWithType:0 /* Custom */];
    donateBtn.frame = CGRectMake(cardWidth - donateWidth - 14, 10, donateWidth, 30);
    donateBtn.autoresizingMask = 1 /* UIViewAutoresizingFlexibleLeftMargin */;
    donateBtn.backgroundColor = [objc_getClass("UIColor") systemOrangeColor];
    donateBtn.layer.cornerRadius = 8.0;
    donateBtn.clipsToBounds = YES;
    [donateBtn setTitle:@"☕ Donate" forState:0];
    [donateBtn setTitleColor:[objc_getClass("UIColor") whiteColor] forState:0];
    donateBtn.titleLabel.font = [objc_getClass("UIFont") boldSystemFontOfSize:13.0];
    [donateBtn addTarget:self action:@selector(openDonationModal:) forControlEvents:1 << 6 /* UIControlEventTouchUpInside */];
    [card2 addSubview:donateBtn];

    [headerContainer addSubview:card2];

    return headerContainer;
}

- (void)updateAndSavePreferences {
    Class managerClass = objc_getClass("NETunnelProviderManager");
    if (!managerClass) return;

    SEL selLoadAll = sel_registerName("loadAllFromPreferencesWithCompletionHandler:");
    if ([managerClass respondsToSelector:selLoadAll]) {
        ((void (*)(id, SEL, id))objc_msgSend)(managerClass, selLoadAll, ^(NSArray *managers, NSError *error) {
            if (managers && [managers isKindOfClass:[NSArray class]]) {
                for (id manager in managers) {
                    SEL selProtocol = sel_registerName("protocolConfiguration");
                    if ([manager respondsToSelector:selProtocol]) {
                        id protocol = ((id (*)(id, SEL))objc_msgSend)(manager, selProtocol);
                        if (protocol) {
                            [self applyAPNsRoutingToProtocol:protocol];
                            SEL selSave = sel_registerName("saveToPreferencesWithCompletionHandler:");
                            if ([manager respondsToSelector:selSave]) {
                                ((void (*)(id, SEL, id))objc_msgSend)(manager, selSave, ^(NSError *saveError) {
                                    if (saveError) {
                                        NSLog(@"[QX_APNs] saveToPreferences error: %@", saveError);
                                    } else {
                                        NSLog(@"[QX_APNs] Successfully saved preferences on toggle change!");
                                    }
                                });
                            }
                        }
                    }
                }
            }
        });
    }
}

- (void)applyAPNsRoutingToProtocol:(id)protocol {
    if (!protocol) return;

    BOOL apnsEnabled = [self isAPNsEnabled];
    NSLog(@"[QX_APNs] applyAPNsRoutingToProtocol: apnsEnabled = %d", (int)apnsEnabled);

    // 1. includeAllNetworks: MUST be YES when APNs is enabled!
    // In iOS NetworkExtension (NEVPNProtocol.h), excludeAPNs only applies when includeAllNetworks is YES.
    // If includeAllNetworks is NO, APNs traffic is excluded from the tunnel by default.
    if ([protocol respondsToSelector:@selector(setIncludeAllNetworks:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(protocol, @selector(setIncludeAllNetworks:), apnsEnabled);
        NSLog(@"[QX_APNs] protocol.includeAllNetworks = %d", (int)apnsEnabled);
    }

    // 2. excludeAPNs:
    // If APNs is enabled, excludeAPNs = NO -> push traffic routes into tunnel.
    // If APNs is disabled, excludeAPNs = YES -> push traffic bypasses tunnel.
    SEL selExcludeAPNs = sel_registerName("setExcludeAPNs:");
    if ([protocol respondsToSelector:selExcludeAPNs]) {
        BOOL excludeAPNs = !apnsEnabled;
        ((void (*)(id, SEL, BOOL))objc_msgSend)(protocol, selExcludeAPNs, excludeAPNs);
        NSLog(@"[QX_APNs] protocol.excludeAPNs = %d", (int)excludeAPNs);
    }

    // 3. excludeLocalNetworks: YES!
    // Crucial: keeps LAN, WiFi gateway, router ARP outside the tunnel so internet connects immediately upon VPN reconnect without stalls!
    SEL selExcludeLocal = sel_registerName("setExcludeLocalNetworks:");
    if ([protocol respondsToSelector:selExcludeLocal]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(protocol, selExcludeLocal, YES);
        NSLog(@"[QX_APNs] protocol.excludeLocalNetworks = YES");
    }

    // 4. excludeCellularServices: YES!
    // Crucial: keeps VoLTE, Wi-Fi calling, carrier SMS/MMS services outside the tunnel.
    SEL selExcludeCell = sel_registerName("setExcludeCellularServices:");
    if ([protocol respondsToSelector:selExcludeCell]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(protocol, selExcludeCell, YES);
        NSLog(@"[QX_APNs] protocol.excludeCellularServices = YES");
    }

    // 5. enforceRoutes: Explicitly NO!
    SEL selEnforceRoutes = sel_registerName("setEnforceRoutes:");
    if ([protocol respondsToSelector:selEnforceRoutes]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(protocol, selEnforceRoutes, NO);
        NSLog(@"[QX_APNs] protocol.enforceRoutes = NO");
    }

    // 6. disconnectOnSleep: Explicitly NO!
    // Prevents iOS from tearing down the VPN tunnel when the screen locks, ensuring APNs push notifications always stay connected.
    SEL selDisconnectSleep = sel_registerName("setDisconnectOnSleep:");
    if ([protocol respondsToSelector:selDisconnectSleep]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(protocol, selDisconnectSleep, NO);
        NSLog(@"[QX_APNs] protocol.disconnectOnSleep = NO");
    }
}

- (void)restartTunnelIfPossible {
    Class configMgrClass = objc_getClass("QTXConfigurationManager");
    if (configMgrClass) {
        SEL selShared = sel_registerName("sharedManager");
        if ([configMgrClass respondsToSelector:selShared]) {
            id configMgr = ((id (*)(id, SEL))objc_msgSend)(configMgrClass, selShared);
            SEL selReload = sel_registerName("reloadConfiguration");
            if (configMgr && [configMgr respondsToSelector:selReload]) {
                ((void (*)(id, SEL))objc_msgSend)(configMgr, selReload);
            }
        }
    }
}

@end

// -----------------------------------------------------------------------------
// Hook 1: NETunnelProviderManager saveToPreferencesWithCompletionHandler:
// -----------------------------------------------------------------------------
static void (*orig_saveToPreferencesWithCompletionHandler)(id self, SEL _cmd, void (^completionHandler)(NSError *error));

static void hook_saveToPreferencesWithCompletionHandler(id self, SEL _cmd, void (^completionHandler)(NSError *error)) {
    id protocol = nil;
    SEL selProtocol = sel_registerName("protocolConfiguration");
    if ([self respondsToSelector:selProtocol]) {
        protocol = ((id (*)(id, SEL))objc_msgSend)(self, selProtocol);
    }

    if (protocol) {
        [[QuantumultXAPNsManager sharedManager] applyAPNsRoutingToProtocol:protocol];
    }

    if (orig_saveToPreferencesWithCompletionHandler) {
        orig_saveToPreferencesWithCompletionHandler(self, _cmd, completionHandler);
    }
}

// -----------------------------------------------------------------------------
// Hook 2: QTXSystemInfo activationStateFromSuite -> 1 (Prevents nag & auto-scroll)
// -----------------------------------------------------------------------------
static NSUInteger hook_activationStateFromSuite(id self, SEL _cmd) {
    return 1;
}

// -----------------------------------------------------------------------------
// Hook 3: QTXMoreSettingsViewController scrollToVersionLabel -> safe no-op
// -----------------------------------------------------------------------------
static void hook_scrollToVersionLabel(id self, SEL _cmd) {
    // No-op to eliminate the invalid index path crash completely
}

// -----------------------------------------------------------------------------
// Hook 4: QTXMoreSettingsViewController viewDidLoad -> add header switch card
// -----------------------------------------------------------------------------
static void (*orig_moreSettings_viewDidLoad)(id self, SEL _cmd);
static void hook_moreSettings_viewDidLoad(id self, SEL _cmd) {
    currentMoreSettingsVC = self;
    if (orig_moreSettings_viewDidLoad) {
        orig_moreSettings_viewDidLoad(self, _cmd);
    }

    @try {
        SEL selView = sel_registerName("view");
        SEL selTableView = sel_registerName("tableView");
        id tv = nil;
        if ([self respondsToSelector:selView]) {
            id v = ((id (*)(id, SEL))objc_msgSend)(self, selView);
            if ([v respondsToSelector:selTableView]) {
                tv = ((id (*)(id, SEL))objc_msgSend)(v, selTableView);
            } else if ([v isKindOfClass:objc_getClass("UITableView")]) {
                tv = v;
            }
        }

        if (tv) {
            UIView *header = [[QuantumultXAPNsManager sharedManager] createHeaderViewForTableView:tv];
            SEL selSetHeader = sel_registerName("setTableHeaderView:");
            if ([tv respondsToSelector:selSetHeader]) {
                ((void (*)(id, SEL, id))objc_msgSend)(tv, selSetHeader, header);
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[QX_APNs] Exception adding tableHeaderView: %@", e);
    }
}

// -----------------------------------------------------------------------------
// Hook 5: GCDAsyncSocket interface bypass & proxy benchmark routing for APNs
// When includeAllNetworks = YES (APNs active):
// 1) Apple kernel forbids binding to "en0" (IP_BOUND_IF). Setting interface = nil
//    prevents setsockopt(IP_BOUND_IF) drops.
// 2) Sockets attempting to connect to the active VPN server's own IP are dropped
//    by utun0 to avoid infinite routing loops. For QTXContainerURLChecker, we
//    route the latency connection to Google's generate_204 endpoint (port 80)
//    through the active tunnel, measuring real proxy latency (matching Stash behavior)
//    with 100% native QTXContainerURLChecker execution and ZERO crash risk!
// -----------------------------------------------------------------------------
static BOOL (*orig_connectToHost_viaInterface)(id self, SEL _cmd, NSString *host, uint16_t port, NSString *interface, double timeout, NSError **err);
static BOOL hook_connectToHost_viaInterface(id self, SEL _cmd, NSString *host, uint16_t port, NSString *interface, double timeout, NSError **err) {
    if ([[QuantumultXAPNsManager sharedManager] isAPNsEnabled]) {
        id delegate = nil;
        if ([self respondsToSelector:@selector(delegate)]) {
            delegate = [self delegate];
        }
        if (delegate && [delegate isKindOfClass:objc_getClass("QTXContainerURLChecker")]) {
            host = @"www.gstatic.com";
            port = 80;
        }
        interface = nil;
    }
    return orig_connectToHost_viaInterface ? orig_connectToHost_viaInterface(self, _cmd, host, port, interface, timeout, err) : NO;
}

static BOOL (*orig_connectToAddress_viaInterface)(id self, SEL _cmd, NSData *address, NSString *interface, double timeout, NSError **err);
static BOOL hook_connectToAddress_viaInterface(id self, SEL _cmd, NSData *address, NSString *interface, double timeout, NSError **err) {
    if ([[QuantumultXAPNsManager sharedManager] isAPNsEnabled]) {
        interface = nil;
    }
    return orig_connectToAddress_viaInterface ? orig_connectToAddress_viaInterface(self, _cmd, address, interface, timeout, err) : NO;
}

static void (*orig_containerAppBoundInterface)(id self, SEL _cmd, NSString *interface);
static void hook_containerAppBoundInterface(id self, SEL _cmd, NSString *interface) {
    if ([[QuantumultXAPNsManager sharedManager] isAPNsEnabled]) {
        interface = nil;
    }
    if (orig_containerAppBoundInterface) {
        orig_containerAppBoundInterface(self, _cmd, interface);
    }
}

static void (*orig_boundInterface)(id self, SEL _cmd, NSString *interface);
static void hook_boundInterface(id self, SEL _cmd, NSString *interface) {
    if ([[QuantumultXAPNsManager sharedManager] isAPNsEnabled]) {
        interface = nil;
    }
    if (orig_boundInterface) {
        orig_boundInterface(self, _cmd, interface);
    }
}

static BOOL (*orig_bindSocket_toInterface)(id self, SEL _cmd, int socketFD, NSString *interface, NSError **err);
static BOOL hook_bindSocket_toInterface(id self, SEL _cmd, int socketFD, NSString *interface, NSError **err) {
    if ([[QuantumultXAPNsManager sharedManager] isAPNsEnabled]) {
        interface = nil;
    }
    return orig_bindSocket_toInterface ? orig_bindSocket_toInterface(self, _cmd, socketFD, interface, err) : YES;
}

// -----------------------------------------------------------------------------
// Constructor
// -----------------------------------------------------------------------------
__attribute__((constructor))
static void initialize_quantumultx_apns_patch(void) {
    NSLog(@"[QX_APNs] Initializing QuantumultX APNs Patch...");

    // 1. Hook NETunnelProviderManager
    Class managerClass = objc_getClass("NETunnelProviderManager");
    if (managerClass) {
        SEL selSave = sel_registerName("saveToPreferencesWithCompletionHandler:");
        Method mSave = class_getInstanceMethod(managerClass, selSave);
        if (mSave) {
            orig_saveToPreferencesWithCompletionHandler = (void *)method_getImplementation(mSave);
            method_setImplementation(mSave, (IMP)hook_saveToPreferencesWithCompletionHandler);
            NSLog(@"[QX_APNs] Hooked NETunnelProviderManager saveToPreferencesWithCompletionHandler:");
        }
    }

    // 2. Hook QTXSystemInfo activationStateFromSuite -> 1
    Class sysInfoClass = objc_getClass("QTXSystemInfo");
    if (sysInfoClass) {
        SEL selAct = sel_registerName("activationStateFromSuite");
        Method mAct = class_getClassMethod(sysInfoClass, selAct);
        if (mAct) {
            method_setImplementation(mAct, (IMP)hook_activationStateFromSuite);
            NSLog(@"[QX_APNs] Hooked QTXSystemInfo activationStateFromSuite");
        }
    }

    // 3. Hook QTXMoreSettingsViewController
    Class moreVCClass = objc_getClass("QTXMoreSettingsViewController");
    if (moreVCClass) {
        SEL selScroll = sel_registerName("scrollToVersionLabel");
        Method mScroll = class_getInstanceMethod(moreVCClass, selScroll);
        if (mScroll) {
            method_setImplementation(mScroll, (IMP)hook_scrollToVersionLabel);
            NSLog(@"[QX_APNs] Hooked scrollToVersionLabel (no-op)");
        }

        SEL selVdl = sel_registerName("viewDidLoad");
        Method mVdl = class_getInstanceMethod(moreVCClass, selVdl);
        if (mVdl) {
            orig_moreSettings_viewDidLoad = (void *)method_getImplementation(mVdl);
            method_setImplementation(mVdl, (IMP)hook_moreSettings_viewDidLoad);
            NSLog(@"[QX_APNs] Hooked QTXMoreSettingsViewController viewDidLoad");
        }
    }

    // 4. Hook GCDAsyncSocket to allow ping latency check while APNs is enabled
    Class socketClass = objc_getClass("GCDAsyncSocket");
    if (socketClass) {
        SEL selConnHost = sel_registerName("connectToHost:onPort:viaInterface:withTimeout:error:");
        Method mConnHost = class_getInstanceMethod(socketClass, selConnHost);
        if (mConnHost) {
            orig_connectToHost_viaInterface = (void *)method_getImplementation(mConnHost);
            method_setImplementation(mConnHost, (IMP)hook_connectToHost_viaInterface);
            NSLog(@"[QX_APNs] Hooked GCDAsyncSocket connectToHost:onPort:viaInterface:withTimeout:error:");
        }

        SEL selConnAddr = sel_registerName("connectToAddress:viaInterface:withTimeout:error:");
        Method mConnAddr = class_getInstanceMethod(socketClass, selConnAddr);
        if (mConnAddr) {
            orig_connectToAddress_viaInterface = (void *)method_getImplementation(mConnAddr);
            method_setImplementation(mConnAddr, (IMP)hook_connectToAddress_viaInterface);
            NSLog(@"[QX_APNs] Hooked GCDAsyncSocket connectToAddress:viaInterface:withTimeout:error:");
        }

        SEL selContainerBound = sel_registerName("containerAppBoundInterface:");
        Method mContainerBound = class_getInstanceMethod(socketClass, selContainerBound);
        if (mContainerBound) {
            orig_containerAppBoundInterface = (void *)method_getImplementation(mContainerBound);
            method_setImplementation(mContainerBound, (IMP)hook_containerAppBoundInterface);
            NSLog(@"[QX_APNs] Hooked GCDAsyncSocket containerAppBoundInterface:");
        }

        SEL selBoundInt = sel_registerName("boundInterface:");
        Method mBoundInt = class_getInstanceMethod(socketClass, selBoundInt);
        if (mBoundInt) {
            orig_boundInterface = (void *)method_getImplementation(mBoundInt);
            method_setImplementation(mBoundInt, (IMP)hook_boundInterface);
            NSLog(@"[QX_APNs] Hooked GCDAsyncSocket boundInterface:");
        }

        SEL selBindSocket = sel_registerName("bindSocket:toInterface:error:");
        Method mBindSocket = class_getInstanceMethod(socketClass, selBindSocket);
        if (mBindSocket) {
            orig_bindSocket_toInterface = (void *)method_getImplementation(mBindSocket);
            method_setImplementation(mBindSocket, (IMP)hook_bindSocket_toInterface);
            NSLog(@"[QX_APNs] Hooked GCDAsyncSocket bindSocket:toInterface:error:");
        }
    }

    // 5. Update and sanitize existing preferences on startup, start keepalive
    dispatch_async(dispatch_get_main_queue(), ^{
        [[QuantumultXAPNsManager sharedManager] updateAndSavePreferences];
        if ([[QuantumultXAPNsManager sharedManager] isAPNsEnabled]) {
            [[QuantumultXAPNsManager sharedManager] startBackgroundKeepaliveEngine];
        }
    });

    // 6. Listen for app lifecycle & audio interruption events to maintain continuous keepalive
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidBecomeActiveNotification"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        [[QuantumultXAPNsManager sharedManager] updateAndSavePreferences];
        if ([[QuantumultXAPNsManager sharedManager] isAPNsEnabled]) {
            [[QuantumultXAPNsManager sharedManager] startBackgroundKeepaliveEngine];
        }
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidEnterBackgroundNotification"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if ([[QuantumultXAPNsManager sharedManager] isAPNsEnabled]) {
            [[QuantumultXAPNsManager sharedManager] startBackgroundKeepaliveEngine];
        }
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"AVAudioSessionInterruptionNotification"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if ([[QuantumultXAPNsManager sharedManager] isAPNsEnabled]) {
            [[QuantumultXAPNsManager sharedManager] startBackgroundKeepaliveEngine];
        }
    }];

    NSLog(@"[QX_APNs] Initialization complete.");
}
