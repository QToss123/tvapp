# Unified Platform Handoff

## Document Purpose
This handoff standardizes cross-platform implementation and release flow for `<project_name>` using one unified release branch.

Use this document as:
- an internal engineering handoff
- a Cursor task prompt source
- a PR/QA checklist baseline across Android, Windows, and Linux

---

## 1) Objective
Build and maintain one release branch for all platforms (Android, Windows, Linux), while keeping platform-specific behavior isolated in a dedicated layer.

### Required outcome
- Shared business logic and feature flow remain common.
- OS-level behavior is centralized (not scattered across screens).
- Packaging and release steps are platform-specific but cleanly separated.

---

## 2) Core Product Flow Requirement (Reader + Encryption)

### Functional requirement
For downloaded books:
1. Unzip first.
2. Book is mostly plain, but encrypted content exists under `resources/`.
3. Decrypt encrypted resources on demand while serving files.
4. Load book using local HTTP serving path / platform launcher.

### Why this model
- Avoid heavy full-file decrypt where not needed.
- Support large books with better memory behavior.
- Keep compatibility with mixed plain + encrypted asset structure.

---

## 3) Architecture Rules (Must Follow)

### 3.1 Platform abstraction layer
Create/maintain:
- `platform_reader_launcher`
- `platform_storage_paths`
- `platform_device_identity`
- `platform_permissions`

All `Platform.isX` checks should live inside this layer.

### 3.2 UI layer policy
Screens/widgets should call interfaces only:
- No direct platform branching in Home/Settings/Reader screens (except temporary migration points).

### 3.3 Service contracts (recommended)
- `ReaderLaunchService.openBook(BookOpenRequest request)`
- `StoragePathService.getDefaultDownloadPath()`
- `PermissionService.ensureStorageAccess()`
- `DeviceIdentityService.getStableDeviceId()`

---

## 4) Linux-Specific Handling to Preserve

### Reader launching
- Linux may use external browser for stability.
- Windows/Android can remain in embedded WebView if stable.

### File system behavior
Linux browse roots should include typical mount points:
- `/`
- `/home`
- `/mnt`
- `/media`
- `/run/media`

### Default storage path
- Linux default: `$HOME/Downloads`

### Device identity
- Linux identity can use machine ID + MAC fallback strategy.

### Build/release
- Linux release bundle and `.deb` packaging should remain script-driven and reproducible.

---

## 5) Encryption + Serving Design (Implementation Guidance)

### 5.1 Decryption boundary
- Only files flagged encrypted should be decrypted.
- Fallback rule: paths under `resources/` are encrypted.
- If manifest exists, manifest encrypted list has priority.

### 5.2 Recommended sequence in reader
1. Resolve book file path.
2. Unzip archive to temp extracted directory.
3. Locate `index.html`.
4. Load decryption key material (if metadata present).
5. Start local HTTP server.
6. For each request:
   - if encrypted path: decrypt bytes then respond
   - else: stream plain file
7. Build reader URL and launch by platform policy.

### 5.3 Fallback path
- If unzip-first fails (for example, fully encrypted archive), fallback to full decrypt-then-unzip legacy path.
- Keep this fallback for backward compatibility.

---

## 6) Performance and Stability Requirements

### Must-have
- Avoid reading huge files into memory unnecessarily.
- Stream plain files when possible.
- Enforce decrypt size guards for large assets.
- Use background isolate for heavy unzip/decrypt where needed.
- Clean up temp extracted/decrypted files safely on dispose/exit.

### Nice-to-have
- Cache selected decrypted assets (small CSS/JS/HTML/video chunks) for repeated requests.
- Add decrypt diagnostics logging behind debug flag.

---

## 7) Branching / Merge Strategy

### Branch policy
- One main release branch: `<branch_name>` (example: `release_unified`)
- Short-lived feature branches merged into unified branch

### Merge checklist (every platform-impacting PR)
- [ ] Linux reader path works
- [ ] Windows reader path works
- [ ] Android reader path works
- [ ] Encrypted `resources/` assets decrypt correctly
- [ ] Plain assets are not decrypted
- [ ] No platform-specific logic leaked into UI
- [ ] Packaging scripts still pass (`linux`/`windows` installers as applicable)

---

## 8) Test Matrix (Minimum)

### Functional
- [ ] Plain zip book opens end-to-end
- [ ] Mixed encrypted `resources/` book opens end-to-end
- [ ] Missing/invalid key shows user-safe error message
- [ ] Missing `index` shows proper error
- [ ] Local server serves paths case-insensitively where required

### Platform
- [ ] Linux: launch + read + navigation + external/internal launcher path
- [ ] Windows: launch + in-app reader + navigation
- [ ] Android/TV: launch + navigation + memory stability

### Regression
- [ ] License flow unaffected
- [ ] Sync/download flow unaffected
- [ ] Storage path selection unchanged behavior

---

## 9) Packaging/Release Instructions (Template)

### Linux
Build release:

```bash
flutter build linux --release
```

Create deb:

```bash
bash scripts/build_linux_installer.sh
```

Install test:

```bash
sudo dpkg -i build/<package_name>_<version>_amd64.deb
sudo apt-get install -f
```

### Windows
- Keep Windows packaging flow in dedicated script/tooling.
- Do not mix installer logic into runtime code.

### Android
- Keep existing signing/build pipeline intact.
- Validate TV behavior where applicable.

---

## 10) Cursor Task Prompt (Copy-Paste)
Use this prompt in Cursor for the different project:

> We need one unified release branch for Android, Windows, Linux.
> Implement/refactor platform handling so OS checks are centralized in platform services, not spread in UI.
> Reader flow must be: unzip first, decrypt only encrypted resources paths (default resources/), serve through local HTTP, then launch reader per platform policy (Linux external browser if needed; others in-app if stable).
> Preserve backward-compatible fallback (full decrypt then unzip) for legacy encrypted archives.
> Add/update tests or validation checklist.
> Do not break existing license/sync/settings flows.
> Provide a final change summary with files touched, platform behavior matrix, and release verification commands.

---

## 11) Project-Specific Values
Replace placeholders before rollout:
- `<project_name>`: project/repository name
- `<branch_name>`: unified release branch name
- `<package_name>`: Linux package artifact base name
- `<version>`: semantic version/release build version

---

## 12) Ownership and Sign-off
- Engineering owner: `<owner_name>`
- QA owner: `<qa_owner_name>`
- Release manager: `<release_manager_name>`
- Last reviewed date: `<yyyy-mm-dd>`

