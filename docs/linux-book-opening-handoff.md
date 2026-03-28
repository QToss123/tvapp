# Linux book opening — detailed logic (handoff for other projects)

This document describes **how book opening can work on Linux** (external browser + loopback HTTP), matching the encryption/serving model in this codebase, so you can replicate or debug the same flow in another project.

---

## 0) Status in *this* repository (`tv_app_books`)

Sections 1–9 describe the **Linux external-browser + loopback HTTP** design. **This repo implements that design** in `lib/screens/reading_screen.dart`:

- On **Linux**, **`WebViewController` is not created** for the reader (`_initializeWebView` returns early and schedules `_startLoadingContent` only).
- **Local books** (`file://`, raw paths): unzip / decrypt path → `_startLocalServer` → build `http://127.0.0.1:<port>/...` → **`WebLauncherService.openWebContent`** (system browser).
- **Remote `http`/`https` books**: same **`WebLauncherService.openWebContent`** path on Linux.
- **`assets/...`** and other non-local URLs that relied on in-app WebView show a clear error on Linux (“can’t be opened in the browser”).
- While the book is open, the UI shows **“Book opened in your browser”** and reminds the user to **keep the app open** so the local server stays up.
- **Windows** still uses **embedded WebView** with `file://` first and **`_linuxHttpFallbackUrl`**-style HTTP fallback (Windows-only; name is historical).

When copying this doc to another project, mirror the same sequence; **Windows/Android** behavior may differ (see §1 table).

---

## 1) High-level behavior on Linux (different from Windows/Android)

| Aspect | Linux (target / handoff pattern) | Windows / Android (reference) |
|--------|-----------------------------------|-------------------------------|
| Embedded WebView for the book | **Not used** for local books | WebView loads `file://` or `http://127.0.0.1` |
| Where the book UI runs | **System default browser** (Chrome, Firefox, etc.) | Inside the app WebView |
| Local HTTP server | **Yes** — must be running **before** opening the browser | Same server; WebView talks to it in-process |
| `contentUrl` types | `file://` and raw paths work for local books; `assets/` and non-URL asset paths show errors | Assets can load in WebView |

**Critical implication:** On Linux the Flutter process **binds `HttpServer` to `127.0.0.1`** and then **`url_launcher` opens `http://127.0.0.1:<port>/...` in an external process**. The browser must be able to reach that loopback server while the app keeps running (and keeps the server open).

---

## 2) Entry points in code (this repo)

| Step | File | What happens on Linux (this repo) |
|------|------|----------------------------------|
| Init | `lib/screens/reading_screen.dart` → `_initializeWebView()` | **Linux:** no `WebViewController`; post-frame calls `_startLoadingContent()`. **Other platforms:** WebView created as before. |
| Route content | `_startLoadingContent()` | **`http(s)://`** → `_openRemoteUrlInLinuxBrowser` → `WebLauncherService`. **`file://` / local path** → `_loadFile()`. **`assets/`** → error. |
| Local book load | `_loadFile()` | Unzip/decrypt flow → `_startLocalServer()` → **`WebLauncherService.openWebContent(httpUrl)`**. |
| External open | `lib/services/web_launcher_service.dart` | `launchUrl(..., mode: LaunchMode.externalApplication)` when `Platform.isLinux`. |

---

## 3) End-to-end sequence for a **local book** (`file://...` or POSIX path)

### 3.1 Preconditions

- `widget.book.contentUrl` must point at the **downloaded book** (usually a `.zip` or extracted path), same as other platforms.
- App must have read access to that path (Linux desktop typically OK; sandboxed/Flatpak may differ).

### 3.2 Steps (in order)

1. **Resolve filesystem path**  
   `_fileUrlToPath(fileUrl)` → native path string.

2. **Verify file exists**  
   If missing → user error.

3. **Load encryption metadata from DB** (if any)  
   `encBookId`, `encKeyB64`, `encNonceB64` from `DatabaseService.getBookByFilePath` or `widget.book`.

4. **If all three encryption fields are present — “encrypted book” path**

   **4a. Unzip-first (preferred)**  
   - `ZipHandler.getExtractDirPath(zipPath)` → temp dir under app temp, e.g. `.../extracted_books/<zip_basename>/`.  
   - On Linux (non-Android): `ZipHandler.extractZipToDir(zipPath, extractDirPath)` on the main isolate.  
   - `ZipHandler.findIndexHtml(extractDirPath)` must succeed.  
   - If success:  
     - `contentKey = BookDecryptionService.getContentKey(bookId, keyEncB64, keyNonceB64)`  
     - `bookDirectory` = extracted dir  
     - `_extractedDirPathForCleanup` set for dispose cleanup  

   **4b. Fallback — whole zip was encrypted / unzip failed**  
   - `decryptBookFileIfNeeded(...)` → decrypted zip path in cache (`_decryptedCachePath`)  
   - Then `ZipHandler.processBookFileOffMain(filePath)` to get `index.html` path and book root directory.

5. **If no encryption metadata — plain book**  
   - `ZipHandler.processBookFileOffMain` or directory/`index.html` resolution only.  
   - `contentKey` stays `null` (nothing decrypted on serve).

6. **Start local HTTP server**  
   - `_startLocalServer(bookDirectory, contentKey: contentKey)`  
   - Binds **`InternetAddress.loopbackIPv4`** on ports **8080–8089** (first free) on Linux/desktop in-process server path.  
   - For each request: map URL path → file under `bookDirectory`; optional decrypt for encrypted paths.

7. **Build book URL**  
   - `httpUrl = 'http://127.0.0.1:${_serverPort}/$urlPath'`  
   - `urlPath` = path of `index.html` **relative to** `bookDirectory`, forward slashes.

