# Display Switch

A small macOS helper that makes a monitor follow a USB peripheral switch. It watches for a configured USB device arriving on this Mac, then asks [BetterDisplay](https://betterdisplay.pro/) to select this Mac's monitor input through DDC/CI. Optional [Raycast](https://www.raycast.com/) commands enable, pause, inspect, and test the helper.

Choose a device you normally leave connected to the USB switch, such as a keyboard, as a stable marker for which Mac has the peripherals. Its USB IDs, the monitor name, input code, and settling delays live in a JSON configuration file, so adapting the helper does not require changing or rebuilding its source.

## Requirements and tested setup

- macOS 13 or newer.
- BetterDisplay running with notification-based integration enabled. Development and testing used BetterDisplay 5.0.6; older versions have not been tested.
- A monitor that supports DDC/CI input selection **from the inactive input**, and a display connection that carries those commands.
- A USB switch and a USB device that disconnects from one Mac and appears on the other when switched.
- Raycast is optional. Apple's Xcode Command Line Tools are needed only to rebuild.

I use this setup daily with two Macs, a USB switch, a keyboard as the monitored device, and an Alienware AW3425DW:

| Computer | Monitor input | Example configuration |
| --- | --- | --- |
| Mac mini | HDMI 2 | `config.mini.example.json` |
| MacBook Pro | DisplayPort | `config.macbook.example.json` |

Both examples match USB vendor `0x3297` / product `0x1969` and the monitor name `AW3425DW`. They describe this setup; they are not automatic hardware detection. Other USB devices, switches, monitors, and cable arrangements have not been broadly tested. In particular, being able to change an input while this Mac's picture is displayed does not establish that the monitor accepts commands while displaying the other Mac.

The included universal binary contains Apple silicon and Intel slices. Apple silicon was exercised locally; the Intel slice was compiled and inspected but has not been run on an Intel Mac. The binary is ad-hoc signed and is **not Apple-notarized**. If macOS blocks a downloaded binary, build it locally rather than disabling security checks.

## Install on each Mac

If you already have an earlier helper installed, pause that installation before installing this one so two watchers do not run together.

1. Enable DDC/CI in the monitor's menu. On the AW3425DW, this is **Others → DDC/CI**.
2. In BetterDisplay, enable **Settings → Application → Integration → notification-based integration**. Keep BetterDisplay running and configure it to open at login.
3. Clone the repository:

   ```sh
   git clone https://github.com/leandrooriente/display-switch.git
   cd display-switch
   ```

4. Choose the configuration for **this Mac**. If your hardware matches the examples, run only the corresponding line:

   ```sh
   ./install.sh mini       # Uses config.mini.example.json: HDMI 2
   ./install.sh macbook    # Uses config.macbook.example.json: DisplayPort
   ```

   For different hardware or input mappings, prepare a custom configuration first:

   ```sh
   cp config.mini.example.json config.local.json
   # Edit config.local.json to match this Mac, USB device, and monitor.
   ./install.sh ./config.local.json
   ```

Files ending in `.local.json` are ignored by Git. Keep each Mac's custom configuration local rather than committing it.

The installer validates the configuration and checks read-only communication with BetterDisplay before enabling the helper. It does not immediately change the monitor input. Once installed on both Macs, switch USB away and back: the receiving Mac should ask the monitor to select its configured input after the connection settles.

The MacBook can remain closed if your normal display arrangement supports that. Use the monitor's physical controls to display each Mac and move the USB peripherals to it while installing.

## Configure your hardware

Configuration is per Mac. Both Macs can match the same USB device and monitor, but each needs the input code for its own display connection.

```json
{
  "usbVendorID": 12951,
  "usbProductID": 6505,
  "monitorNameContains": "AW3425DW",
  "inputCode": 18,
  "inputName": "HDMI 2",
  "settleDelaySeconds": 0.8,
  "wakeSuppressionSeconds": 8
}
```

| Field | Purpose |
| --- | --- |
| `usbVendorID` | Required. Numeric USB vendor ID for the monitored device. |
| `usbProductID` | Required. Numeric USB product ID for the monitored device. |
| `monitorNameContains` | Required. A distinctive fragment of the monitor's original name in BetterDisplay. Choose a fragment that matches only the intended monitor. |
| `inputCode` | Required. Numeric DDC input-selection value for this Mac's connection. |
| `inputName` | Optional. A readable input label for status and logs. |
| `settleDelaySeconds` | Optional. Arrival settling delay; defaults to `0.8` seconds. |
| `wakeSuppressionSeconds` | Optional. Time to ignore arrivals after wake; defaults to `8` seconds. |

Use decimal numbers in JSON. USB vendor/product IDs identify a vendor and product model, **not a device serial number**. A firmware change can alter the IDs. No USB device or monitor serial number is required in the configuration.

To find the device IDs locally, open macOS **System Information → Hardware → USB**, select the device, and read **Vendor ID** and **Product ID**. Confirm that this entry disappears and reappears when you move the USB switch. If those values are hexadecimal, convert them in Terminal; for the example IDs:

```sh
printf '%d\n' 0x3297 0x1969
# 12951
# 6505
```

The example input codes are the conventional DDC values `15` for DisplayPort 1 and `18` for HDMI 2. Monitor mappings can differ. Confirm your monitor's mapping using its documentation and BetterDisplay's input controls before relying on the helper. The helper sends input selection through VCP `0x60`.

Validate and inspect a configuration without changing the monitor:

```sh
bin/display-switch validate ./config.local.json
bin/display-switch check ./config.local.json
bin/display-switch watch ./config.local.json --dry-run --once
```

Validation checks the file. `check` queries BetterDisplay without sending an input-change command. The short dry run initializes the USB watcher without sending monitor commands; it does not prove that input switching works. To observe actual switch events, omit `--once`, move USB away and back, and press Control-C afterward. Pause any installed live helper first so it does not switch the monitor while you are testing.

Raw display identifiers are hidden by `check` by default. If you need them to diagnose a monitor match, run:

```sh
bin/display-switch check ./config.local.json --show-identifiers
```

That optional output may include monitor serial numbers or other device identifiers. Keep it local or redact it before posting an issue. Without an explicit configuration path, `check` uses the installed configuration.

## Optional Raycast controls

In Raycast Settings, open **Extensions → + → Add Script Directory** and select:

```text
~/Library/Application Support/Display Switch/raycast
```

The installer prints the expanded path for your account. Each command uses the installed `config.json`:

- **Enable Monitor Follow** — enable automatic switching and start at login.
- **Pause Monitor Follow** — stop switching, including at the next login, until enabled again.
- **Monitor Follow Status** — show the selected input, mode, and recent events.
- **Check BetterDisplay Connection** — perform the read-only display check.
- **Test USB Device Events** — replace live switching with log-only event testing. Run Enable afterward to restore switching.

The helper performs event detection in the background. Raycast does not need to poll or stay open. The same controls are available from Terminal:

```sh
bin/display-switch enable ./config.local.json
bin/display-switch pause
bin/display-switch status
```

## Behavior and sleep/wake

- Observes only USB attachment metadata for the configured vendor/product IDs. It does not read keystrokes or send data over the network.
- Ignores matching devices already connected when the watcher starts.
- Acts on arrival, after the configured settling delay. Disconnection cancels a pending action and does not itself send an input-change command.
- Suppresses events during system sleep and for the configured period after a reported wake.
- Sends at most one retry if BetterDisplay rejects the request or does not answer.

USB events cannot identify a physical button press uniquely. Reconnecting the monitored device or a Mac while the switch selects it can also trigger an arrival. A switch that automatically transfers peripherals when a computer is unplugged creates an arrival on the receiving computer too.

For the tested setup, enabling **automatic input selection on the monitor** fixed switching after a Mac wakes. Wake-related USB arrivals are deliberately suppressed by the helper, so the monitor setting handles that case. Other monitors may behave differently. If a deliberate USB switch during the wake suppression period is ignored, wait for it to end, then switch away and back.

After installation, test both directions while the monitor shows the other Mac, then test sleep/wake and login. Use the monitor's physical controls to recover if necessary. An accepted BetterDisplay request does not establish that the picture changed. If the monitor blocks DDC commands from its inactive input, this arrival-only design needs a different control route.

## Installed files, updates, and removal

Installation is for the current user and requires no administrator privileges:

- `~/Library/Application Support/Display Switch/` — helper, `config.json`, and Raycast scripts.
- `~/Library/LaunchAgents/local.display-switch.plist` — login startup.
- `~/Library/Logs/Display Switch/events.log` — events and command results.

The installed configuration is `~/Library/Application Support/Display Switch/config.json`. The installer copies it, so moving or deleting the repository afterward is fine. To update, pull the repository and run the installer again with your configuration. Keep your custom configuration available; use its path when reinstalling rather than replacing it with an example.

To pause without Raycast:

```sh
"$HOME/Library/Application Support/Display Switch/display-switch" pause
```

After pausing, remove the Application Support and Logs folders above and remove the script directory from Raycast. Pause removes the LaunchAgent so the helper will not return at the next login.

## Troubleshooting and rebuilding

**No BetterDisplay response:** open BetterDisplay and enable notification-based integration. Run checks in your normal logged-in desktop session; a restricted shell or automation environment may not reach the desktop app.

**Monitor not found:** confirm it is connected to this Mac and recognized by BetterDisplay, then check `monitorNameContains` against its original name. Use `--show-identifiers` locally if needed.

**No USB device events:** confirm the monitored device is connected through the USB switch and that the configured IDs match its current USB identity. Dry-run mode can show arrivals without changing the monitor.

**Request accepted but picture unchanged:** check the DDC input code and whether the monitor accepts commands while its other input is active.

To rebuild and check the included binary, install Apple's Xcode Command Line Tools and run:

```sh
./build.sh
./verify.sh
```

The build produces an ad-hoc signed universal binary targeting macOS 13+ and updates `SHA256SUMS`. Verification, validation, and dry-run checks do not install a service or send monitor input-change commands. Real hardware switching still needs the two-direction test described above.

## License and references

MIT License, copyright 2026 Leandro Oriente. See [LICENSE](LICENSE).

References: [BetterDisplay third-party integration](https://betterdisplay.pro/guide/integration/third-party-apps/), [Raycast Script Commands](https://github.com/raycast/script-commands).
