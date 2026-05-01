# Aquarium

Aquarium is a small macOS menu bar utility for keeping a Mac awake when the lid is closed. It can also turn the internal display brightness down while closed, limit the behavior to selected apps or processes, and stop itself around battery thresholds.

<img width="420" height="577" alt="image" src="https://github.com/user-attachments/assets/f3958dfd-788f-4fec-bdb5-59534ca65ade" />


## Install

```sh
brew install --cask zimengxiong/tools/aquarium
```

> [!WARNING]
> Aquarium is not notarized yet. If macOS blocks the first launch, remove Gatekeeper quarantine from the installed app:

```sh
xattr -dr com.apple.quarantine /Applications/Aquarium.app
```

Open Aquarium after installing. The app installs or updates its privileged helper on launch, and macOS will ask for administrator approval because the helper writes the system `pmset disablesleep` setting.

Build from source with `make build`, then run the debug app with `make open`. Install the privileged helper with `make install-helper`.

For a release build, run `make package`. The packaged app is written to `.build/Aquarium-0.1.0.zip`.

Aquarium requires macOS 14 or newer. The default safety settings only start above 20% battery and auto-disable below 10%.