8. **Linux-only: open in system browser** (target)  
   - `WebLauncherService.openWebContent(httpUrl)`  
   - Requires **http** or **https** scheme (see section 5).  
   - Sets UI: `_openedExternally`, clears loading; on failure: *“Could not open browser…”*.

9. **Server lifecycle**  
   - Server stays up while `ReadingScreen` is mounted; closed in `dispose()` (with delay so teardown is safe).  
   - If user closes the reader screen, server stops — **external browser tabs may then break**.

---

## 4) Local server: what gets decrypted (resources-only model)

**File:** `lib/screens/reading_screen.dart` → `_startLocalServer`

- Loads optional `manifest.json` from book root: `loadEncryptedPathsFromManifest(bookDirectory.path)` (`lib/utils/book_manifest.dart`).
- **If manifest lists encrypted paths:** only those paths are decrypted when `contentKey != null`.
- **If no manifest:** default rule — paths whose relative path starts with **`resources/`** (case normalized) are treated as encrypted.
- For each request:
  - **Encrypted path + `contentKey`:** read file bytes → `BookDecryptionService.decryptFileBytesWithOptionalAad(...)` → respond with decrypted bytes and correct `Content-Type`.
  - **Not encrypted:** read file bytes and respond as-is.
- Size limits: `BookDecryptionService.maxDecryptBytesForPath(...)`; oversized → HTTP 413-style response.

**Important for the other project:** If your book uses a different folder name than `resources/` and no manifest, decryption will **never** run and the browser will show corrupt/binary content for those files.

---

## 5) `WebLauncherService` constraints (common failure point)

**File:** `lib/services/web_launcher_service.dart`

- `openWebContent(url)` **returns false** if:
  - URI parse fails, or
  - scheme is not **exactly** `http` or `https`.
- So **`file://` book URLs are never opened via this service** — local books **must** go through the **loopback HTTP** URL built in `_loadFile`.
- On non-Linux platforms this method returns `false` by design (no external launch).

**Dependencies:** `url_launcher` + Linux implementation (`url_launcher_linux`). Ensure Linux desktop embedding registers the plugin.

---

## 6) Linux-specific branches in `_startLoadingContent` (this repo)

- **No WebView** for the book on Linux (`_controller == null`).
- **`contentUrl` empty:** error message (no `about:blank` in WebView).
- **`assets/...`:** error *“This book can’t be opened in the browser.”*
- **`http://` / `https://`:** `_openRemoteUrlInLinuxBrowser` → `WebLauncherService`.

---

## 7) Checklist: “not working on Linux” in another project

Use this in order.

### A) Server never reached

- [ ] Confirm `_startLocalServer` runs without throwing (port in use, permission).
- [ ] Log `_serverPort` and full `httpUrl`.
- [ ] From a terminal while the app is on the reader screen: `curl -I http://127.0.0.1:<port>/` or open URL manually.

### B) Browser opens but blank / broken book

- [ ] External browser loads HTML but assets 404 → path mapping or `index.html` location wrong.
- [ ] Assets load but look like garbage → **decrypt rule mismatch** (not under `resources/` and no manifest).
- [ ] CORS usually **not** an issue for same-origin `127.0.0.1` requests from the same tab.

### C) `launchUrl` fails

- [ ] Default browser / `xdg-open` available on target distro.
- [ ] Snaps/sandbox: may block opening browser or localhost (test unsandboxed build).
- [ ] URL must be `http://127.0.0.1:...` not `file://` for this flow.

### D) App exits or reader disposed immediately

- [ ] Server closed while browser still open → tab dies. Keep server alive or document “keep app open”.

### E) Flatpak / Snap

- [ ] May restrict `HttpServer` on loopback or external `xdg-open` behavior — needs platform-specific testing.

### F) Whole-zip encryption only

- [ ] Unzip-first will fail; fallback `decryptBookFileIfNeeded` must work and produce a zip that `processBookFileOffMain` can extract.

---

## 8) Minimal replication recipe (pseudo-steps)

1. On book open: resolve path → unzip to temp dir (or decrypt then unzip).
2. Find `index.html` under book root.
3. `HttpServer.bind(InternetAddress.loopbackIPv4, port)`.
4. Serve files from book root; if encrypted resources, decrypt per request using same rules as `book_manifest.dart` / `resources/`.
5. `launchUrl(Uri.parse('http://127.0.0.1:$port/$relativeIndexPath'), mode: LaunchMode.externalApplication)`.
6. Keep server running until user leaves reader.

---

## 9) Related files (this repository)

- `lib/screens/reading_screen.dart` — Linux/desktop branches, `_loadFile`, `_startLocalServer`, `_startLoadingContent`
- `lib/services/web_launcher_service.dart` — `url_launcher` on Linux
- `lib/utils/book_manifest.dart` — encrypted path set + `isEncryptedPath`
- `lib/services/book_decryption_service.dart` — `getContentKey`, `decryptFileBytesWithOptionalAad`, size caps
- `lib/utils/zip_handler.dart` — `getExtractDirPath`, `extractZipToDir`, `processBookFileOffMain`, `findIndexHtml`
- `lib/utils/decrypt_util.dart` — full-zip decrypt fallback (`decryptBookFileIfNeeded`)

---

## 10) Optional: align README with actual stack

Older `README.md` snippets may mention WPE / `flutter_inappwebview_linux`. **A Linux handoff that uses external browser + local `HttpServer`** is different from an embedded Linux WebView for the book load path. Update docs in the other project to match whatever implementation you ship; for *this* repo, see §0 for the current mix (WebView + optional `WebLauncherService`).

---

*Generated for handoff from the tv_app_books codebase. Adjust paths and package names when copying to another repository.*
