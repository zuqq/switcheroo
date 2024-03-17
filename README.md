# switcheroo

Switcheroo is a macOS application that automatically switches your keyboard
layout and natural scrolling settings when input devices are connected or
disconnected.

## Installation

Using Homebrew:

```bash
brew install zuqq/tap/switcheroo
brew services start zuqq/tap/switcheroo
```

Alternatively, clone this Git repository and run `swift build`.

## Example

Switcheroo's configuration file resides at `~/.switcheroo.json` and adheres to a
simple, JSON-based format. For example, here is a configuration file that
instructs Switcheroo to switch to a US keyboard layout if `"HHKB-Classic"` is
connected and to turn off natural scrolling if `"SteelSeries Rival 3"` is
connected:

```json
{
    "entries": [
        {
            "selector": "HHKB-Classic",
            "rules": {
                "input_source": "com.apple.keylayout.US"
            }
        },
        {
            "selector": "SteelSeries Rival 3",
            "rules": {
                "natural_scrolling": false
            }
        }
    ]
}
```

Later entries take precedence over earlier ones if there are conflicts.

Run `switcheroo list-devices` and `switcheroo list-input-sources` to determine
possible values for the keys `"selector"` and `"input_source"`.

Note that Switcheroo reads in its configuration file only once, right when it
starts up. To check that you have configured Switcheroo to its liking, run the
`switcheroo` command and wait for "Entering main loop." to appear in its output.

## Troubleshooting

Switcheroo uses Swift's built-in `Logger` type for debug logging. You can view
its output in `Console.app`,[^1] or by running the following command:

```bash
log stream --level debug --predicate 'subsystem == "switcheroo"'
```

[^1]: Make sure to enable "Include Info Messages" and "Include Debug Messages".
