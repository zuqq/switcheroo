# switcheroo

Switcheroo is a macOS application that automatically switches your keyboard
layout and natural scrolling settings when input devices are connected or
disconnected.

## Installation

Using Homebrew:

```
brew install zuqq/tap/switcheroo
brew services start zuqq/tap/switcheroo
```

Alternatively, clone this Git repository and run `swift build`.

## Example

Switcheroo's configuration resides at `~/.switcheroo.json`, and follows a
simple JSON-based file format. For example, here is a configuration file with a
single entry that automatically switches to a US keyboard layout and no natural
scrolling if a device with the name `"HHKB-Classic"` is connected:

```json
{
    "entries": [
        {
            "selector": "HHKB-Classic",
            "rules": {
                "input_source": "com.apple.keylayout.US",
                "natural_scroll": false
            }
        }
    ]
}
```

Such a configuration file may have multiple entries, in which case later
entries take precedence over earlier ones.

In order to determine possible values for the keys `"selector"` and
`"input_source"`, run `switcheroo list-devices` and `switcheroo list-input-sources`.

## Troubleshooting

Switcheroo uses Swift's built-in `Logger` type for debug logging. You can view
its output in `Console.app`,[^1] or by running the following command:

```
log stream --level debug --predicate 'subsystem == "switcheroo"'
```

[^1]: Make sure to enable "Include Info Messages" and "Include Debug Messages".
