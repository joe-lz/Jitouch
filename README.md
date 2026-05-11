# Jitouch

**Jitouch** is a Mac application that expands the set of multi-touch gestures for MacBook, Magic Mouse, and Magic Trackpad. These thoughtfully designed gestures enable users to perform frequent tasks more easily such as changing tabs in web browsers, closing windows, minimizing windows, changing spaces, and a lot more.

For more details, see https://www.jitouch.com/.

## Installation

Download `Jitouch Modern.app` from the [releases](https://github.com/aaronkollasch/jitouch/releases/latest) page.
Move it to your Applications folder and open it.

## Troubleshooting

When opening Jitouch for the first time, macOS should prompt you to grant accessibility permissions. If the prompt does not appear, open Jitouch and grant permissions manually.

#### To manually give Jitouch permissions:
- Open System Settings and go to "Privacy & Security -> Accessibility".
- Add `Jitouch Modern.app` to the list and enable it.
- Force restart Jitouch with `killall Jitouch` in the Terminal.

## How to build from source

1. Open `jitouch/Jitouch/Jitouch.xcodeproj` in Xcode.
2. Select the `Jitouch` scheme.
3. Build the project. For the highest performance, set the Build Configuration to Release.
4. Move the built `Jitouch Modern.app` to your Applications folder.

## License

Copyright (c) Supasorn Suwajanakorn and Sukolsak Sakshuwong. All rights reserved.  
Modified work copyright (c) Aaron Kollasch. All rights reserved.

Licensed under the [GNU General Public License v3.0](LICENSE).
