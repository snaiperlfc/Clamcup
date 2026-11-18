# Changelog

## 1.0.2

- The panel shrinks back when its content gets shorter. Before, an empty band stayed at the top after the helper card disappeared, for example right after installing the helper.

## 1.0.1

- The helper installer writes only into a root-owned folder. If something other than a plain file sits in place of the mode file, the installer removes it instead of following it.
- The installer checks the version it is given.
- README: a Security section.

## 1.0.0

First public release.

- Menu bar app with a panel: power, lid and sleep state, the main switch, launch at login.
- The app installs, updates and removes its helper itself, through the standard administrator password prompt.
- Helper in Swift: reacts to power source changes and mode changes immediately, re-checks every 60 seconds.
- Unplugged with the lid closed: the Mac goes to sleep right away.
- English and Russian.
