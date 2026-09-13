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
