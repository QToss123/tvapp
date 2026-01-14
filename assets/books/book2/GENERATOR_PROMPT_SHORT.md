# PDF to Book Package Generator - Quick Prompt

Build a web application that converts PDF files into a complete interactive book package.

## What It Does
- Accepts PDF file upload
- Analyzes PDF (counts pages, extracts metadata)
- Generates complete file structure matching the existing book reader system
- Creates `book_data.js` with proper page entries
- Packages everything into a downloadable ZIP file

## Input
- PDF file (drag-and-drop or file picker)
- Optional metadata: title, logo, theme color, cover image

## Output
Complete package structure:
```
output/
├── index.html (from template)
├── css/ (all styles from template)
├── js/ (main.js, interactions.js, PDF.js libraries)
├── data/
│   └── book_data.js (generated with page entries)
├── assets/
│   └── [pdf-file].pdf
└── audio/
    └── pageflip.mp3
```

## Generated book_data.js Format
```javascript
window.BOOK_DATA = {
  "books": [{
    "id": "[timestamp]",
    "title": "[user-input]",
    "logo": null,
    "canvasColor": "#4f46e5",
    "cover": null,
    "pdfPath": "",
    "totalPages": [count],
    "toc": [],
    "pages": [
      {
        "id": "[timestamp]_0",
        "fileUrl": "assets/[pdf-name].pdf",
        "fileType": "pdf",
        "pageIndex": 1
      },
      // ... one per page
    ],
    "hotspots": []
  }]
};
```

## Key Requirements
1. Use PDF.js to read PDF and count pages
2. Generate unique IDs (timestamp-based)
3. Copy template files (HTML, CSS, JS, libraries)
4. Create proper directory structure
5. Generate book_data.js with correct format
6. Package into ZIP for download
7. Handle errors gracefully

## Tech Stack Options
- **Pure Client-side**: JavaScript + PDF.js + JSZip (simpler, works offline)
- **Node.js**: Express + pdf-lib + archiver (more control)
- **Python**: Flask + PyPDF2 + zipfile (alternative)

## UI Flow
1. Upload PDF
2. (Optional) Enter metadata
3. Click "Generate"
4. Download ZIP file
5. Extract and open index.html

## Success Criteria
Generated package must:
- Open directly in browser (file:// protocol)
- Display all PDF pages correctly
- Have all features working (bookmarks, highlights, notes, etc.)
- Match existing reader structure exactly
