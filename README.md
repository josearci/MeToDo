# MeToDo

A minimal macOS to-do app that lives in your menu bar.

## Install / update

```bash
./install.sh
```

Builds the app, installs it to `/Applications/MeToDo.app` and launches it. Re-run after any change; your tasks are kept.

## Where your data lives

`~/Library/Application Support/MeToDo/data.json`, plus `data.json.bak`, which is the copy from the last successful launch. Copy that folder to back up.

## Uninstall

Quit from the menu bar ⚙︎ menu, then delete `/Applications/MeToDo.app` (and the data folder above if you want).

## Develop

`swift test` runs the core tests. Don't use `swift run`: notifications need the app bundle, so use `./install.sh`.
