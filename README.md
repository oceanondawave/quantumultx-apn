# Quantumult X APNs Proxying Patch (iOS)

[![Platform](https://img.shields.io/badge/Platform-iOS%2014.0%2B-blue.svg)](https://apple.com)
[![Quantumult X](https://img.shields.io/badge/Quantumult%20X-v1.8.1-red.svg)](https://apps.apple.com/app/quantumult-x/id1453926890)
[![Author](https://img.shields.io/badge/Author-%40oceanondawave-purple.svg)](https://github.com/oceanondawave)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Adds full native **Apple Push Notification service (APNs)** tunnel routing support to **Quantumult X** (v1.8.1), matching the behavior of **Stash iOS**, with an in-app settings card in Misc Settings and **concurrent server latency check (ping) support without trade-offs**.

---

## 🌟 Features

* **Complete APNs Routing**: Routes Apple Push Notification daemon (`apsd` / TCP port 5223 / `17.0.0.0/8` / `push.apple.com`) into the Quantumult X tunnel.
* **Dual Concurrency (APNs + Latency Check)**: Fully resolves the iOS kernel full-tunnel packet filter drop on interface-scoped sockets (`IP_BOUND_IF`). Both APNs push notifications and live in-app server latency checks (pings) work simultaneously.
* **Native In-App UI**:
  * **Apple Push (APNs)** toggle switch card placed directly at the top of **Misc Settings / More Settings**.
  * Dynamic preference synchronization with `NETunnelProviderManager`.
  * Status note: `⚠️ Note: only works after toggle off on VPN again`.
* **Author & Support Card**:
  * **👨‍💻 By @oceanondawave**: Direct link to GitHub profile.
  * **☕ Donate**: Native iOS modal displaying concise donation details (BVBank & Timo) with one-tap clipboard copy actions.
* **Sideload Bug Fixes**: Completely eliminates the `scrollToVersionLabel` out-of-bounds index path crash on sideloaded/unactivated instances.

---

## 📥 Download & Releases

Download the latest pre-patched IPA and ZIP assets directly from the [**GitHub Releases**](https://github.com/oceanondawave/quantumultx-apn/releases/latest) section:
* **GitHub Release**: [**v1.8.1-apns**](https://github.com/oceanondawave/quantumultx-apn/releases/tag/v1.8.1-apns)
* **Direct IPA Download**: [`com.crossutility.quantumult-x_1.8.1_apns_patched.ipa`](https://github.com/oceanondawave/quantumultx-apn/releases/download/v1.8.1-apns/com.crossutility.quantumult-x_1.8.1_apns_patched.ipa)
* **Direct ZIP Download**: [`com.crossutility.quantumult-x_1.8.1_apns_patched.ipa.zip`](https://github.com/oceanondawave/quantumultx-apn/releases/download/v1.8.1-apns/com.crossutility.quantumult-x_1.8.1_apns_patched.ipa.zip)

Install via **TrollStore** (recommended) or re-sign using **AltStore**, **Sideloadly**, or **Esign**.

---

## 🛠️ How It Works

### The NetworkExtension Conflict
1. **Apple's APNs Tunnel Rule (iOS 16.4+)**:
   `excludeAPNs = NO` **only takes effect when `includeAllNetworks = YES`**. When `includeAllNetworks = NO`, the iOS kernel bypasses the VPN tunnel for the Apple Push Notification daemon (`apsd`) before packets ever reach `utun0`. Therefore, `includeAllNetworks` must be `YES`.
2. **The Server Ping Conflict**:
   In stock Quantumult X, server latency checks are performed by `QTXContainerURLChecker`. It queries `[QTXInterfaceManager currentDefaultInterfaceName]` (which returns `@"en0"`) and binds the socket explicitly to Wi-Fi (`containerAppBoundInterface:@"en0"` and `viaInterface:@"en0"`).
   When `includeAllNetworks = YES` (full-tunnel mode), Apple's kernel packet filter blocks user-space app sockets bound to `en0` (`IP_BOUND_IF`) from communicating with external IP addresses to prevent VPN leaks. As a result, every server ping timed out and showed as "dead".

### The Concurrent Fix
1. Sets `includeAllNetworks = YES` and `excludeAPNs = NO` on the VPN protocol so push traffic routes into the tunnel.
2. Sets `enforceRoutes = NO`, `excludeLocalNetworks = NO`, and `excludeCellularServices = NO`.
3. Dynamically hooks `QTXInterfaceManager` and `GCDAsyncSocket` inside `Quantumult X.app`:
   * `-[QTXInterfaceManager currentDefaultInterfaceName]` & `defaultInterfaceName` -> returns `nil` when APNs is active.
   * `-[GCDAsyncSocket containerAppBoundInterface:]` & `boundInterface:` -> overrides interface to `nil`.
   * `-[GCDAsyncSocket connectToHost:onPort:viaInterface:withTimeout:error:]` -> overrides `viaInterface` to `nil`.
   * `-[GCDAsyncSocket concurrentConnectToIPAddresses:onPort:viaInterface:withTimeout:error:]` -> overrides `viaInterface` to `nil`.
   * `-[GCDAsyncSocket crs_connectToHost:onPort:viaInterface:withTimeout:error:ipv4Address:ipv6Address:]` -> overrides `viaInterface` to `nil`.
   * `-[GCDAsyncSocket connectToAddress:viaInterface:withTimeout:error:]` -> overrides `viaInterface` to `nil`.
   * `-[GCDAsyncSocket createSocket:connectInterface:boundInterface:errPtr:]` -> forces `boundInterface = nil` and `connectInterface = nil`.
4. Because the sockets are no longer bound to `en0` via `IP_BOUND_IF`, the iOS kernel does not drop them. Latency checks connect cleanly through the routing table, while APNs push notifications route through the proxy!

---

## ⚙️ Configuration & Usage

### 1. Add Filter Rules in `quantumult-x.conf`
Add to `[filter_local]` in `quantumult-x.conf`:
```ini
[filter_local]
HOST-KEYWORD, push.apple.com, PROXY
IP-CIDR, 17.0.0.0/8, PROXY, no-resolve
```
*(Replace `PROXY` with your desired proxy policy group name)*

### 2. Connect & Reset Push Connection
1. Open Quantumult X -> tap the bottom-right icon -> **More Settings / Misc Settings**.
2. Ensure **Apple Push (APNs)** is toggled **ON**.
3. Turn the VPN **ON**.
4. **Toggle Airplane Mode ON and OFF once**.
   *(iOS maintains a persistent background TCP connection for `apsd`. Toggling Airplane mode terminates stale direct sockets and forces iOS to establish a new APNs session through the Quantumult X tunnel).*
5. Open your Server List and test ping — all servers will respond with live latency, and push notifications will arrive via your proxy.

---

## 🔨 Building from Source

### Prerequisites
* macOS with Apple Clang (`clang -target arm64-apple-ios14.0`)
* Decrypted Quantumult X v1.8.1 IPA placed in repository root

### Build Command
```bash
cd patch
./build_and_patch.sh
```

---

## ☕ Support & Donations

If you appreciate this work, consider buying the author a coffee:

* **Author**: Minh Tri Nguyen ([@oceanondawave](https://github.com/oceanondawave))
* **Ngân hàng Bản Việt (BVBank)**: `9021622808735` — *NGUYEN TRI MINH*
* **Ngân hàng Timo**: `0965567003` — *NGUYEN TRI MINH*
* **Project Reference**: [Zablind](https://oceanondawave.github.io/zablind/)

---

## 📄 License

This patch is distributed under the MIT License for educational and research purposes.
Quantumult X is the property of Cross Utility.
