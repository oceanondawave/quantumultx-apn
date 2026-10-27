#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <unistd.h>
#import "fishhook.h"

// -----------------------------------------------------------------------------
// 1. Enable SO_KEEPALIVE and aggressive TCP_KEEPALIVE on all TCP sockets
// -----------------------------------------------------------------------------
static void configure_socket_keepalive(int fd) {
    if (fd < 0) return;

    int opt_on = 1;
    // 1. Enable SO_KEEPALIVE
    setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &opt_on, sizeof(opt_on));

    // 2. TCP_KEEPALIVE: time in seconds of idle before sending first probe.
    // Default on iOS is 7200s (2 hrs!). We set it to 15s so NAT mappings NEVER expire!
    int idle = 15;
    setsockopt(fd, IPPROTO_TCP, TCP_KEEPALIVE, &idle, sizeof(idle));

    // 3. TCP_KEEPINTVL: interval between probes (5 seconds)
    int intvl = 5;
    setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &intvl, sizeof(intvl));

    // 4. TCP_KEEPCNT: number of failed probes before drop
    int cnt = 4;
    setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, &cnt, sizeof(cnt));
}

// Hook connect
static int (*orig_connect)(int sockfd, const struct sockaddr *addr, socklen_t addrlen) = NULL;
static int hook_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    configure_socket_keepalive(sockfd);
    int ret = orig_connect ? orig_connect(sockfd, addr, addrlen) : -1;
    if (ret == 0) {
        configure_socket_keepalive(sockfd);
    }
    return ret;
}

// Hook connectx
typedef struct sa_endpoints sa_endpoints_t;
typedef uint32_t sae_associd_t;
typedef uint32_t sae_connid_t;
static int (*orig_connectx)(int sockfd, const sa_endpoints_t *endpoints, sae_associd_t associd, unsigned int flags, const struct iovec *iov, unsigned int iovcnt, size_t *len, sae_connid_t *connid) = NULL;
static int hook_connectx(int sockfd, const sa_endpoints_t *endpoints, sae_associd_t associd, unsigned int flags, const struct iovec *iov, unsigned int iovcnt, size_t *len, sae_connid_t *connid) {
    configure_socket_keepalive(sockfd);
    int ret = orig_connectx ? orig_connectx(sockfd, endpoints, associd, flags, iov, iovcnt, len, connid) : -1;
    if (ret == 0) {
        configure_socket_keepalive(sockfd);
    }
    return ret;
}

// Hook GCDAsyncSocket didConnect:
static void (*orig_gcd_didConnect)(id self, SEL _cmd, id a1);
static void hook_gcd_didConnect(id self, SEL _cmd, id a1) {
    if (orig_gcd_didConnect) {
        orig_gcd_didConnect(self, _cmd, a1);
    }
    int fd = -1;
    if ([self respondsToSelector:sel_registerName("socketFD")]) {
        fd = ((int (*)(id, SEL))objc_msgSend)(self, sel_registerName("socketFD"));
    }
    if (fd < 0 && [self respondsToSelector:sel_registerName("socket4FD")]) {
        fd = ((int (*)(id, SEL))objc_msgSend)(self, sel_registerName("socket4FD"));
    }
    if (fd < 0 && [self respondsToSelector:sel_registerName("socket6FD")]) {
        fd = ((int (*)(id, SEL))objc_msgSend)(self, sel_registerName("socket6FD"));
    }
    if (fd >= 0) {
        configure_socket_keepalive(fd);
    }
}

// -----------------------------------------------------------------------------
// 2. Prevent QTXPacketTunnelProvider from suspending during device lock/sleep
// Stash does NOT implement sleepWithCompletionHandler:, keeping the tunnel
// reading packets 24/7. In Quantumult X, we swizzle sleepWithCompletionHandler:
// so it immediately returns without tearing down packet flow or pausing timers.
// -----------------------------------------------------------------------------
static void hook_tunnel_sleepWithCompletionHandler(id self, SEL _cmd, void (^completionHandler)(void)) {
    NSLog(@"[QX_TunnelKeepalive] Device lock/sleep requested. Keeping tunnel active for instant APNs delivery!");
    if (completionHandler) {
        completionHandler();
    }
}

