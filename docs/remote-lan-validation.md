# Yoda LAN validation

Status: incomplete; connection stability failure remains open.

Moonlight 6.1.0 is paired with Yoda. Desktop and Steam applications are visible.
The owner requested 1920 × 1080 with HDR disabled. Baseline test settings were
1080p, 60 FPS target, 20 Mb/s, H.264, HDR off, performance statistics enabled.

The Steam session displayed the Windows desktop and Steam updater, followed by
an incompletely rendered Steam library. The session lasted approximately 88 seconds
from first video to an unexpected control-stream disconnect (error -1).
The next attempt failed establishing ENet control on UDP 47999 (error 35).
Neither error alone establishes a firewall fault. PC-side Sunshine logs and service
state are needed. Router port forwarding is not required for this LAN test.

Client summary from the failed session:

| Metric | Observed |
|---|---|
| Incoming / rendered | 29.74 / 29.64 FPS |
| Host processing average | 2.40 ms (maximum 222.60 ms) |
| Network latency | 3 ms, variance 1 ms |
| Network dropped frames | 0.00% |
| Jitter dropped frames | 0.23% |
| Decode / render average | 3.20 / 1.53 ms |
| Mac decoding | VideoToolbox hardware, Metal renderer |

This desktop/startup sample is not gameplay acceptance, a 60 FPS pass, or a
sustained packet-loss test. Host GPU/encoder, audio, controller, ten-minute gameplay,
and an external direct Tailscale path remain unverified. No firewall, router,
credentials or pairing records were modified during this test.

Raw client logs remain local; private addresses and account details are excluded here.

## Recovery and owner acceptance

A subsequent Desktop connection succeeded without changing firewall/router policy.
Rebirth was launched from Yoda's installed Steam copy after its cloud status showed
up to date. Gameplay was visibly rendered at approximately 60 FPS, and the owner
reported that it worked well and the controller was supported.

The resumed Desktop session ended with a normal quit event. Its aggregate included
idle desktop, Steam startup and gameplay, so its 39.27 incoming / 39.21 rendered FPS
is not a gameplay benchmark. Summary: 4 ms network latency (variance 0 ms),
0.00% network drops, 0.10% jitter drops, 3.04 ms decode, 1.34 ms render, and
2.50 ms average host processing. The session did not establish a ten-minute test.

Game Hub's own TCP reachability retest succeeded at 18 ms. Mac Local Network
permission for Game Hub was already on. No permission change was needed for that
check. The earlier transient disconnect remains recorded; its root cause is unknown.

The owner prefers direct game launch over entering Desktop. A dedicated Sunshine
Rebirth entry and matching Game Hub target remain to be configured and verified.
