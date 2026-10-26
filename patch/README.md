# Apple Push Notifications (APNs) Support for Quantumult X

This project reverse engineers how **Stash** handles Apple Push Notification service (APNs) traffic on iOS and applies the complete system-level mechanism to **Quantumult X**, allowing **both APNs push notifications and in-app server pings / latency checks to work simultaneously without trade-offs**.

---

## 1. The Conflict & The Solution

### Why APNs and Ping Previously Conflicted
1. **Apple's APNs Tunnel Rule (iOS 16.4+)**:
   Apple documentation specifies that `excludeAPNs` only takes effect when `includeAllNetworks = true`. If `includeAllNetworks = false`, the iOS kernel bypasses the tunnel for the Apple Push Notification daemon (`apsd`) entirely before packets ever reach `utun`. Therefore, `includeAllNetworks` **must be `YES`** for APNs push notifications to route through the tunnel.
2. **Why Server Ping Failed When `includeAllNetworks = YES`**:
   In Quantumult X, server latency checks are performed by `QTXContainerURLChecker`. It queries `[QTXInterfaceManager currentDefaultInterfaceName]` (which returns `@"en0"`) and binds the socket explicitly to Wi-Fi (`containerAppBoundInterface:@"en0"` and `viaInterface:@"en0"`).
   When `includeAllNetworks = YES` (full-tunnel mode), the iOS kernel packet filter blocks user-space app sockets bound to `en0` (`IP_BOUND_IF`) from reaching public IP addresses, causing ping checks to immediately time out and show "dead".

### The Fix (Making Both Work Concurrently)
1. Set `includeAllNetworks = YES` and `excludeAPNs = NO` on the VPN protocol configuration so `apsd` push packets enter the tunnel.
2. Set `enforceRoutes = NO`, `excludeLocalNetworks = NO`, and `excludeCellularServices = NO`.
3. Hook `QTXInterfaceManager` and `GCDAsyncSocket` inside `Quantumult X.app`:
   - `-[QTXInterfaceManager currentDefaultInterfaceName]` -> returns `nil` when APNs is active.
   - `-[QTXInterfaceManager defaultInterfaceName]` -> returns `nil` when APNs is active.
   - `-[GCDAsyncSocket containerAppBoundInterface:]` & `boundInterface:` -> overrides interface to `nil`.
   - `-[GCDAsyncSocket connectToHost:onPort:viaInterface:withTimeout:error:]` -> overrides `viaInterface` to `nil`.
   - `-[GCDAsyncSocket concurrentConnectToIPAddresses:onPort:viaInterface:withTimeout:error:]` -> overrides `viaInterface` to `nil`.
   - `-[GCDAsyncSocket crs_connectToHost:onPort:viaInterface:withTimeout:error:ipv4Address:ipv6Address:]` -> overrides `viaInterface` to `nil`.
   - `-[GCDAsyncSocket connectToAddress:viaInterface:withTimeout:error:]` -> overrides `viaInterface` to `nil`.
   - `-[GCDAsyncSocket createSocket:connectInterface:boundInterface:errPtr:]` -> overrides `connectInterface` and `boundInterface` to `nil`.
4. Because the sockets are no longer bound to `en0` with `IP_BOUND_IF`, the iOS kernel does not drop them. Latency checks connect normally and report true live ping times, while APNs push notifications route through the proxy!

---

## 2. Configuration Rules & Airplane Mode Reset

1. **Routing Rules in Quantumult X (`quantumult-x.conf`)**:
   Add to `[filter_local]` in `quantumult-x.conf`:
   ```ini
   [filter_local]
   HOST-KEYWORD, push.apple.com, PROXY
   IP-CIDR, 17.0.0.0/8, PROXY, no-resolve
   ```
   *(Replace `PROXY` with your desired proxy policy group name)*

2. **Reset the Existing APNs Connection**:
   iOS maintains a persistent background TCP connection for `apsd`. After enabling APNs and turning on the VPN, **toggle Airplane Mode ON and OFF** once. This terminates the stale direct socket and forces iOS to establish a new APNs session through the Quantumult X tunnel.

---

## 3. Where to See & Toggle the Setting

### In the App UI:
Open Quantumult X -> tap the bottom-right icon -> tap **More Settings / Misc Settings**.
* Right at the **top of the screen**, you will see two polished native iOS cards:
  1. **Apple Push (APNs)**:
     - Live **[ ON / OFF ]** switch.
     - Description: `Route notifications in tunnel`.
     - Subtitle note: `⚠️ Note: only works after toggle off on VPN again`.
  2. **Author & Support**:
     - **👨‍💻 By @oceanondawave**: Tapping opens the author's GitHub profile (`https://github.com/oceanondawave`).
     - **☕ Donate**: Tapping opens a native modal dialog with donation account details (BVBank & Timo with one-tap clipboard copy actions).

### In Configuration File:
You can also set it in `quantumult-x.conf` under `[general]`:
```ini
[general]
include_apns = true   ; (or false)
```

---

## 4. Patched IPA Output

* **File**: `com.crossutility.quantumult-x_1.8.1_apns_patched.ipa`
* Install via TrollStore or re-sign using AltStore, Sideloadly, or Esign.