// -----------------------------------------------------------------------------
// 3. Background Heartbeat Timer
// Fires every 20 seconds to keep the tunnel extension's dispatch loop active
// and maintain cellular Radio Resource Control (RRC_CONNECTED) state.
// -----------------------------------------------------------------------------
static dispatch_source_t heartbeatTimer = NULL;

static void start_background_heartbeat(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_queue_t queue = dispatch_queue_create("com.crossutility.quantumult-x.tunnel.heartbeat", DISPATCH_QUEUE_SERIAL);
        heartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        if (heartbeatTimer) {
            // Start after 5 seconds, repeat every 20 seconds
            dispatch_source_set_timer(heartbeatTimer,
                                      dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                                      20 * NSEC_PER_SEC,
                                      1 * NSEC_PER_SEC);
            dispatch_source_set_event_handler(heartbeatTimer, ^{
                // Send dummy UDP probe to localhost to keep socket buffers warm
                int s = socket(AF_INET, SOCK_DGRAM, 0);
                if (s >= 0) {
                    struct sockaddr_in sin;
                    memset(&sin, 0, sizeof(sin));
                    sin.sin_family = AF_INET;
                    sin.sin_port = htons(5353); // mDNS port
                    sin.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
                    char dummy = 0;
                    sendto(s, &dummy, 1, 0, (struct sockaddr *)&sin, sizeof(sin));
                    close(s);
                }
            });
            dispatch_resume(heartbeatTimer);
            NSLog(@"[QX_TunnelKeepalive] 20s background heartbeat timer active.");
        }
    });
}

// -----------------------------------------------------------------------------
// 4. Constructor
// -----------------------------------------------------------------------------
__attribute__((constructor))
static void init_tunnel_keepalive(void) {
    NSLog(@"[QX_TunnelKeepalive] Initializing Quantumult X Tunnel Keepalive...");

    // 1. Rebind connect and connectx to enforce TCP keepalive
    struct rebinding rebindings[] = {
        {"connect", (void *)hook_connect, (void **)&orig_connect},
        {"connectx", (void *)hook_connectx, (void **)&orig_connectx}
    };
    rebind_symbols(rebindings, 2);
    NSLog(@"[QX_TunnelKeepalive] Rebound connect & connectx for TCP keepalive.");

    // 2. Swizzle GCDAsyncSocket didConnect:
    Class socketClass = objc_getClass("GCDAsyncSocket");
    if (socketClass) {
        SEL selDidConn = sel_registerName("didConnect:");
        Method mDidConn = class_getInstanceMethod(socketClass, selDidConn);
        if (mDidConn) {
            orig_gcd_didConnect = (void *)method_getImplementation(mDidConn);
            method_setImplementation(mDidConn, (IMP)hook_gcd_didConnect);
            NSLog(@"[QX_TunnelKeepalive] Hooked GCDAsyncSocket didConnect:");
        }
    }

    // 3. Swizzle sleepWithCompletionHandler: on QTXPacketTunnelProvider
    Class providerClass = objc_getClass("QTXPacketTunnelProvider");
    if (providerClass) {
        SEL selSleep = sel_registerName("sleepWithCompletionHandler:");
        Method mSleep = class_getInstanceMethod(providerClass, selSleep);
        if (mSleep) {
            method_setImplementation(mSleep, (IMP)hook_tunnel_sleepWithCompletionHandler);
            NSLog(@"[QX_TunnelKeepalive] Hooked sleepWithCompletionHandler: to keep tunnel active!");
        }
    }

    // 4. Start background heartbeat
    start_background_heartbeat();

    NSLog(@"[QX_TunnelKeepalive] Initialization complete.");
}
