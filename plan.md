# ArchRiot ISO Builder - Current Status & Simple Plan

## 🎯 SIMPLE GOAL

Build a custom Arch Linux ISO that includes:

1. **Standard archiso/releng** (works perfectly every time)
2. **Offline package cache** for ArchRiot packages
3. **Riot installer binary** (manual execution)

That's it. Nothing else.

## 📋 CURRENT STATUS

### ✅ What Works

- **Build process** compl
  etes successfully
- **Package cache** creation (184MB, clean)
- **Riot binary** exists at `airootfs/usr/local/bin/riot`
- **All required config files** exist

### ❌ Current Problem

- **Getty restart loop** on boot: `[ OK ] Started Getty on tty1` repeating endlessly
- **No shell prompt** - system hangs after "Initializes pacman keyring"
- **Same issue persists** through all attempted fixes

### 🗂️ Current File State

- **Package list:** `configs/official-packages.txt` (105 packages)
- **Riot installer:** `airootfs/usr/local/bin/riot` (working binary)
- **Config files:** All present in `configs/`
- **Git repo:** Currently messy from multiple restore attempts

## 🔧 SIMPLE SOLUTION APPROACH

### What We Need

1. **Clean git state** - reset to known good state
2. **Minimal create-iso.sh** that does ONLY:
    - Copy standard releng profile
    - Add package cache to `/opt/archriot-cache/`
    - Add riot binary to `/usr/local/bin/riot`
    - Create offline pacman.conf pointing to cache
    - **NO systemd services, NO getty overrides, NO automation**

### Expected Result

- **Standard archiso boot** with autologin to root shell
- **Manual execution:** User types `riot` to run installer
- **Offline installation:** Uses cached packages

## 🚨 ROOT CAUSE ANALYSIS

The getty restart loop suggests something is **crashing the boot process**, not just a getty configuration issue.

**Possible causes:**

1. **Corrupted build artifacts** in current workspace
2. **Package conflicts** or dependency issues
3. **Systemd conflicts** from lingering service files
4. **Build script bugs** that corrupt the ISO

## 📝 IMMEDIATE NEXT STEPS

### 1. Clean Git State

- Reset git to clean working state
- Remove build artifacts (cache/, out/, etc.)
- Identify what files actually need to be in git

### 2. Create Minimal Working Script

- Strip create-iso.sh to absolute basics
- No automation, no services, no getty overrides
- Just: releng + cache + riot + pacman.conf

### 3. Test Minimal Build

- Build with minimal script
- If getty loop persists, it's not configuration related
- If it works, we have the baseline

### 4. Debug Boot Process (If Still Broken)

- Enable debug logging: `loglevel=7 systemd.log_level=debug`
- Add debug shell: `systemd.debug-shell=1` (tty9 access)
- Capture actual boot logs to identify crash point

## 🔄 FALLBACK PLAN

If minimal approach still fails:

1. **Test pure releng** - build unmodified archiso to confirm base works
2. **Add components incrementally** - cache first, then riot, then pacman.conf
3. **Identify regression point** - find exactly what breaks it

## ✅ SUCCESS CRITERIA

**Working system should:**

- Boot to root shell prompt
- Allow manual execution of `riot`
- Install packages from offline cache
- Complete ArchRiot installation offline

**NO automation, NO services, NO complexity.**

## 📊 CURRENT METRICS

- **Target ISO size:** <2GB
- **Package count:** 105 packages
- **Cache size:** 184MB
- **Build time:** ~45-60 minutes

---

**KEEP IT SIMPLE. ARCHISO WORKS. WE'RE JUST ADDING FILES.**
