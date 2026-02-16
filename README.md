# 📦 APKCleaner

A guarded Android debloating utility with APK extraction, integrity hashing, and full rollback lifecycle support.

APKCleaner safely removes unwanted Android packages using ADB — while automatically extracting APKs, generating atomic restore bundles, and verifying integrity with SHA256 hashes.

Unlike simple debloat scripts, APKCleaner validates projected system state before removal and provides full rollback capability without requiring a factory reset.

---

## 🔥 Features

* 🔍 JSON-based package filtering (`recommended`, `advanced`, `oem`)
* 🛡 Critical package protection (prevents removal of core system apps)
* 🧠 Intent-based projected validation (ensures active launcher survives removal)
* 📦 Automatic APK extraction before uninstall
* 🔄 Split APK support (`install-multiple` safe)
* 🔐 Global SHA256 integrity hashing
* ✅ One-click restore verification (`--verify`)
* 🔁 One-click full restore (`--install`)
* 🧪 Dry-run mode
* 🚨 Force override option
* 📊 Post-debloat analysis mode
* 🎨 Colorized CLI interface

---

## 🧩 Requirements

* Linux or macOS
* `adb`
* `jq`
* `sha256sum`
* Android device with USB debugging enabled

---

## 🚀 Installation

Clone the repository:

```bash
git clone https://github.com/DouglasFreshHabian/APKCleaner.git
cd APKCleaner
chmod +x apkclean.sh
```

---

## 📋 Usage

### Scan Device

Build a removal list based on filter:

```bash
./apkclean.sh --scan
```

With filter:

```bash
./apkclean.sh --scan --filter advanced
```

---

### Apply Removal

```bash
./apkclean.sh --apply
```

---

### Apply With APK Extraction (Recommended)

```bash
./apkclean.sh --apply --extract
```

This will:

* Extract all APK files
* Generate a restore bundle
* Create global `SHA256SUMS`
* Create global `verify.sh`
* Create global `install.sh`
* Then proceed with removal

---

### Dry Run (Simulation)

```bash
./apkclean.sh --apply --dry-run
```

---

### Force Mode (Bypass Guardrails)

```bash
./apkclean.sh --apply --force
```

---

### Verify Latest Extraction

Automatically verifies integrity of the most recent extraction bundle:

```bash
./apkclean.sh --verify
```

---

### Install From Latest Extraction

Automatically restores all packages from the most recent extraction bundle:

```bash
./apkclean.sh --install
```

---

### Analyze System After Debloat

```bash
./apkclean.sh --analyze
```

---

### Help

```bash
./apkclean.sh --help
```

---

## 📂 Extraction Structure

When using `--extract`, extractions are stored as:

```
apk_backups/YYYY-MM-DD_HH-MM-SS/
  com.package.one/
    base.apk
    split_config.arm64_v8a.apk
  com.package.two/
    base.apk
    split_config.xxhdpi.apk
  SHA256SUMS
  verify.sh
  install.sh
```

All packages are restored atomically using a single install script.

---

## 🔁 Manual Restore (Optional)

Navigate into a backup directory:

```bash
cd apk_backups/TIMESTAMP
```

Verify integrity:

```bash
./verify.sh
```

Restore all packages:

```bash
./install.sh
```

Split APKs are automatically handled via `adb install-multiple`.

---

## 🛡 Safety Design

APKCleaner prevents common soft-brick scenarios by:

* Blocking removal of critical system packages
* Protecting the active launcher via intent resolution
* Warning if dialer or browser handlers disappear
* Providing atomic rollback capability

This makes it suitable for both daily-driver devices and controlled lab environments.

---

## ⚠️ Disclaimer

APKCleaner uses ADB to uninstall packages for the specified user.
Removing system packages can break device functionality if done carelessly.

Use `--extract` whenever possible.

You are responsible for changes made to your device.

---

## 🧠 Philosophy

APKCleaner is built around:

* Reversibility
* Transparency
* Integrity
* Controlled modification

It is not a blind debloat script.
It is a reversible Android package management tool.

---
## ☕ Support This Project

If **APKCleaner™** helps you manage and safely debloat your Android devices, consider supporting continued development:

<p align="center">
  <a href="https://www.buymeacoffee.com/dfreshZ" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
</p>

<!-- 
 _____              _       _____                        _          
|  ___| __ ___  ___| |__   |  ___|__  _ __ ___ _ __  ___(_) ___ ___ ™️
| |_ | '__/ _ \/ __| '_ \  | |_ / _ \| '__/ _ \ '_ \/ __| |/ __/ __|
|  _|| | |  __/\__ \ | | | |  _| (_) | | |  __/ | | \__ \ | (__\__ \
|_|  |_|  \___||___/_| |_| |_|  \___/|_|  \___|_| |_|___/_|\___|___/
        freshforensicsllc@tuta.com Fresh Forensics, LLC 2026 -->
