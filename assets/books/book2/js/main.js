document.addEventListener('DOMContentLoaded', () => {
    const app = {
        state: {
            viewMode: 'single', // 'single' | 'double'
            currentBook: null,
            currentPageIndex: 0,
            scale: 1.0,
            thumbnailsRendered: false,
            // Features
            timerInterval: null,
            timerSeconds: 0,
            timerRunning: false,
            isHighlighting: false,
            highlightColor: '#FFFF00', // Default Yellow
            isDrawing: false,
            // Data
            bookmarks: [],
            notes: {}, // pageIndex -> note content
            highlights: {}, // pageIndex -> [ { color: '#...', points: [{x,y}, ...] } ]
            highlightHistory: [] // [ { pageIndex, strokeIndex } ]
        },

        elements: {
            readerView: document.getElementById('reader-view'),
            readerContent: document.getElementById('reader-content'),
            modalOverlay: document.getElementById('modal-overlay'),
            modalBody: document.getElementById('modal-body'),
            modalClose: document.getElementById('modal-close'),
            pageNum: document.getElementById('page-num'),

            // Header
            bookTitle: document.getElementById('book-title'),
            pageInput: document.getElementById('page-jump-input'),
            pageTotal: document.getElementById('page-total-disp'),
            btnFullscreen: document.getElementById('btn-fullscreen'),
            btnBookmark: document.getElementById('btn-bookmark'),
            btnNotes: document.getElementById('btn-notes'),

            // Tools
            btnTimerToggle: document.getElementById('btn-timer-toggle'),
            timerWidget: document.getElementById('timer-widget'),
            timerBtn: document.getElementById('timer-btn'),
            timerResetBtn: document.getElementById('timer-reset-btn'),
            timerDisplay: document.getElementById('timer-display'),
            btnHighlighter: document.getElementById('btn-highlighter'),
            highlighterColors: document.getElementById('highlighter-colors'),

            // Footer
            btnSingle: document.getElementById('btn-single'),
            btnDouble: document.getElementById('btn-double'),
            btnPrev: document.getElementById('btn-prev'),
            btnNext: document.getElementById('btn-next'),
            btnThumbs: document.getElementById('btn-thumbs'),
            btnZoomIn: document.getElementById('btn-zoom-in'),
            btnZoomOut: document.getElementById('btn-zoom-out'),

            // Overlays
            thumbnailsOverlay: document.getElementById('thumbnails-overlay'),
            pageFlipAudio: document.getElementById('page-flip-audio'),

            // Sidebar
            btnHome: document.getElementById('btn-home'),
            navSidebar: document.getElementById('nav-sidebar'),
            btnCloseSidebar: document.getElementById('btn-close-sidebar'),
            tocList: document.getElementById('toc-list'),
            animList: document.getElementById('anim-list'),
            interactList: document.getElementById('interact-list')
        },

        init() {
            try {
                this.loadUserData();
                this.attachEventListeners();

                // Check for PDF.js
                if (typeof pdfjsLib === 'undefined') {
                    throw new Error("PDF.js library not loaded. Check internet connection or file integrity.");
                }
                // Add worker source
                pdfjsLib.GlobalWorkerOptions.workerSrc = 'js/libs/pdf.worker.min.js';

                // PDF Cache for file:// protocol
                window.PDF_DATA_CACHE = window.PDF_DATA_CACHE || {};


                // Load Data
                if (window.BOOK_DATA && window.BOOK_DATA.books && window.BOOK_DATA.books.length > 0) {
                    const book = window.BOOK_DATA.books[0];
                    if (this.elements.bookTitle) this.elements.bookTitle.textContent = book.title || "My eBook";
                    // Load Logo
                    const logoImg = document.getElementById('project-logo');
                    if (book.logo && logoImg) {
                        logoImg.src = book.logo;
                        logoImg.classList.remove('hidden');
                    }

                    // Also set logo for Loader
                    const loaderLogoImg = document.getElementById('loader-project-logo');
                    if (book.logo && loaderLogoImg) {
                        loaderLogoImg.src = book.logo;
                        loaderLogoImg.style.display = 'block';
                    }

                    this.loadBook(book).catch(e => this.showError("Failed to load book: " + e.message));
                } else {
                    this.showError("No book data found.");
                }
            } catch (e) {
                this.showError("Init Error: " + e.message);
            }
        },

        loadUserData() {
            try {
                const savedBookmarks = localStorage.getItem('offlinePlayer_bookmarks');
                if (savedBookmarks) this.state.bookmarks = JSON.parse(savedBookmarks);

                const savedNotes = localStorage.getItem('offlinePlayer_notes');
                if (savedNotes) this.state.notes = JSON.parse(savedNotes);

                const savedHighlights = localStorage.getItem('offlinePlayer_highlights');
                if (savedHighlights) this.state.highlights = JSON.parse(savedHighlights);

                const savedHistory = localStorage.getItem('offlinePlayer_highlightHistory');
                if (savedHistory) this.state.highlightHistory = JSON.parse(savedHistory);
            } catch (e) {
                console.warn("Failed to load user data", e);
            }
        },

        saveUserData() {
            try {
                localStorage.setItem('offlinePlayer_bookmarks', JSON.stringify(this.state.bookmarks));
                localStorage.setItem('offlinePlayer_notes', JSON.stringify(this.state.notes));
                localStorage.setItem('offlinePlayer_highlights', JSON.stringify(this.state.highlights));
                localStorage.setItem('offlinePlayer_highlightHistory', JSON.stringify(this.state.highlightHistory));
            } catch (e) {
                console.warn("Failed to save user data", e);
            }
        },

        attachEventListeners() {
            // Navigation
            if (this.elements.btnPrev) this.elements.btnPrev.addEventListener('click', () => this.changePage(-1));
            if (this.elements.btnNext) this.elements.btnNext.addEventListener('click', () => this.changePage(1));
            if (this.elements.pageInput) this.elements.pageInput.addEventListener('change', (e) => this.jumpToPage(e.target.value));

            // View Modes
            if (this.elements.btnSingle) this.elements.btnSingle.addEventListener('click', () => this.setViewMode('single'));
            if (this.elements.btnDouble) this.elements.btnDouble.addEventListener('click', () => this.setViewMode('double'));

            // Zoom
            if (this.elements.btnZoomIn) this.elements.btnZoomIn.addEventListener('click', () => this.zoom(0.2));
            if (this.elements.btnZoomOut) this.elements.btnZoomOut.addEventListener('click', () => this.zoom(-0.2));

            // Extras
            if (this.elements.btnFullscreen) this.elements.btnFullscreen.addEventListener('click', () => this.toggleFullscreen());
            if (this.elements.btnThumbs) this.elements.btnThumbs.addEventListener('click', () => this.toggleThumbnails());

            // Header Features
            if (this.elements.btnBookmark) this.elements.btnBookmark.addEventListener('click', () => this.toggleBookmark());
            if (this.elements.btnNotes) this.elements.btnNotes.addEventListener('click', () => this.toggleNotes());

            // Timer & Highlighter
            if (this.elements.btnTimerToggle) this.elements.btnTimerToggle.addEventListener('click', () => this.toggleTimerWidget());
            if (this.elements.timerBtn) this.elements.timerBtn.addEventListener('click', () => this.toggleTimerState());
            if (this.elements.timerResetBtn) this.elements.timerResetBtn.addEventListener('click', () => this.resetTimer());
            if (this.elements.btnHighlighter) this.elements.btnHighlighter.addEventListener('click', () => this.toggleHighlighter());

            // Sidebar
            if (this.elements.btnHome) this.elements.btnHome.addEventListener('click', () => this.toggleSidebar());
            if (this.elements.btnCloseSidebar) this.elements.btnCloseSidebar.addEventListener('click', () => this.toggleSidebar(false));

            // Sidebar Accordion logic
            const headers = document.querySelectorAll('.section-header');
            headers.forEach(header => {
                header.addEventListener('click', () => {
                    const section = header.parentElement;
                    section.classList.toggle('active');
                });
            });

            // Color Picker
            const swatches = document.querySelectorAll('.color-swatch');
            swatches.forEach(s => {
                s.addEventListener('click', (e) => {
                    // Update active state
                    swatches.forEach(sw => sw.classList.remove('active'));
                    e.target.classList.add('active');
                    this.state.highlightColor = e.target.dataset.color;
                });
            });

            // Undo / Clear
            const btnUndo = document.getElementById('btn-highlight-undo');
            if (btnUndo) btnUndo.addEventListener('click', () => this.undoHighlight());

            const btnClear = document.getElementById('btn-highlight-clear');
            if (btnClear) btnClear.addEventListener('click', () => this.clearPageHighlights());

            // Modal
            if (this.elements.modalClose) {
                this.elements.modalClose.addEventListener('click', () => {
                    this.elements.modalOverlay.classList.add('hidden');
                    this.elements.modalOverlay.classList.remove('zoom-mode'); // Clean up zoom mode
                    this.elements.modalBody.innerHTML = '';
                    // Stop media
                    const videos = this.elements.modalBody.querySelectorAll('video');
                    videos.forEach(v => v.pause());
                    const audios = this.elements.modalBody.querySelectorAll('audio');
                    audios.forEach(a => a.pause());
                });
            }

            // Resize
            window.addEventListener('resize', () => {
                if (this.resizeTimeout) clearTimeout(this.resizeTimeout);
                this.resizeTimeout = setTimeout(() => this.renderCurrentView(), 200);
            });

            // Keyboard Shortcuts
            document.addEventListener('keydown', (e) => {
                // Undo: Ctrl+Z or Cmd+Z
                if ((e.ctrlKey || e.metaKey) && e.key === 'z') {
                    if (this.state.isHighlighting) {
                        e.preventDefault();
                        this.undoHighlight();
                    }
                }

                // Clear: Delete or Backspace (only if highlighting)
                if ((e.key === 'Delete' || e.key === 'Backspace') && this.state.isHighlighting) {
                    // Check if not in an input/textarea
                    if (['INPUT', 'TEXTAREA'].indexOf(document.activeElement.tagName) === -1) {
                        e.preventDefault();
                        this.clearPageHighlights();
                    }
                }

                // Deactivate: Escape
                if (e.key === 'Escape' && this.state.isHighlighting) {
                    this.toggleHighlighter();
                }
            });

            // Mouse Wheel Zoom: Ctrl + Scroll
            window.addEventListener('wheel', (e) => {
                if (e.ctrlKey || e.metaKey) {
                    e.preventDefault();
                    if (e.deltaY < 0) this.zoom(0.1);
                    else this.zoom(-0.1);
                }
            }, { passive: false });

            // Global Helper for MCQ
            window.checkAnswer = (selected, correct, btn) => {
                const feedback = document.getElementById('feedback');
                if (selected === correct) {
                    feedback.innerHTML = '<p style="color: green">Correct!</p>';
                    btn.style.background = 'lightgreen';
                } else {
                    feedback.innerHTML = '<p style="color: red">Try Again</p>';
                    btn.style.background = '#ffcccb';
                }
            };
        },

        /* --- BOOKMARKS & NOTES --- */
        toggleBookmark() {
            const pageIndex = this.state.currentPageIndex;
            const idx = this.state.bookmarks.indexOf(pageIndex);

            if (idx === -1) {
                this.state.bookmarks.push(pageIndex);
                this.elements.btnBookmark.style.color = '#F59E0B'; // Gold
            } else {
                this.state.bookmarks.splice(idx, 1);
                this.elements.btnBookmark.style.color = 'white';
            }
            this.saveUserData();
        },

        showBookmarksList() {
            this.elements.modalOverlay.classList.remove('hidden');
            const list = this.state.bookmarks.sort((a, b) => a - b).map(idx => {
                return `<div style="padding:10px; border-bottom:1px solid #eee; cursor:pointer;" onclick="app.closeModalAndJump(${idx})">
                    Page ${idx + 1}
                </div>`;
            }).join('');

            this.elements.modalBody.innerHTML = `
                <div style="width:100%; height:100%; padding:20px;">
                    <h2>My Bookmarks</h2>
                    <div style="max-height:80%; overflow-y:auto;">
                        ${this.state.bookmarks.length ? list : '<p>No bookmarks yet.</p>'}
                    </div>
                </div>
            `;
        },

        closeModalAndJump(idx) {
            this.elements.modalOverlay.classList.add('hidden');
            this.state.currentPageIndex = idx;
            this.renderCurrentView();
        },

        checkBookmarkStatus() {
            if (this.state.bookmarks.includes(this.state.currentPageIndex)) {
                this.elements.btnBookmark.style.color = '#F59E0B';
            } else {
                this.elements.btnBookmark.style.color = 'white';
            }
        },

        showAllNotes() {
            this.elements.modalOverlay.classList.remove('hidden');
            const notesKeys = Object.keys(this.state.notes).map(k => parseInt(k)).sort((a, b) => a - b);

            const list = notesKeys.map(idx => {
                const txt = this.state.notes[idx];
                if (!txt || !txt.trim()) return '';
                return `<div style="padding:10px; border-bottom:1px solid #eee; cursor:pointer;" onclick="app.closeModalAndJump(${idx})">
                    <strong>Page ${idx + 1}</strong>
                    <p style="margin:5px 0 0 0; color:#666; font-size:0.9em; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${txt}</p>
                </div>`;
            }).join('');

            this.elements.modalBody.innerHTML = `
                <div style="width:100%; height:100%; padding:20px;">
                    <h2>My Notes</h2>
                    <div style="max-height:80%; overflow-y:auto;">
                        ${notesKeys.length ? list : '<p>No notes yet.</p>'}
                    </div>
                </div>
            `;
        },

        toggleNotes() {
            const pageIndex = this.state.currentPageIndex;
            const currentNote = this.state.notes[pageIndex] || "";

            this.elements.modalOverlay.classList.remove('hidden');
            this.elements.modalBody.innerHTML = `
                <div style="width:100%; height:100%; display:flex; flex-direction:column;">
                    <div style="display:flex; justify-content:space-between; align-items:center;">
                         <h2 style="margin-top:0;">Notes for Page ${pageIndex + 1}</h2>
                         <div>
                            <button onclick="app.showBookmarksList()" style="background:#eee; border:none; padding:5px 10px; cursor:pointer; border-radius:4px; margin-right:5px;">Bookmarks</button>
                            <button onclick="app.showAllNotes()" style="background:#eee; border:none; padding:5px 10px; cursor:pointer; border-radius:4px;">All Notes</button>
                         </div>
                    </div>
                    <textarea id="page-notes" style="flex:1; padding:10px; border-radius:8px; border:1px solid #ccc; font-family:sans-serif; resize:none;">${currentNote}</textarea>
                    <button id="save-note-btn" style="margin-top:10px; padding:10px; background:#4F46E5; color:white; border:none; border-radius:8px; cursor:pointer;">Save Note</button>
                    <span id="save-msg" style="margin-top:5px; color:green; display:none;">Saved!</span>
                </div>
            `;

            document.getElementById('save-note-btn').onclick = () => {
                const val = document.getElementById('page-notes').value;
                this.state.notes[pageIndex] = val;
                this.saveUserData();
                const msg = document.getElementById('save-msg');
                msg.style.display = 'inline-block';
                setTimeout(() => msg.style.display = 'none', 1500);
            };
        },

        /* --- ZOOM MODAL --- */
        async openPageZoom(pageIndex) {
            const pageData = this.state.currentBook.pages[pageIndex];
            if (!pageData) return;

            const overlay = this.elements.modalOverlay;
            const body = this.elements.modalBody;

            overlay.classList.add('zoom-mode');
            overlay.classList.remove('hidden');
            body.innerHTML = '<div style="color:white">Loading...</div>';

            try {
                if (pageData.fileType === 'pdf') {
                    const canvas = document.createElement('canvas');
                    canvas.className = 'zoom-content';
                    const loadingTask = await this.getPDFLoadingTask(pageData.fileUrl);
                    const pdfDoc = await loadingTask.promise;
                    // Safe page fetching: if doc has 1 page (like exported assets), get page 1. 
                    // If multi-page doc, get pageIndex + 1.
                    const pageNum = Math.min(pdfDoc.numPages, (pageData.pageIndex || 0) + 1);
                    const page = await pdfDoc.getPage(pageNum);

                    // High quality render
                    const viewport = page.getViewport({ scale: 3.0 });
                    canvas.width = viewport.width;
                    canvas.height = viewport.height;
                    const ctx = canvas.getContext('2d');
                    await page.render({ canvasContext: ctx, viewport: viewport }).promise;

                    body.innerHTML = '';
                    body.appendChild(canvas);
                } else {
                    const img = document.createElement('img');
                    img.src = pageData.fileUrl;
                    img.className = 'zoom-content';
                    body.innerHTML = '';
                    body.appendChild(img);
                }
            } catch (e) {
                console.error("Zoom Error", e);
                body.innerHTML = '<p style="color:white">Error loading page.</p>';
            }
        },

        /* --- TIMER --- */
        toggleTimerWidget() {
            if (this.elements.timerWidget) this.elements.timerWidget.classList.toggle('hidden');
        },

        toggleTimerState() {
            const btn = this.elements.timerBtn;
            if (this.state.timerRunning) {
                // Stop
                clearInterval(this.state.timerInterval);
                this.state.timerRunning = false;
                btn.textContent = "Start";
                btn.classList.remove('running');
            } else {
                // Start
                this.state.timerRunning = true;
                btn.textContent = "Stop";
                btn.classList.add('running');
                this.state.timerInterval = setInterval(() => {
                    this.state.timerSeconds++;
                    this.updateTimerDisplay();
                }, 1000);
            }
        },

        resetTimer() {
            if (this.state.timerRunning) {
                clearInterval(this.state.timerInterval);
                this.state.timerRunning = false;
                if (this.elements.timerBtn) {
                    this.elements.timerBtn.textContent = "Start";
                    this.elements.timerBtn.classList.remove('running');
                }
            }
            this.state.timerSeconds = 0;
            this.updateTimerDisplay();
        },

        updateTimerDisplay() {
            if (this.elements.timerDisplay) {
                const mins = Math.floor(this.state.timerSeconds / 60).toString().padStart(2, '0');
                const secs = (this.state.timerSeconds % 60).toString().padStart(2, '0');
                this.elements.timerDisplay.textContent = `${mins}:${secs}`;
            }
        },

        /* --- HIGHLIGHTER --- */
        toggleHighlighter() {
            this.state.isHighlighting = !this.state.isHighlighting;
            if (this.elements.btnHighlighter) this.elements.btnHighlighter.classList.toggle('tool-active', this.state.isHighlighting);
            document.body.classList.toggle('highlighter-active', this.state.isHighlighting);

            // Toggle Colors Widget
            if (this.elements.highlighterColors) {
                if (this.state.isHighlighting) {
                    this.elements.highlighterColors.classList.remove('hidden');
                } else {
                    this.elements.highlighterColors.classList.add('hidden');
                }
            }
        },

        async loadBook(book) {
            this.state.currentBook = book;
            this.state.currentPageIndex = 0;
            if (this.elements.pageTotal) this.elements.pageTotal.textContent = `/ ${book.pages.length}`;
            if (this.elements.pageInput) this.elements.pageInput.max = book.pages.length;

            // Hide loader
            const loader = document.getElementById('loading-overlay');
            if (loader) {
                loader.classList.add('loader-fade-out');
                setTimeout(() => {
                    loader.style.display = 'none';
                }, 400); // Wait for transition
            }

            // Render Sidebar
            this.renderNavigationSidebar();

            this.renderCurrentView();
            this.checkBookmarkStatus();
        },

        /* --- NAVIGATION --- */
        /* --- NAVIGATION --- */
        async changePage(offset) {
            const step = this.state.viewMode === 'double' ? 2 : 1;
            const newIndex = this.state.currentPageIndex + (offset * step);
            const container = this.elements.readerContent;

            if (newIndex >= 0 && newIndex < this.state.currentBook.pages.length) {
                // Play Sound Immediately
                this.playSound();

                // LIGHTWEIGHT ANIMATION LOGIC
                const direction = offset > 0 ? 'next' : 'prev';
                const oldPageElement = container ? container.firstElementChild : null;

                if (oldPageElement && container) {
                    if (direction === 'next') {
                        // NEXT: Current page flips to left, disappearing.
                        // 1. Lock old page in place
                        oldPageElement.classList.add('flip-exit-next');

                        // 2. Render NEW content underneath immediately
                        this.state.currentPageIndex = newIndex;

                        // We need a wrapper for the new content to separate it from the animating one
                        const newWrapper = document.createElement('div');
                        // Render into new wrapper (off-DOM or appended?)
                        // Append it BEHIND the old one?
                        // Actually, if we append it, it usually goes last (on top). 
                        // We need to use insertBefore or absolute positioning.
                        // The CSS for .flip-exit-next handles absolute positioning (on top).
                        // So we can just append the new static page.

                        await this.renderCurrentView(true); // true = appendMode (don't clear)

                        // 3. Cleanup old after animation
                        setTimeout(() => {
                            if (oldPageElement && oldPageElement.parentNode) {
                                oldPageElement.remove();
                            }
                        }, 600); // Match CSS duration

                    } else {
                        // PREV: New page flips in from left, covering current.
                        // 1. We need to render the NEW page FIRST, but hidden/prepared?
                        // Actually, we render it ON TOP with animation.

                        const currentIndex = this.state.currentPageIndex;
                        this.state.currentPageIndex = newIndex;

                        // Create a temp container for the new page coming in
                        const newPageDiv = document.createElement('div');
                        newPageDiv.className = 'page-container flip-enter-prev';
                        // Render content into it
                        // This is tricky because renderCurrentView handles layout (single/double).
                        // Let's rely on standard render logic but cheat the container?

                        // SIMPLER STRATEGY for Prev:
                        // Just swap instantly for now to avoid complexity/heaviness, 
                        // OR: Just use the same 'flip-next' style reversed?
                        // Let's try:
                        // 1. Clear everything.
                        // 2. Render New Page.
                        // 3. (Optional) Animate? 
                        // If user wants lightweight, 'Next' animation is most important (reading flow).
                        // 'Prev' can be instant or simple fad/slide.

                        // Implementing simple "slide/fade" for Prev to save complexity
                        await this.renderCurrentView();
                    }
                } else {
                    // First load or error - just render
                    this.state.currentPageIndex = newIndex;
                    await this.renderCurrentView();
                }

                this.checkBookmarkStatus();
            }
        },

        jumpToPage(val) {
            let pageNum = parseInt(val);
            if (pageNum >= 1 && pageNum <= this.state.currentBook.pages.length) {
                this.state.currentPageIndex = pageNum - 1;
                if (this.state.viewMode === 'double' && this.state.currentPageIndex % 2 !== 0) {
                    this.state.currentPageIndex--;
                }
                this.playSound();
                this.renderCurrentView();
                this.checkBookmarkStatus();
            } else {
                if (this.elements.pageInput) this.elements.pageInput.value = this.state.currentPageIndex + 1;
            }
        },

        playSound() {
            try {
                const audio = new Audio('audio/pageflip.mp3');
                audio.volume = 1.0;
                audio.play().catch(e => console.warn("Audio play prevented", e));
            } catch (e) {
                console.error("Audio error", e);
            }
        },

        /* --- VIEW MODES --- */
        setViewMode(mode) {
            if (this.state.viewMode === mode) return;
            this.state.viewMode = mode;
            this.state.scale = 1.0;

            if (this.elements.btnSingle) this.elements.btnSingle.classList.toggle('active', mode === 'single');
            if (this.elements.btnDouble) this.elements.btnDouble.classList.toggle('active', mode === 'double');

            const wrapper = this.elements.readerView;
            if (wrapper) {
                wrapper.classList.remove('view-mode-single', 'view-mode-double');
                wrapper.classList.add(`view-mode-${mode}`);
            }

            if (mode === 'double' && this.state.currentPageIndex % 2 !== 0) {
                this.state.currentPageIndex--;
            }

            this.renderCurrentView();
        },

        zoom(amount) {
            const newScale = this.state.scale + amount;
            if (newScale >= 0.4 && newScale <= 3.0) {
                this.state.scale = newScale;
                this.renderCurrentView();
            }
        },
        toggleFullscreen() {
            if (!document.fullscreenElement) {
                document.documentElement.requestFullscreen();
            } else {
                if (document.exitFullscreen) {
                    document.exitFullscreen();
                }
            }
        },

        /* --- NAVIGATION SIDEBAR --- */
        toggleSidebar(force) {
            const sidebar = this.elements.navSidebar;
            if (!sidebar) return;

            const isShown = force !== undefined ? force : sidebar.classList.contains('sidebar-hidden');

            if (isShown) {
                sidebar.classList.remove('sidebar-hidden');
                if (this.elements.btnHome) this.elements.btnHome.classList.add('sidebar-active');
            } else {
                sidebar.classList.add('sidebar-hidden');
                if (this.elements.btnHome) this.elements.btnHome.classList.remove('sidebar-active');
            }
        },

        renderNavigationSidebar() {
            const book = this.state.currentBook;
            if (!book) return;

            // 1. Render TOC
            if (this.elements.tocList) {
                this.elements.tocList.innerHTML = '';
                if (book.toc && book.toc.length > 0) {
                    book.toc.forEach(item => {
                        const li = document.createElement('li');
                        li.textContent = item.title;
                        li.addEventListener('click', () => {
                            this.jumpToPage(item.pageIndex + 1);
                        });
                        this.elements.tocList.appendChild(li);
                    });
                } else {
                    this.elements.tocList.innerHTML = '<li class="empty-msg" style="opacity:0.5; font-style:italic;">No entries</li>';
                }
            }

            // 2. Render Animations & Interactivities from Hotspots
            const animations = [];
            const interactivities = [];

            book.hotspots.forEach(h => {
                if (!h.title) return; // Only show if name is provided

                const entry = {
                    title: h.title,
                    pageId: h.pageId,
                    hotspotId: h.id,
                    type: h.type
                };

                // Logic to categorize
                const interactiveTypes = [
                    'mcq', 'drag_drop', 'match_column', 'fill_blanks', 'find_hotspot',
                    'sequencing', 'flashcards', 'timeline', 'accordion', 'tabs', 'image_slider'
                ];

                if (h.type === 'video') {
                    animations.push(entry);
                } else if (interactiveTypes.includes(h.type)) {
                    interactivities.push(entry);
                }
            });

            const renderList = (listEl, items) => {
                if (!listEl) return;
                listEl.innerHTML = '';
                if (items.length > 0) {
                    items.forEach(item => {
                        const li = document.createElement('li');
                        li.textContent = item.title;
                        li.addEventListener('click', () => {
                            // Find page index for this pageId
                            const pageIdx = book.pages.findIndex(p => p.id === item.pageId);
                            if (pageIdx !== -1) {
                                this.jumpToPage(pageIdx + 1);
                                // After jump, open the hotspot
                                setTimeout(() => {
                                    if (window.InteractionHandler) {
                                        window.InteractionHandler.openHotspot(item.hotspotId, h => this.showModal(h));
                                    }
                                }, 500);
                            }
                        });
                        listEl.appendChild(li);
                    });
                } else {
                    listEl.innerHTML = '<li class="empty-msg" style="opacity:0.5; font-style:italic;">None found</li>';
                }
            };

            renderList(this.elements.animList, animations);
            renderList(this.elements.interactList, interactivities);
        },
        /* --- THUMBNAILS --- */
        toggleThumbnails() {
            const overlay = this.elements.thumbnailsOverlay;
            if (!overlay) return;
            const isActive = overlay.classList.contains('active');
            if (isActive) {
                overlay.classList.remove('active');
                if (this.elements.btnThumbs) this.elements.btnThumbs.classList.remove('active');
            } else {
                overlay.classList.add('active');
                if (this.elements.btnThumbs) this.elements.btnThumbs.classList.add('active');
                if (!this.state.thumbnailsRendered) this.renderThumbnails();
            }
        },

        async renderThumbnails() {
            const container = this.elements.thumbnailsOverlay;
            container.innerHTML = '';
            const pages = this.state.currentBook.pages;

            for (let i = 0; i < pages.length; i++) {
                const page = pages[i];
                const div = document.createElement('div');
                div.className = 'thumbnail-item';
                // Bookmark indicator
                if (this.state.bookmarks.includes(i)) {
                    div.classList.add('bookmarked');
                    // Add icon
                    const badge = document.createElement('div');
                    badge.innerHTML = 'â';
                    badge.style.cssText = 'position:absolute; top:2px; right:2px; color:#F59E0B; font-size:12px; z-index:10; text-shadow:0 0 2px black;';
                    div.appendChild(badge);
                }

                div.onclick = () => {
                    this.state.currentPageIndex = i;
                    if (this.state.viewMode === 'double' && i % 2 !== 0) {
                        this.state.currentPageIndex = i - 1;
                    }
                    this.renderCurrentView();
                    this.toggleThumbnails();
                };
                div.innerHTML = `<span class="thumbnail-num">${i + 1}</span>`;
                container.appendChild(div);
                this.renderThumbnailContent(page, div);
            }
            this.state.thumbnailsRendered = true;
        },

        async renderThumbnailContent(page, container) {
            try {
                if (page.fileType === 'pdf') {
                    const canvas = document.createElement('canvas');
                    const loadingTask = await this.getPDFLoadingTask(page.fileUrl);
                    const pdf = await loadingTask.promise;
                    const pageNum = Math.min(pdf.numPages, (page.pageIndex || 0) + 1);
                    const pdfPage = await pdf.getPage(pageNum);
                    const viewport = pdfPage.getViewport({ scale: 100 / pdfPage.getViewport({ scale: 1 }).width });
                    canvas.height = viewport.height;
                    canvas.width = viewport.width;
                    const ctx = canvas.getContext('2d');
                    await pdfPage.render({ canvasContext: ctx, viewport: viewport }).promise;
                    container.insertBefore(canvas, container.firstChild);
                } else {
                    const img = document.createElement('img');
                    img.src = page.fileUrl;
                    container.insertBefore(img, container.firstChild);
                }
            } catch (e) { console.error("Thumb error", e); }
        },

        /* --- MAIN RENDER --- */
        async renderCurrentView() {
            const container = this.elements.readerContent;
            if (!container) return;
            container.innerHTML = '';

            const pageCount = this.state.currentBook.pages.length;
            if (this.elements.pageNum) this.elements.pageNum.textContent = `${this.state.currentPageIndex + 1} / ${pageCount}`;
            if (this.elements.pageInput) this.elements.pageInput.value = this.state.currentPageIndex + 1;

            if (this.state.viewMode === 'single') {
                await this.renderPage(this.state.currentPageIndex, container);
            } else {
                const wrapper = document.createElement('div');
                wrapper.className = 'double-page-wrapper';
                container.appendChild(wrapper);
                let leftIndex = this.state.currentPageIndex;
                await this.renderPage(leftIndex, wrapper, true);
                if (leftIndex + 1 < pageCount) {
                    await this.renderPage(leftIndex + 1, wrapper, true);
                } else {
                    const placeholder = document.createElement('div');
                    placeholder.className = 'page-container';
                    placeholder.style.visibility = 'hidden';
                    wrapper.appendChild(placeholder);
                }
            }

            // Highlights
            const thumbItems = document.querySelectorAll('.thumbnail-item');
            if (thumbItems) {
                thumbItems.forEach((t, i) => {
                    if (i === this.state.currentPageIndex || (this.state.viewMode === 'double' && i === this.state.currentPageIndex + 1)) {
                        t.classList.add('active');
                    } else {
                        t.classList.remove('active');
                    }
                });
            }

            this.checkBookmarkStatus();
        },

        async renderPage(pageIndex, container, isDouble = false) {
            const pageData = this.state.currentBook.pages[pageIndex];
            if (!pageData) return;

            const pageDiv = document.createElement('div');
            pageDiv.className = 'page-container';

            // Layout Constants
            const HEADER_HEIGHT = 60;
            const FOOTER_HEIGHT = 70;
            // 1px top + 1px bottom = 2px total gap
            const VERTICAL_GAP = 2;
            const AVAILABLE_HEIGHT = window.innerHeight - HEADER_HEIGHT - FOOTER_HEIGHT - VERTICAL_GAP;
            const AVAILABLE_WIDTH = window.innerWidth;

            // Click to Zoom
            pageDiv.onclick = (e) => {
                if (!this.state.isHighlighting) {
                    this.openPageZoom(pageIndex);
                }
            };
            container.appendChild(pageDiv);

            // Canvas for drawing
            const highlightCanvas = document.createElement('canvas');
            highlightCanvas.className = 'highlighter-canvas';
            highlightCanvas.id = `highlight-canvas-${pageIndex}`;
            pageDiv.appendChild(highlightCanvas);

            try {
                if (pageData.fileType === 'pdf') {
                    const canvas = document.createElement('canvas');
                    pageDiv.appendChild(canvas);
                    const context = canvas.getContext('2d');

                    const url = pageData.fileUrl;
                    const loadingTask = await this.getPDFLoadingTask(url);
                    const pdfDoc = await loadingTask.promise;
                    const pageNum = Math.min(pdfDoc.numPages, (pageData.pageIndex || 0) + 1);
                    const page = await pdfDoc.getPage(pageNum);

                    const unscaledViewport = page.getViewport({ scale: 1.0 });
                    let baseScale = 1;

                    if (isDouble) {
                        const heightScale = AVAILABLE_HEIGHT / unscaledViewport.height;
                        const maxWidth = (AVAILABLE_WIDTH / 2) - 10;
                        const widthScale = maxWidth / unscaledViewport.width;
                        baseScale = Math.min(heightScale, widthScale);
                    } else {
                        const heightScale = AVAILABLE_HEIGHT / unscaledViewport.height;
                        const widthScale = (AVAILABLE_WIDTH * 0.95) / unscaledViewport.width;
                        baseScale = Math.min(heightScale, widthScale);
                    }

                    const finalScale = baseScale * this.state.scale;
                    const viewport = page.getViewport({ scale: finalScale });

                    canvas.height = viewport.height;
                    canvas.width = viewport.width;

                    // Sync Highlighter
                    highlightCanvas.width = viewport.width;
                    highlightCanvas.height = viewport.height;
                    this.setupDrawing(highlightCanvas, pageIndex);
                    this.restoreHighlights(pageIndex, highlightCanvas);

                    await page.render({ canvasContext: context, viewport: viewport }).promise;
                    this.renderHotspots(pageData.id, pageDiv);

                } else {
                    const img = document.createElement('img');
                    img.src = pageData.fileUrl;

                    img.onload = () => {
                        const naturalW = img.naturalWidth;
                        const naturalH = img.naturalHeight;

                        let baseScale = 1;
                        if (isDouble) {
                            const heightScale = AVAILABLE_HEIGHT / naturalH;
                            const maxWidth = (AVAILABLE_WIDTH / 2) - 10;
                            const widthScale = maxWidth / naturalW;
                            baseScale = Math.min(heightScale, widthScale);
                        } else {
                            const heightScale = AVAILABLE_HEIGHT / naturalH;
                            const widthScale = (AVAILABLE_WIDTH * 0.95) / naturalW;
                            baseScale = Math.min(heightScale, widthScale);
                        }

                        const finalScale = baseScale * this.state.scale;
                        const finalWidth = naturalW * finalScale;
                        const finalHeight = naturalH * finalScale;

                        img.style.width = `${finalWidth}px`;
                        img.style.height = `${finalHeight}px`;
                        img.style.maxWidth = 'none';
                        img.style.maxHeight = 'none';

                        highlightCanvas.width = finalWidth;
                        highlightCanvas.height = finalHeight;

                        this.setupDrawing(highlightCanvas, pageIndex);
                        this.restoreHighlights(pageIndex, highlightCanvas);
                        this.renderHotspots(pageData.id, pageDiv);
                    };
                    pageDiv.appendChild(img);
                }
            } catch (e) {
                console.error("Render error", e);
                pageDiv.innerHTML = `<div style="padding:20px; color:red">Error loading page</div>`;
            }
        },

        restoreHighlights(pageIndex, canvas) {
            const saved = this.state.highlights[pageIndex];
            if (!saved || !saved.length) return;
            const ctx = canvas.getContext('2d');
            ctx.lineCap = 'round';
            ctx.lineJoin = 'round';
            ctx.lineWidth = 15;
            ctx.globalAlpha = 0.25;

            // Re-draw all strokes
            saved.forEach(stroke => {
                ctx.strokeStyle = stroke.color;
                if (stroke.points.length < 2) return;

                ctx.beginPath();
                ctx.moveTo(stroke.points[0].x, stroke.points[0].y);

                // Quadratic Bezier interpolation
                for (let i = 1; i < stroke.points.length - 1; i++) {
                    const p1 = stroke.points[i];
                    const p2 = stroke.points[i + 1];
                    const midX = (p1.x + p2.x) / 2;
                    const midY = (p1.y + p2.y) / 2;
                    ctx.quadraticCurveTo(p1.x, p1.y, midX, midY);
                }
                // Last point
                const last = stroke.points[stroke.points.length - 1];
                ctx.lineTo(last.x, last.y);
                ctx.stroke();
            });
            ctx.globalAlpha = 1.0; // Reset
        },

        /* --- DRAWING --- */
        setupDrawing(canvas, pageIndex) {
            const ctx = canvas.getContext('2d');
            ctx.lineCap = 'round';
            ctx.lineJoin = 'round';
            ctx.lineWidth = 15;

            let painting = false;
            let currentPoints = [];

            const startPosition = (e) => {
                if (!this.state.isHighlighting) return;
                painting = true;
                currentPoints = [];

                // Get Color
                ctx.strokeStyle = this.state.highlightColor;
                ctx.globalAlpha = 0.25; // Transparency
                // We use source-over with alpha to allow simple layering. 
                // "multiply" is better but harder to save/restore consistently without image data.
                ctx.globalCompositeOperation = 'source-over';

                const rect = canvas.getBoundingClientRect();
                // We need to scale coords to canvas internal size
                const scaleX = canvas.width / rect.width;
                const scaleY = canvas.height / rect.height;

                const clientX = e.touches ? e.touches[0].clientX : e.clientX;
                const clientY = e.touches ? e.touches[0].clientY : e.clientY;

                const x = (clientX - rect.left) * scaleX;
                const y = (clientY - rect.top) * scaleY;

                currentPoints.push({ x, y });
                ctx.beginPath();
                ctx.moveTo(x, y);
            };

            const endPosition = () => {
                if (!painting) return;
                painting = false;
                ctx.closePath();

                // Save Stroke
                if (currentPoints.length > 0) {
                    if (!this.state.highlights[pageIndex]) this.state.highlights[pageIndex] = [];
                    const strokeIndex = this.state.highlights[pageIndex].length;
                    this.state.highlights[pageIndex].push({
                        color: this.state.highlightColor,
                        points: currentPoints
                    });

                    // Add to global history
                    this.state.highlightHistory.push({ pageIndex, strokeIndex });

                    this.saveUserData();
                }
            };

            const draw = (e) => {
                if (!painting || !this.state.isHighlighting) return;
                if (e.cancelable) e.preventDefault(); // Prevent scrolling on touch

                const rect = canvas.getBoundingClientRect();
                const scaleX = canvas.width / rect.width;
                const scaleY = canvas.height / rect.height;

                const clientX = e.touches ? e.touches[0].clientX : e.clientX;
                const clientY = e.touches ? e.touches[0].clientY : e.clientY;

                const x = (clientX - rect.left) * scaleX;
                const y = (clientY - rect.top) * scaleY;

                const lastPoint = currentPoints[currentPoints.length - 1];
                currentPoints.push({ x, y });

                // Draw segment immediately (no accumulation)
                ctx.beginPath();
                ctx.moveTo(lastPoint.x, lastPoint.y);
                ctx.lineTo(x, y);
                ctx.stroke();
            };

            canvas.addEventListener('mousedown', startPosition);
            canvas.addEventListener('mouseup', endPosition);
            canvas.addEventListener('mouseout', endPosition);
            canvas.addEventListener('mousemove', draw);

            // Touch support
            canvas.addEventListener('touchstart', startPosition, { passive: false });
            canvas.addEventListener('touchend', endPosition);
            canvas.addEventListener('touchcancel', endPosition);
            canvas.addEventListener('touchmove', draw, { passive: false });
        },

        undoHighlight() {
            if (this.state.highlightHistory.length === 0) return;

            // Pop from global history
            const lastAction = this.state.highlightHistory.pop();
            const { pageIndex } = lastAction;

            if (this.state.highlights[pageIndex] && this.state.highlights[pageIndex].length > 0) {
                this.state.highlights[pageIndex].pop();
                this.saveUserData();

                // Redraw ALL potentially visible canvases
                // In double view, both could be visible.
                const canvases = document.querySelectorAll('.highlighter-canvas');
                canvases.forEach(canvas => {
                    const idParts = canvas.id.split('-');
                    const canvasPageIndex = parseInt(idParts[idParts.length - 1]);

                    if (canvasPageIndex === pageIndex) {
                        const ctx = canvas.getContext('2d');
                        ctx.clearRect(0, 0, canvas.width, canvas.height);
                        this.restoreHighlights(pageIndex, canvas);
                    }
                });
            }
        },

        clearPageHighlights() {
            const pageIndex = this.state.currentPageIndex;
            // Also need to handle other visible page in double view?
            // User usually wants to clear what they see. 
            // In double view, maybe we should clear both or ask.
            // Let's clear ONLY the primary active page as per original intent but fix the multi-render.

            if (confirm("Clear all highlights on this page?")) {
                this.state.highlights[pageIndex] = [];

                // Remove relevant entries from history
                this.state.highlightHistory = this.state.highlightHistory.filter(h => h.pageIndex !== pageIndex);

                this.saveUserData();

                const canvases = document.querySelectorAll('.highlighter-canvas');
                canvases.forEach(canvas => {
                    const idParts = canvas.id.split('-');
                    const canvasPageIndex = parseInt(idParts[idParts.length - 1]);
                    if (canvasPageIndex === pageIndex) {
                        const ctx = canvas.getContext('2d');
                        ctx.clearRect(0, 0, canvas.width, canvas.height);
                    }
                });
            }
        },

        renderHotspots(pageId, container) {
            const hotspots = this.state.currentBook.hotspots || (window.BOOK_DATA.hotspots);
            if (hotspots) {
                const pageHotspots = hotspots.filter(h => h.pageId === pageId);
                pageHotspots.forEach(hs => {
                    const el = document.createElement('div');
                    el.className = `hotspot ${hs.type || 'interactive'}`;
                    el.style.left = hs.x + '%';
                    el.style.top = hs.y + '%';
                    el.style.width = hs.width + '%';
                    el.style.height = hs.height + '%';

                    // Create Icon
                    const icon = document.createElement('div');
                    icon.className = 'hotspot-icon';

                    let svgContent = '';
                    if (hs.type === 'video') {
                        // Play Icon
                        svgContent = `<svg width="100%" height="100%" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>`;
                    } else if (hs.type === 'audio') {
                        // Speaker Icon
                        svgContent = `<svg width="100%" height="100%" fill="currentColor" viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>`;
                    } else if (hs.type === 'fill_blanks') {
                        // Edit/Pen Icon
                        svgContent = `<svg width="100%" height="100%" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>`;
                    } else if (hs.type === 'match_column') {
                        // Shuffle/Swap Icon
                        svgContent = `<svg width="100%" height="100%" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4"/></svg>`;
                    } else if (hs.type === 'mcq') {
                        // List/Check Icon
                        svgContent = `<svg width="100%" height="100%" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"/></svg>`;
                    } else {
                        // Generic Interaction
                        svgContent = `<svg width="100%" height="100%" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M15 15l-2 5L9 9l11 4-5 2zm0 0l5 5M7.188 2.239l.777 2.897M5.136 7.965l-2.898-.777M13.95 4.05l-2.122 2.122m-5.657 5.656l-2.12 2.122"/></svg>`;
                    }
                    icon.innerHTML = svgContent;
                    el.appendChild(icon);

                    // Interaction
                    el.onclick = (e) => {
                        e.stopPropagation();
                        // Delegate to InteractionHandler
                        if (window.InteractionHandler) {
                            window.InteractionHandler.handleInteraction(hs);
                        } else {
                            console.error("InteractionHandler not found!");
                        }
                    };

                    container.appendChild(el);
                });
            }
        },

        showModal(hotspot) {
            const overlay = this.elements.modalOverlay;
            const body = this.elements.modalBody;
            if (!overlay || !body) return;

            body.innerHTML = '';
            overlay.classList.remove('hidden');

            const content = document.createElement('div');
            content.style.width = '100%';
            content.style.height = '100%';

            if (hotspot.type === 'video') {
                const video = document.createElement('video');
                video.src = hotspot.content.src;
                video.controls = true;
                video.autoplay = true;
                video.style.width = '100%';
                video.style.height = '100%';
                content.appendChild(video);
            } else if (hotspot.type === 'image') {
                const img = document.createElement('img');
                img.src = hotspot.content.src;
                img.style.maxWidth = '100%';
                img.style.maxHeight = '100%';
                img.style.objectFit = 'contain';
                content.appendChild(img);
            } else {
                content.innerHTML = `<div style="padding:40px; text-align:center;">
                    <h3>${hotspot.title || 'Interaction'}</h3>
                    <p>Refer to interactions.js for advanced handling.</p>
                </div>`;
            }

            body.appendChild(content);
        },

        handleHotspotClick(hs) {
            // Legacy method, now delegated in renderHotspots directly. 
            // Kept empty or redirected just in case.
            if (window.InteractionHandler) {
                window.InteractionHandler.handleInteraction(hs);
            }
        },

        showError(msg) {
            if (window.InteractionHandler && window.InteractionHandler.showToast) {
                window.InteractionHandler.showToast(msg, 'error');
            } else {
                const loader = document.getElementById('loading-overlay');
                if (loader) loader.innerHTML = `<div style="color:red; background:white; padding:20px;">${msg}</div>`;
            }
        },

        /* --- PDF LOADER FOR OFFLINE --- */
        async getPDFLoadingTask(url) {
            // If running via file:// protocol, use script-based companion files to bypass CORS
            if (window.location.protocol === 'file:') {
                if (window.PDF_DATA_CACHE[url]) {
                    const base64Data = window.PDF_DATA_CACHE[url].split(',')[1];
                    const binaryString = atob(base64Data);
                    const bytes = new Uint8Array(binaryString.length);
                    for (let i = 0; i < binaryString.length; i++) {
                        bytes[i] = binaryString.charCodeAt(i);
                    }
                    return pdfjsLib.getDocument({ data: bytes });
                }

                return new Promise((resolve, reject) => {
                    const script = document.createElement('script');
                    script.src = url + '.js';
                    script.onload = () => {
                        if (window.PDF_DATA_CACHE[url]) {
                            const base64Data = window.PDF_DATA_CACHE[url].split(',')[1];
                            const binaryString = atob(base64Data);
                            const bytes = new Uint8Array(binaryString.length);
                            for (let i = 0; i < binaryString.length; i++) {
                                bytes[i] = binaryString.charCodeAt(i);
                            }
                            resolve(pdfjsLib.getDocument({ data: bytes }));
                        } else {
                            // Fallback to normal loading if script didn't populate cache
                            resolve(pdfjsLib.getDocument(url));
                        }
                    };
                    script.onerror = () => {
                        // If script fails, fallback to normal loading (might fail with CORS but better than hanging)
                        resolve(pdfjsLib.getDocument(url));
                    };
                    document.head.appendChild(script);
                });
            }
            // Standard server-based loading
            return pdfjsLib.getDocument(url);
        }
    };

    // Global hook
    window.app = app;
    app.init();
});
