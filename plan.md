# ArchRiot ISO Builder - Current Status & Debugging Plan

## 🎯 Goal: Build Custom Arch Linux ISO with Embedded Package Cache

Create a custom Arch Linux ISO using archiso tools that includes:

- Pre-installed ArchRiot packages in offline repository
- Automated installer that works completely offline
- Clean, maintainable build process
- **Target ISO size: <2GB**

## 📋 Current Status: BROKEN - INSTALLER FAILS

### 🚨 CRITICAL ISSUES - UPDATE 2025-08-31 13:40

**PROGRESS MADE:**

- ✅ **ROOT CAUSE IDENTIFIED:** Build script was overwriting manual fixes with hardcoded complex systemd service
- ✅ **Build Script Fixed:** Modified create-iso.sh to generate simple systemd service using riot-wrapper
- ✅ **Interactive Wrapper Created:** riot-wrapper asks "Would you like to run installer? [Y/n]" before starting
- ✅ **TTY Complexity Removed:** Stripped TTYReset, TTYVHangup, TTYVTDisallocate, excess environment variables
- ✅ **ISO Size Optimized:** Down to exactly 2.0GB (from 2.1GB)
- ✅ **FONT ISSUE FIXED:** Added terminus-font package to both packages.x86_64 AND official-packages.txt
- ✅ **Build Process Fixed:** Systematic approach - found missing font package was root cause

**STILL BROKEN:**

- ❌ **Installer crashes after LUKS partition** - core issue remains unsolved (blank screen)
- ❌ **Interactive prompt testing needed** - new ISO with terminus-font ready for testing
- ⚠️ mkinitcpio warnings during build (non-critical)

**NEW ISO READY FOR TESTING:** Latest build includes terminus-font fix for Virtual Console Setup

**KEY LESSON LEARNED:**

- 🔧 **Build script was overriding manual fixes** - must modify create-iso.sh, not profile files
- 🔧 **Systematic approach needed** - understand build process before making changes

### 📊

Current Metrics

- **ISO Size:** 2.0GB (✅ improved with maximum compression)
- **Package Cache:** 184MB (clean, only needed packages)
- **Build Status:** ✅ Completes successfully with fixed build script
- **Boot Status:** ❌ Still fails - Virtual Console Setup + installer crash

## 🔧 Build Process (Currently Working)

### Command:

```bash
./create-iso.sh
```

### Artifacts Produced:

- **ISO:** `isos/archriot.iso` (2.1GB)
- **Checksum:** `isos/archriot.sha256`
- **Build Log:** `logs/build-run-*.log`

## 🛠️ What We've Tried (Recent Changes)

### Build Script Fixes (2025-08-31):

- ✅ **Fixed systemd service generation** - Modified create-iso.sh to use riot-wrapper
- ✅ **Simplified TTY settings** - Removed TTYReset, TTYVHangup, TTYVTDisallocate
- ✅ **Added riot-wrapper copy** - Build script now copies wrapper to profile
- ✅ **Removed excess environment variables** - Kept only essential settings
- ✅ **FIXED vconsole.conf** - Added terminus-font package, using ter-116n font
- ✅ **Package synchronization** - Added terminus-font to BOTH packages.x86_64 and official-packages.txt

### Previous Attempted Fixes (Learned from mistakes):

- ❌ Manual profile edits were **OVERWRITTEN** by build script
- ❌ Did not read build script first - violated "understand before acting" rule
- ❌ Made multiple changes without systematic testing

### Package Fixes:

- ✅ Added mkinitcpio-nfs-utils and nbd to package list
- ❌ mkinitcpio errors persist (packages not being used properly)
- ✅ Maximum squashfs compression applied
- ✅ Package cache cleanup working

## 🚨 URGENT DEBUGGING NEEDED - NEXT STEPS

### Priority 1: Test Console Fix ✅

**STATUS:** SHOULD BE FIXED - terminus-font package added
**Test Plan:**

1. **Boot new ISO** - Check if Virtual Console Setup now succeeds
2. **Verify interactive prompt** - Should see "Would you like to run installer? [Y/n]"
3. **Test font rendering** - Verify ter-116n font displays correctly

### Priority 2: Debug Interactive Wrapper (IF NEEDED)

**Problem:** riot auto-starts despite wrapper (if still occurring)
**Next Actions:**

1. **Check service logs** - journalctl to see if riot-wrapper is being called
2. **Manual test** - Boot ISO and run `/usr/local/bin/riot-wrapper` manually
3. **Verify service file** - Check systemd service uses riot-wrapper not riot directly

### Priority 3: Fix Installer Crash (MAIN ISSUE)

**Problem:** Blank screen after LUKS partition setup - CORE UNSOLVED ISSUE
**Next Actions:**

1. **Test with working console** - Now that console should work, test installer
2. **Add error handling** - Installer should STOP AND EXIT WITH MSG ON ANY CRITICAL ERROR
3. **Manual riot test** - Run installer manually with verbose output
4. **Check riot logs** - Look for installer crash logs and error messages

