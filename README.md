# Narrate

A small Mac menu bar app for talking through what you're seeing while you investigate something.

Anything you copy while you're recording (a link, a log line, a stack trace) is dropped into your narration at the point where you copied it. When you stop, the whole narration is on your clipboard, ready to paste into Claude, a ticket, or a message.

- Lives in the **menu bar** as a speech-bubble icon. No Dock icon, no windows.
- Transcription uses **Apple's built-in on-device speech recognition**. There's no model to download, no third-party service, and audio never leaves your Mac.
- No browser extension needed.

---

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools: the free compiler tools from Apple. Not the full Xcode app.

Check whether you already have the tools:

```bash
swiftc --version
```

If that prints a version, you're set. If not, install them, which takes a few minutes:

```bash
xcode-select --install
```

---

## Install

```bash
git clone https://github.com/xiaoniuniu89/narrate.git ~/narrate
cd ~/narrate
./build.sh
```

**No git?** Put the files (`main.swift`, `Info.plist`, `build.sh`, `icon.png`) in a folder called `~/narrate`, then run `cd ~/narrate && chmod +x build.sh && ./build.sh`.

`build.sh` compiles the app, installs it in `/Applications` and opens it. When it's done, you'll see a speech-bubble icon in your menu bar, next to wifi and battery.

From then on, you can open Narrate from **Applications**, **Spotlight** or **Launchpad**, like any other app.

### Update

```bash
cd ~/narrate
git pull
./build.sh
```

This replaces the installed app and restarts it. Your vocabulary is kept.

---

## First-time setup

1. **Turn on Dictation:** System Settings → Keyboard → Dictation. Narrate uses the speech engine that comes with it. The first time, macOS downloads speech files in the background, so give it a minute.
2. **Allow permissions:** the first time you record, macOS asks for **Microphone** and **Speech Recognition** access. Allow both.
3. **Optional, start at login:** System Settings → General → Login Items → **+** → choose Narrate.

---

## How to use it

1. **Start:** click the speech bubble in the menu bar and choose **Start narrating**, or press **⌃⌥⌘N** (Control-Option-Command-N) from any app.
2. **Talk and work:** a red stop button appears on screen. Keep browsing, reading logs and copying things as normal. The button never takes focus away from what you're doing, and you can drag it out of the way.
3. **Stop:** click the red button, or press **⌃⌥⌘N** again. It turns orange for a moment while it finishes transcribing, then disappears. You'll hear a chime when the narration is on your clipboard.
4. **Paste** wherever you need it.

Example output:

```
# Narration 2026-10-23 23:05

I'm looking at GitHub and now I'm gonna copy something

[copied]
~~~
About
No description, website, or topics provided.
~~~

OK so I copied that, it was just the about section
```

Short copies appear inline as `[copied] …`. Multi-line copies, like stack traces, go in a fenced block.

### Menu

| Item | What it does |
| --- | --- |
| Start narrating / Stop & copy | Same as ⌃⌥⌘N |
| Edit vocabulary… | Opens your vocabulary list in TextEdit |
| Open last narration | Opens the most recent narration, in case the clipboard lets you down |
| Quit Narrate | Quits the app |

### Sounds

- *Tink*: recording started
- *Pop*: stopped, finishing transcription
- *Glass*: narration is on your clipboard

---

## Vocabulary

Apple's speech recognizer doesn't know most technical terms, so `useEffect` can come out as "use effect". Your vocabulary list tells it which words to expect and how to spell them.

**Everyone's list is their own.** It lives only on your Mac, and editing it doesn't affect anyone else. The first time you run Narrate, it creates a starter list of common web-dev terms: React and TypeScript hooks, DevTools words like CORS and payload, and CI/Git terms like TeamCity and pull request. There's an empty section at the bottom for your own.

To edit it:

1. Menu bar → **Edit vocabulary…**
2. Add one term per line, spelled exactly the way you want it to appear, e.g. `PolicyCenter` or `useQuery`. Lines starting with `#` are ignored.
3. Save. The change applies from your next recording, with no rebuild needed.

Tips:
- Add the names of your company's products, internal tools, services and teammates. These are what the recognizer gets wrong most often.
- Remove terms you never say. A shorter, relevant list works better than a huge one.
- If a word still comes out wrong, try adding a phrase you'd naturally say it in as well, e.g. `useEffect hook`.

---

## Where things are saved

Everything lives in one hidden folder:

```
~/Library/Application Support/Narrate/
├── vocab.txt   your vocabulary list
└── last.md     the most recent narration (overwritten each time)
```

Nothing else is kept. You can open both files from the menu, so you never need to go into this folder.

---

## Uninstall

```bash
killall Narrate
rm -rf /Applications/Narrate.app ~/Library/Application\ Support/Narrate ~/narrate
```

---

## Troubleshooting

**No speech in the output, only copied items**
Check System Settings → Privacy & Security → **Microphone** and **Speech Recognition**, and make sure Narrate is switched on in both. Make sure Dictation is on (System Settings → Keyboard). Then quit Narrate from the menu and open it again.

**Build fails with "could not build module 'Foundation'"**
Your Command Line Tools don't match your macOS version, which is common after a macOS update. Reinstall them, then run `./build.sh` again:
```bash
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

**Dictation is greyed out in System Settings**
Your Mac's management profile has disabled it. Narrate needs Dictation's speech engine, so it can't transcribe on that machine.

**macOS says the app "can't be opened"**
Go to System Settings → Privacy & Security, scroll down, click **Open Anyway**, then open Narrate again.

**⌃⌥⌘N does nothing**
Another app may already use that shortcut. Use the menu bar item instead.
