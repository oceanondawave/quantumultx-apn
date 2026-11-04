function FindProxyForURL(url, host) {
    // Direct for local and hotspot gateway
    if (isPlainHostName(host) ||
        shExpMatch(host, "*.local") ||
        shExpMatch(host, "172.20.10.*") ||
        shExpMatch(host, "10.*") ||
        shExpMatch(host, "192.168.*") ||
        shExpMatch(host, "127.0.0.1") ||
        shExpMatch(host, "localhost")) {
        return "DIRECT";
    }

    // Tunnel all traffic through Quantumult X SOCKS5 (Port 9988), fallback to HTTP (Port 8899)
    return "SOCKS5 172.20.10.1:9988; SOCKS 172.20.10.1:9988; PROXY 172.20.10.1:8899; DIRECT";
}
