# PDF to Interactive Book Package Generator - Project Prompt

## Project Overview
Create a web-based application that accepts a PDF file upload and automatically generates a complete, self-contained interactive book package ready for deployment. The output should match the structure and functionality of an existing interactive eBook reader system.

## Core Functionality

### Input Requirements
- Accept PDF file upload (drag-and-drop or file picker)
- Optional: Book metadata input form:
  - Book title
  - Logo image (optional)
  - Canvas/theme color (hex code)
  - Cover image (optional)

### Processing Steps
1. **PDF Analysis**
   - Read the uploaded PDF file
   - Extract total number of pages
   - Validate PDF integrity
   - Optionally extract PDF metadata (title, author, etc.)

2. **File Structure Generation**
   Create the following directory structure:
   ```
   output/
   ├── index.html
   ├── css/
   │   ├── style.css
   │   ├── components.css
   │   └── custom-theme.css
   ├── js/
   │   ├── main.js
   │   ├── interactions.js
   │   └── libs/
   │       ├── pdf.min.js
   │       ├── pdf.worker.min.js
   │       └── page-flip.browser.js (if used)
   ├── data/
   │   └── book_data.js
   ├── assets/
   │   └── [uploaded_pdf].pdf
   └── audio/
       └── pageflip.mp3
   ```

3. **Data File Generation**
   Generate `data/book_data.js` with the following structure:
   ```javascript
   window.BOOK_DATA = {
     "books": [
       {
         "id": "[timestamp-based-id]",
         "title": "[user-input-or-pdf-title]",
         "logo": "[logo-path-or-null]",
         "canvasColor": "[user-selected-color]",
         "cover": "[cover-path-or-null]",
         "pdfPath": "",
         "totalPages": [actual-page-count],
         "toc": [],
         "pages": [
           {
             "id": "[timestamp]_0",
             "fileUrl": "assets/[pdf-filename].pdf",
             "fileType": "pdf",
             "pageIndex": 1
           },
           // ... one entry per page
         ],
         "hotspots": []
       }
     ]
   };
   ```

4. **File Copying**
   - Copy the uploaded PDF to `assets/` directory
   - Copy all required library files (PDF.js, etc.)
   - Copy template files (HTML, CSS, JS) from a template directory
   - Include default audio file (pageflip.mp3)
   - Optionally copy logo and cover images if provided

5. **Package Generation**
   - Create a ZIP file containing the complete package
   - Provide download link
   - Optionally provide a preview option

## Technical Requirements

### Technology Stack (Recommended)
- **Frontend**: HTML, CSS, JavaScript (Vanilla or framework like React/Vue)
- **PDF Processing**: 
  - Client-side: PDF.js library
  - Server-side (if needed): pdf-lib, pdf-parse, or similar Node.js libraries
- **File Handling**: 
  - Client-side: FileReader API, JSZip for ZIP creation
  - Server-side: Multer (Node.js), file system operations
- **Backend** (if server-side processing needed):
  - Node.js + Express
  - OR Python + Flask/FastAPI
  - OR Pure client-side (browser-only)

### Key Features to Implement

1. **Upload Interface**
   - Drag-and-drop area for PDF files
   - File input fallback
   - Progress indicator during upload/processing
   - File size validation
   - Error handling for invalid PDFs

2. **Metadata Form**
   - Book title input (defaults to PDF filename or metadata)
   - Logo upload (optional, with preview)
   - Color picker for theme color
   - Cover image upload (optional)
   - Form validation

3. **PDF Processing**
   - Read PDF using PDF.js or server-side library
   - Count total pages
   - Extract PDF metadata (if available)
   - Validate PDF structure
   - Handle errors gracefully

4. **Template System**
   - Maintain template files for:
     - index.html
     - All CSS files
     - main.js
     - interactions.js
     - Required library files
   - Templates should be minimal/standard versions
   - No hardcoded book-specific data

5. **Generation Engine**
   - Generate unique IDs (timestamp-based)
   - Create book_data.js with correct structure
   - Copy all template files
   - Organize files in proper directory structure
   - Handle file naming (sanitize PDF filename)

6. **Output & Download**
   - Create ZIP archive of the package
   - Generate downloadable file
   - Provide clear instructions for usage
   - Optional: Preview mode to test the generated package

## User Interface Requirements

### Upload Page
- Clean, modern design
- Large drag-and-drop area
- Clear instructions
- Progress bar during processing
- Success/error messages

### Configuration Panel (Optional)
- Collapsible/expandable metadata form
- Preview of book cover/logo
- Theme color preview
- "Generate Package" button

### Results Page
- Download button for ZIP file
- Package information summary
- Next steps/instructions
- Option to generate another book

## Additional Features (Optional but Recommended)

1. **Batch Processing**: Upload multiple PDFs at once
2. **Preview Mode**: Test the generated package in browser before download
3. **TOC Extraction**: Attempt to extract table of contents from PDF bookmarks/outline
4. **Template Selection**: Choose from different reader templates/themes
5. **Custom Branding**: Advanced options for customizing colors, fonts, etc.
6. **Export Options**: 
   - ZIP download
   - Direct deployment instructions
   - Docker container option
7. **History**: Save generated packages (if server-side)
8. **Validation**: Check package integrity before download

## Error Handling

- Invalid PDF format
- Corrupted PDF files
- Large file sizes (provide warnings)
- Missing template files
- Browser compatibility issues
- Network errors (if server-side)

## Success Criteria

The generator should produce a package that:
1. ✅ Can be opened directly in a browser (file:// protocol)
2. ✅ Displays all PDF pages correctly
3. ✅ Has all interactive features working (bookmarks, notes, highlights, etc.)
4. ✅ Contains all necessary files in correct locations
5. ✅ book_data.js has correct structure and page count
6. ✅ PDF file is properly referenced and accessible
7. ✅ No broken links or missing resources

## Delivery Format

- Web application (can be deployed or run locally)
- Self-contained (all dependencies included)
- Clear documentation for users
- README with setup/usage instructions

## Example Workflow

1. User visits the generator application
2. User uploads a PDF file (e.g., "my-book.pdf")
3. System analyzes PDF: "14 pages detected"
4. User fills metadata form:
   - Title: "My Interactive Book"
   - Theme Color: #4f46e5
   - (Optional fields left blank)
5. User clicks "Generate Package"
6. System processes:
   - Creates directory structure
   - Generates book_data.js with 14 page entries
   - Copies template files
   - Copies PDF to assets/
   - Creates ZIP file
7. User downloads "My_Interactive_Book.zip"
8. User extracts ZIP and opens index.html in browser
9. Book displays correctly with all 14 pages accessible

## Technical Considerations

- **Client-side vs Server-side**: 
  - Pure client-side is simpler but may have limitations with large PDFs
  - Server-side provides more control and can handle larger files
  - Hybrid approach: client-side for small files, server-side for large ones

- **Browser Compatibility**: 
  - Support modern browsers (Chrome, Firefox, Safari, Edge)
  - Handle file:// protocol limitations
  - Consider CORS issues if processing on server

- **Performance**:
  - Handle large PDFs efficiently
  - Show progress during processing
  - Optimize ZIP creation

- **Security**:
  - Validate file types
  - Sanitize file names
  - Prevent malicious file uploads
  - If server-side: implement proper authentication if needed

## Reference Structure

Study the existing book package structure:
- File organization
- book_data.js format
- Required dependencies
- Template file structure
- Asset organization

Generate output that is 100% compatible with the existing reader system.
