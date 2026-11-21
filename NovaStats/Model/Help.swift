import Foundation

// the same questions are on the website, docs/index.html
enum Help {
    static let about = "Nova Stats is a free, open-source system monitor for the Mac. It shows what the CPU, GPU, memory, disk, network, battery and temperatures are doing, in a dashboard, the menu bar, desktop widgets and, while you play, an overlay on top of the game. It's the sibling of Nova, the network app, and looks like it."

    static let questions: [(String, String)] = [
        ("Is Nova Stats free?",
         "Yes, completely. It's open source under the MIT license, so you can read the code, change it and share it."),
        ("Why does macOS say it can't check the app?",
         "Apple only vouches for apps from developers who pay for a yearly account. Nova Stats isn't signed that way, so the first time macOS blocks it. Open System Settings, go to Privacy & Security, scroll down and press Open Anyway. You only do this once."),
        ("Does it send my data anywhere?",
         "No. Nova Stats never connects to the internet. Everything it measures stays on your Mac."),
        ("Does it slow my Mac down?",
         "Barely. With the dashboard closed it uses about 1–2% of one CPU core: anything you can't see is measured less often. The open dashboard with moving stars uses about 7%; turn the stars off in Settings if you like."),
        ("Where do the temperatures come from?",
         "Straight from the chip's own sensors (the SMC and the system's temperature sensors), the same ones macOS uses to run the fans. The CPU number is the average of the core sensors."),
        ("Which Macs does it work on?",
         "Macs with Apple Silicon (M1 to M5) on macOS 15 or newer. On Intel Macs most numbers work, but some temperatures may be missing."),
        ("What is game mode?",
         "Turn it on from the menu bar or with ⌃⌥G, or let it start by itself when a game goes full screen. While it's on, an overlay shows your stats over the game and warns you if the Mac gets so hot that macOS slows it down. When you stop, you get a report: how long you played and the average and peak CPU, GPU, temperatures and power. macOS doesn't let other apps read a game's FPS, so that isn't shown."),
        ("Can a stress test damage my Mac?",
         "No. Apple Silicon protects itself: when it gets too hot, macOS slows it down, which is exactly what the test shows. Nova Stats also stops a test by itself above 110°, under 20% battery or when its time is up. The SSD test only reads, so it doesn't wear the SSD, and the RAM test never takes so much memory that macOS has to swap."),
        ("Why don't my scores match Geekbench or Cinebench?",
         "Every benchmark uses its own work and its own scale. Nova Stats' scores are for comparing your own runs: plugged in or on battery, before and after an update, or with another Mac running Nova Stats."),
        ("Why do the widgets update only every few minutes?",
         "macOS decides how often widgets may refresh. For numbers that change every second, use the menu bar or game mode's overlay."),
        ("Why are some apps missing from the Apps list?",
         "Without an administrator password macOS only lets an app look at your own processes, not the system's. Everything you run yourself is there."),
        ("Why don't alerts show up?",
         "macOS needs your permission for notifications. Open System Settings, then Notifications, find Nova Stats and allow them. Settings → Alerts has a button that takes you there."),
        ("How do I remove it?",
         "Quit it from the menu bar panel, then drag Nova Stats from Applications to the Bin. Its settings are in ~/Library/Preferences/com.mammadali.novastats.plist."),
    ]

    static let website = URL(string: "https://mammad-ali.github.io/nova-stats/")!
    static let source = URL(string: "https://github.com/Mammad-Ali/nova-stats")!
    static let license = URL(string: "https://github.com/Mammad-Ali/nova-stats/blob/main/LICENSE")!
    static let issues = URL(string: "https://github.com/Mammad-Ali/nova-stats/issues")!
}
