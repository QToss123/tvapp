# Bookshelf App - Workflow Documentation

## Complete Workflow with Dummy Data

### 1. App Launch Flow

```
Splash Screen (2 seconds)
    ↓
Check License Status
    ├─ License Valid? → Home Screen (Show Books)
    └─ License Invalid/Expired → Home Screen (Show Empty State)
```

### 2. License Activation Flow

```
Home Screen (Empty State)
    ↓
Click "Go to Settings" Button
    ↓
Settings Screen
    ├─ Enter License Number (max 16 chars)
    ├─ Enter Expiry Date (YYYY-MM-DD format)
    ├─ Click "Activate" Button
    └─ License Activated (Fields Disabled, Green Tick Shown)
    ↓
Return to Home Screen
    ↓
Home Screen (Shows Books Grid)
```

### 3. Testing with Dummy Data

#### Quick Setup:
1. Open **Settings Screen**
2. Scroll to **"Testing Tools"** section
3. Click **"Load Dummy Data"** button
4. This will automatically:
   - Set license number: `LIQVID1234567890` (16 chars)
   - Set expiry date: 1 year from today
   - Activate the license
   - Set sync type: `online`
   - Set storage location: `internal`

#### Clear All Data:
1. In **Settings Screen**
2. Click **"Clear All Data"** button
3. This removes all saved preferences

### 4. Dummy Books Data

The app includes **30 dummy books** for testing:
- Books are displayed in a grid (10 per row)
- Each book has:
  - Title
  - Author
  - Progress (0-100%)
  - Thumbnail image
  - Content URL (for reading)

**Sample Books:**
- Book 1 & Book 2 (with actual content from `assets/books/book1` and `assets/books/book2`)
- The Pragmatic Programmer
- Clean Code
- Design Patterns
- The Lean Startup
- Sapiens
- Thinking Fast and Slow
- The 7 Habits
- Good to Great
- And 20 more...

### 5. License Validation Rules

**License is considered valid if:**
1. License number exists and is not empty
2. License is activated (`licenseActivated = true`)
3. Expiry date exists and is in valid format (YYYY-MM-DD)
4. Current date is before expiry date

**License is invalid if:**
- License number is empty
- License is not activated
- Expiry date is missing
- Expiry date is in the past
- Expiry date format is invalid

### 6. Settings Screen Features

**License Section:**
- License Number input (max 16 characters)
- Expiry Date input (YYYY-MM-DD format)
- Activate button (only visible when not activated)
- Green check icon (shown when activated)
- Fields disabled after activation

**Sync Type:**
- Options: `online`, `from external`
- Default: `online`

**Storage Location:**
- Options: `internal`, `external`, `cloud`
- Default: `internal`

**Action Buttons:**
- **Save**: Saves sync type and storage location
- **Reset**: Clears all settings to default

**Testing Tools:**
- **Load Dummy Data**: Initializes test license data
- **Clear All Data**: Removes all saved preferences

### 7. Home Screen States

**Loading State:**
- Shows circular progress indicator
- Checks license status

**Empty State (No License/Expired):**
- Lock icon
- Message: "Please activate the licence first to download books"
- "Go to Settings" button
- Settings icon in app bar

**Books Grid State (License Valid):**
- Search bar
- Grid of book cards (10 per row)
- Each card shows:
  - Thumbnail image
  - Title (overlaid on thumbnail)
  - Author (below thumbnail)
- Clicking a card opens reading screen

### 8. Reading Screen

- Loads book content in WebView
- Supports:
  - Local assets (`assets/books/book1/index.html`)
  - External files (`file:///path/to/book/index.html`)
  - Network URLs (`http://` or `https://`)
- Handles relative resources (CSS, JS, images, audio)
- Refresh button to reload content

### 9. Data Persistence

All settings are saved using `SharedPreferences`:
- `licenseNumber`: String
- `licenseActivated`: Boolean
- `licenseExpiryDate`: String (YYYY-MM-DD)
- `syncType`: String
- `storageLocation`: String

### 10. Testing Checklist

✅ **Test License Activation:**
1. Launch app → See empty state
2. Go to Settings
3. Enter license: `LIQVID1234567890`
4. Enter expiry: `2025-12-31` (or any future date)
5. Click "Activate"
6. Return to Home → See books grid

✅ **Test License Expiry:**
1. Activate license with past date: `2020-01-01`
2. Try to activate → Should show error
3. Activate with future date
4. Manually set expiry to past date in SharedPreferences
5. Relaunch app → Should show expired message

✅ **Test Dummy Data:**
1. Go to Settings
2. Click "Load Dummy Data"
3. Verify license is auto-filled and activated
4. Return to Home → See books grid
5. Go back to Settings → Click "Clear All Data"
6. Return to Home → See empty state

✅ **Test Book Reading:**
1. With valid license, click any book card
2. Reading screen should load
3. For Book 1 and Book 2, should load from assets
4. Other books show placeholder

✅ **Test Search:**
1. With books visible, type in search bar
2. Books should filter by title or author
3. Clear search → All books visible again

### 11. Dummy Data Constants

**License:**
- Number: `LIQVID1234567890` (16 characters)
- Expiry: 1 year from current date (auto-calculated)

**Books:**
- 30 books total
- Mix of programming, business, fiction, and self-help books
- Progress values range from 12% to 95%

---

## Quick Start for Testing

1. **Launch the app** → You'll see empty state (no license)
2. **Go to Settings** → Click "Load Dummy Data"
3. **Return to Home** → You'll see 30 books in a grid
4. **Click any book** → Opens reading screen
5. **Search books** → Type in search bar to filter
6. **Test expiry** → Use "Clear All Data" then manually set past expiry date

---

**Note:** The dummy data helper (`lib/utils/dummy_data.dart`) provides easy methods to initialize and clear test data for development and testing purposes.
