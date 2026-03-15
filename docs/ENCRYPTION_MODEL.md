# Book encryption model

**Current model:** Books are **zipped only**. Only the contents of the **`resources/`** folder inside the zip are encrypted. The rest of the book (e.g. `index.html`, structure, non-resource assets) is plain inside the zip.

## Book file format (e.g. `book_17c4ba3312ac44d4_encrypted.zip`)

- **File:** A normal ZIP file (e.g. `book_<id>_encrypted.zip`). The zip itself is **not** encrypted; it can be unzipped with any standard unzip.
- **After unzip:** The book directory is named like the zip without `.zip` (e.g. `book_17c4ba3312ac44d4_encrypted`). The app uses this as the server root when serving the book.
- **Inside the zip:**
  - **Plain:** `index.html`, JS, CSS, and any files not listed as encrypted are served as plain.
  - **Encrypted:** Which files are encrypted is defined by **`manifest.json`** in the book root. If `manifest.json` is present, it lists all encrypted paths (e.g. `encrypted`, `encryptedFiles`, or `files[].path` with `encrypted: true`). If `manifest.json` is missing, the app falls back to treating only paths under **`resources/`** as encrypted.
- **manifest.json** (optional): Contains the list of encrypted file paths. Supported shapes:
  - `{ "encrypted_files": ["resources/book/page_1.webp", "resources/Animations/Page_13.mp4", ...] }` (e.g. Liqvid book manifest)
  - `{ "encrypted": ["resources/1.webp", "resources/2.webp", ...] }`
  - `{ "encryptedFiles": ["path1", "path2", ...] }`
  - `{ "files": [ { "path": "resources/a.webp", "encrypted": true }, ... ] }`
- **Flow:** Unzip → start local server → load manifest (if present) → serve. For each request: if path is in the manifest (or under `resources/` when no manifest), decrypt then serve; otherwise serve file as-is. No full-book decryption.

---

## 1. Download (sync)

- **API:** `ApiService.downloadCourse()` downloads the file **as-is** from the server (no decryption on download).
- The file is typically a **.zip**. It may contain:
  - Plain entries (e.g. `index.html`, structure).
  - Encrypted entries **only** under **`resources/`** (e.g. chapter content, media).
- Encryption metadata is stored with the book: `encBookId`, `encKeyB64`, `encNonceB64` (and optionally `encBookPath`). These are used later to derive the content key and decrypt only `resources/` content when opening the book.

**Relevant code:** `lib/services/api_service.dart` (download stores file; returns `encBookId`, `encKeyB64`, `encNonceB64`).

---

## 2. Opening a book (reading screen)

When the user opens a book that has encryption metadata:

### Preferred path: unzip first, decrypt on serve

1. **Unzip** the book zip to a temp directory (no decryption of the zip itself).
2. **Content key** is derived once: `BookDecryptionService.getContentKey(bookId, keyEncB64, keyNonceB64)`.
3. A **local HTTP server** serves the book. For each request:
   - Path **under `resources/`** → read file bytes, **decrypt** with the content key, then serve.
   - Any other path → serve **plain** (no decryption).

When **manifest.json** exists, only paths listed there are decrypted; otherwise only paths under `resources/` are decrypted. Everything else is served as plain.

**Relevant code:**
- `lib/screens/reading_screen.dart`: `_startLoadingContent()` unzips, gets content key, starts server; request handler uses `isEncryptedPath(pathForDecrypt, serverEncryptedPaths)` from `book_manifest.dart` (manifest or `resources/` fallback).

### Fallback path: whole zip was encrypted (legacy)

If the zip cannot be read as a normal zip (e.g. old format where the **entire** zip was encrypted):

1. **Decrypt the whole file** to a `_decrypted.zip` (e.g. in app cache) via `decryptBookFileIfNeeded()`.
2. Then **unzip** that decrypted zip and serve. In that case all content is already decrypted; no per-file decrypt in the server.

**Relevant code:**
- `lib/screens/reading_screen.dart`: when `unzipFirstSucceeded` is false, calls `decryptBookFileIfNeeded()` then `ZipHandler.processBookFileOffMain(filePath)`.
- `lib/utils/decrypt_util.dart`: `decryptBookFileIfNeeded()` uses `BookDecryptionService.decryptFileOnDisk()` to produce the decrypted zip.

---

## 3. Where “only resources/ is encrypted” is enforced

| Place | What it does |
|-------|----------------|
| `utils/book_manifest.dart` | `loadEncryptedPathsFromManifest(bookDirPath)` reads `manifest.json`; `isEncryptedPath(path, set)` uses that set or falls back to `resources/`. |
| `book_server_isolate.dart` | Loads manifest at startup; request handler uses `isEncryptedPath(pathForDecrypt, encryptedPaths)`. |
| `reading_screen.dart` | In-process server loads manifest; request handler uses `isEncryptedPath(pathForDecrypt, serverEncryptedPaths)`. |
| `reading_screen.dart` | `_verifyDecryptionBeforeLoad()` → looks under `bookDirectory/resources/` for a file to verify decryption. |
| `book_decryption_service.dart` | `decryptFileBytes` / `decryptFileBytesWithOptionalAad` used for per-file decrypt. |

---

## 4. Summary

- **Initially** (old model): The whole book/screen could be encrypted (entire zip encrypted).
- **Now**: Books are **only zipped**. Encrypted paths come from **manifest.json** when present, else only **`resources/`**. The app:
  - Unzips the zip as-is.
  - Serves content over a local HTTP server.
  - Loads `manifest.json` (if present) for the list of encrypted paths.
  - Decrypts on the fly only for those paths; all other paths are served as plain.

The fallback “decrypt whole zip then unzip” remains for legacy books where the entire zip was encrypted.