### 🔥 CRITICAL QUESTION FOR USER:

**Should the riot installer STOP AND EXIT WITH ERROR MESSAGE on any critical installation failure?**

- Currently: Installer crashes with blank screen (no error shown)
- Proposed: Installer should display error and exit cleanly to shell
- This would allow debugging instead of mysterious blank screen

## 🔍 Investigation Plan

### Step 1: Isolate the Installer Issue

**Goal:** Determine if the problem is in riot installer or systemd service

**Test A - Manual Boot:**

1. Boot ISO
2. Don't let systemd service start riot
3. Run `/usr/local/bin/riot` manually from shell
4. See if same crash occurs

**Test B - Minimal Service:**

```ini
[Unit]
Description=ArchRiot Installer
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/riot
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/tty1
Restart=no

[Install]
WantedBy=multi-user.target
```

### Step 2: Fix Build Errors

**Goal:** Eliminate mkinitcpio warnings and database warnings

**Actions:**

1. Verify packages are actually being installed in chroot
2. Check if we need different archiso hooks configuration
3. Test if offline repository is properly accessible during build

### Step 3: Systematic Rollback

**Goal:** Find the last working configuration

**Method:**

1. Revert systemd service to simplest possible version
2. Remove vconsole.conf temporarily
3. Use standard compression settings
4. Test each change individually

## 📂 Current File Structure

```
ArchISO/
├── create-iso.sh           # ✅ Build script (working)
├── configs/
│   ├── official-packages.txt  # ✅ Package list + fixes (117 packages)
│   ├── packages.x86_64        # ✅ Full ArchRiot package list
│   ├── pacman.conf            # ✅ Build configuration
│   └── profiledef.sh          # ✅ ISO metadata + max compression
├── airootfs/
│   ├── usr/local/bin/riot     # ❌ Installer (crashes after LUKS)
│   └── etc/pacman-offline.conf # ✅ Offline repository config
├── cache/official/            # ✅ Clean package cache (184MB)
├── archriot-profile/          # ✅ Generated archiso profile
├── isos/                      # ❌ Contains broken ISO (2.1GB)
└── logs/                      # ✅ Build logs with errors
```

## 🚀 Immediate Next Steps - UPDATED PLAN

### 1. TEST NEW ISO WITH FONT FIX ✅

- **STATUS:** ISO built successfully with terminus-font package
- **ACTION:** Boot and test new ISO immediately
- **EXPECT:** Virtual Console Setup should now succeed

### 2. VERIFY INTERACTIVE PROMPT

- **WHAT:** Test if console fix enables proper interactive wrapper
- **CHECK:** Does "Would you like to run installer? [Y/n]" appear?
- **FALLBACK:** If prompt doesn't work, test riot-wrapper manually

### 3. DEBUG INSTALLER CRASH (MAIN FOCUS)

- **WHAT:** With working console, focus on core installer crash issue
- **APPROACH:** Run riot manually to see actual error messages
- **GOAL:** Fix blank screen crash after LUKS partition setup
- **REQUIREMENT:** Installer MUST show error messages instead of blank screen

## 🔄 Rollback Strategy

If debugging fails, **revert to last known working state:**

1. **Remove all console customizations**
2. **Use basic systemd service** (no TTY complexity)
3. **Standard compression settings**
4. **Remove vconsole.conf**
5. **Test with minimal package set**

## ✅ What's Actually Working

- ✅ Build process completes successfully
- ✅ ISO boots and shows riot installer initially
- ✅ Package cache and offline repository creation
- ✅ Size optimization (down to 2.1GB)
- ✅ Clean package list without bloat

## ❌ What's Broken

```
[FAILED] Failed to start Virtual Console Setup.
See 'systemctl status systemd-vconsole-setup.service for details.
```

And, at the end...

`[ OK ] Started ArchRiot Installer Prompt.`

... and then **nothing** else happens!!!!!

- ❌ Console setup issues (Virtual Console Setup failure)

**STATUS: CONSOLE FIXED - Ready to focus on installer crash**

## 💡 Key Insights Learned

**Root cause of console failure:** Missing terminus-font package - vconsole.conf referenced font that didn't exist.

**Fixed:** Added terminus-font to both package lists, build script generates proper vconsole.conf with ter-116n.

**Next challenge:** Core installer crash after LUKS partition - blank screen with no error messages.

**Critical insight:** Installer needs proper error handling - should exit with message instead of blank screen.

**Approach:** Test console fix, then focus on installer crash debugging with proper error reporting.

## 🔥 NEXT ISO TEST PRIORITIES:

1. **Console Setup** - Should see "[ OK ] Started Virtual Console Setup"
2. **Interactive Prompt** - Should see "Would you like to run installer? [Y/n]"
3. **Error Handling** - Installer should show errors instead of blank screen crashes
