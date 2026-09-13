# Yoda LAN validation

Status: direct Rebirth launch verified; sustained active-gameplay and external tests remain open.

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

## Direct Rebirth launch

Added a Sunshine application named Rebirth with a detached official Steam
`-applaunch 2909400` command. Existing Desktop and Steam Big Picture entries are
preserved; both apps.json and sunshine.conf were backed up on Yoda before edits.
The matching Game Hub target is saved and selected for Steam game 2909400.

A live test exposed two independent issues, both corrected:

- macOS reused an open Moonlight instance without passing the requested stream
  arguments. Stream launches now request a new application instance. A repeat
  test with Moonlight already open reached the Rebirth stream.
- The game rendered on Yoda's second display while Sunshine captured the primary
  desktop. Switching displays revealed gameplay. Sunshine now selects the verified
  game display by its stable device ID. A subsequent tile launch showed gameplay
  directly without entering Desktop or using the display-switch shortcut.

Observed game-display samples: approximately 60 FPS, 1–3 ms network latency,
0.00% network/jitter drops, around 3.2–3.4 ms decode time. These are samples,
not a completed ten-minute active-gameplay benchmark. The stream remains
1920×1080, 60 FPS target, 20 Mb/s, H.264, HDR off.

Game Hub checks the saved host automatically at startup and rechecks a preferred
Home PC before launch. A temporary loopback-address test produced the expected
unavailable-PC error instead of launching local Wine. The real Yoda address was
restored and retested successfully. No router forwarding was added.

## Restricted administration

The owner approved dedicated key-only SSH from this Mac to Yoda's LAN address.
The default broad OpenSSH rule is disabled; the project rule permits only this
Mac, on the Private profile, for the sshd program and TCP 22. Agent/TCP forwarding
are disabled. Host identity was checked through Moonlight before the first SSH
login. Windows account identity, effective sshd configuration, service restart,
automatic startup, and key ACLs were verified. This is a source-restricted
administrative account, not a filesystem sandbox. Keys and host-specific access
receipts remain outside tracked source.

References: [Sunshine application examples](https://github.com/LizardByte/Sunshine/blob/master/docs/app_examples.md),
[Sunshine display configuration](https://docs.lizardbyte.dev/projects/sunshine/master/md_docs_2configuration.html),
[Apple application launch configuration](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration).
