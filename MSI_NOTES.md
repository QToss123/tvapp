# MSI / Windows installer notes

## Faster book opening

Book opening can feel slow when using the MSI-installed app. Here are the main causes and what to do:

### 1. First open of each book is slower
- The first time you open a book, it must **decrypt** (if encrypted) and **extract** the ZIP to temp. This is unavoidable.
- **Second and later opens** of the same book reuse the extracted cache, so they are much faster.

### 2. Windows Defender / antivirus can slow file access
When the app runs from Program Files, antivirus may scan every file read/write (decrypt, extract, serve). That can add noticeable delay.

**Tip:** Add Windows Defender exclusions for faster opening:
1. Open **Windows Security** → **Virus & threat protection** → **Manage settings** (under Virus & threat protection settings) → **Exclusions** → **Add or remove exclusions** → **Add an exclusion** → **Folder**.
2. Add these folders (adjust paths for your setup):
   - `C:\Program Files\BurlingtonEnglish` (app install folder)
   - `C:\Users\<YourUser>\AppData\Local\Temp\extracted_books` (book extract cache)
   - `C:\Users\<YourUser>\AppData\Local\Temp\decrypted_books` (decrypted cache)

Or add your **book storage folder** if books are in a custom location.

### 3. Books on slow drives
- If books are on an external USB drive or network share, reading and decrypting them will be slower.
- Storing books on a fast local drive (e.g. SSD) improves first-open time.

### 4. What the app does to help
- Keeps extracted books in cache so **reopening the same book is fast**.
- Runs decrypt/extract off the main thread so the UI stays responsive.
- Uses parallel work (file check, DB lookup, settings) where possible.
