class InteractionHandler {
    constructor() {
        this.overlay = document.getElementById('hotspot-layer');
        this.modal = null;
        this.toastContainer = null;
        this.allHotspots = []; // To support openHotspot by ID
        this.createModal();
        this.createToastContainer();
    }

    createToastContainer() {
        this.toastContainer = document.createElement('div');
        this.toastContainer.id = 'toast-container';
        this.toastContainer.style.cssText = `
            position: fixed;
            bottom: 20px;
            right: 20px;
            z-index: 10001;
            display: flex;
            flex-direction: column;
            gap: 10px;
            pointer-events: none;
        `;
        document.body.appendChild(this.toastContainer);
    }

    showToast(message, type = 'info') {
        const toast = document.createElement('div');
        const bgColor = type === 'error' ? '#ef4444' : type === 'success' ? '#10b981' : '#3b82f6';
        const icon = type === 'error' ? '⚠️' : type === 'success' ? '✓' : 'ℹ️';

        toast.style.cssText = `
            background: white;
            color: #1f2937;
            padding: 12px 16px;
            border-radius: 8px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
            display: flex;
            align-items: center;
            gap: 8px;
            font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            font-size: 14px;
            font-weight: 500;
            border-left: 4px solid ${bgColor};
            opacity: 0;
            transform: translateX(20px);
            transition: all 0.3s ease-out;
            pointer-events: auto;
            min-width: 250px;
        `;

        toast.innerHTML = `<span style="color: ${bgColor}; font-size: 16px;">${icon}</span> ${message}`;

        this.toastContainer.appendChild(toast);

        // Animation in
        requestAnimationFrame(() => {
            toast.style.opacity = '1';
            toast.style.transform = 'translateX(0)';
        });

        // Remove after 3s
        setTimeout(() => {
            toast.style.opacity = '0';
            toast.style.transform = 'translateY(10px)';
            setTimeout(() => {
                if (toast.parentNode) toast.parentNode.removeChild(toast);
            }, 300);
        }, 3000);
    }

    createModal() {
        // Create modal container
        this.modal = document.createElement('div');
        this.modal.id = 'interaction-modal';
        this.modal.style.cssText = `
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.8);
            z-index: 10000;
            justify-content: center;
            align-items: center;
        `;
        document.body.appendChild(this.modal);
    }

    renderHotspots(hotspots, pageId) {
        this.overlay.innerHTML = ''; // Clear previous
        this.allHotspots = hotspots; // Store globally for this session

        // Filter hotspots for this page
        const pageHotspots = hotspots.filter(h => h.pageId === pageId);

        pageHotspots.forEach(h => {
            const el = document.createElement('div');
            el.className = 'hotspot';
            el.style.left = h.x + '%';
            el.style.top = h.y + '%';
            el.style.width = h.width + '%';
            el.style.height = h.height + '%';
            el.style.position = 'absolute';
            el.style.cursor = 'pointer';

            // Apply colors based on type (matching Editor)
            const getHotspotColor = (type) => {
                switch (type) {
                    case 'video': return 'rgba(244, 63, 94, 0.4)';  // Rose-500
                    case 'audio': return 'rgba(14, 165, 233, 0.4)'; // Sky-500
                    case 'image': return 'rgba(16, 185, 129, 0.4)'; // Emerald-500
                    case 'mcq': return 'rgba(245, 158, 11, 0.4)'; // Amber-500
                    case 'fill_blanks': return 'rgba(16, 185, 129, 0.4)'; // Emerald-500
                    case 'match_column': return 'rgba(124, 58, 237, 0.4)'; // Violet-600
                    case 'drag_drop': return 'rgba(236, 72, 153, 0.4)'; // Pink-500
                    default: return 'rgba(99, 102, 241, 0.4)';      // Indigo-500
                }
            };

            el.style.backgroundColor = getHotspotColor(h.type);
            el.style.border = '2px solid rgba(255, 255, 255, 0.5)';
            el.style.borderRadius = '4px'; // Slight rounded corners for better look, but still rectangular

            // Hover effect handled in CSS

            el.onclick = () => this.handleInteraction(h);
            this.overlay.appendChild(el);
        });
    }

    handleInteraction(hotspot) {
        console.log("Clicked hotspot:", hotspot);

        switch (hotspot.type) {
            case 'video':
                this.showVideoPlayer(hotspot);
                break;
            case 'audio':
                this.showAudioPlayer(hotspot);
                break;
            case 'image':
                this.showImageViewer(hotspot);
                break;
            case 'mcq':
                this.showMCQ(hotspot);
                break;
            case 'fill_blanks':
                this.showFillBlanks(hotspot);
                break;
            case 'match_column':
                this.showMatchColumn(hotspot);
                break;
            case 'drag_drop':
                this.showDragDrop(hotspot);
                break;
            case 'image_slider':
                this.showImageSlider(hotspot);
                break;
            case 'sequencing':
                this.showSequencing(hotspot);
                break;
            case 'flashcards':
                this.showFlashcards(hotspot);
                break;
            case 'timeline':
                this.showTimeline(hotspot);
                break;
            case 'accordion':
                this.showAccordion(hotspot);
                break;
            case 'tabs':
                this.showTabs(hotspot);
                break;
            case 'find_hotspot':
                this.showFindHotspot(hotspot);
                break;
            default:
                this.showToast(`Interaction type "${hotspot.type}" not yet implemented`, 'info');
        }
    }

    openHotspot(id) {
        const hotspot = this.allHotspots.find(h => h.id === id);
        if (hotspot) {
            this.handleInteraction(hotspot);
        } else {
            console.error("Hotspot not found:", id);
        }
    }

    showTimeline(hotspot) {
        const timelineData = hotspot.content.timeline || {};
        const events = timelineData.events || [];
        const direction = timelineData.direction || 'horizontal';

        if (events.length === 0) {
            this.showToast('Timeline not configured (add events in Editor)', 'error');
            return;
        }

        const renderTimeline = () => {
            let timelineHTML = '';

            if (direction === 'horizontal') {
                const points = events.map((evt, idx) => `
                    <div class="timeline-point" onclick="window.InteractionHandler.selectTimelineEvent(${idx})" style="left: ${(idx / (events.length - 1)) * 100}%">
                        <div class="point-marker"></div>
                        <div class="point-date">${evt.date}</div>
                    </div>
                `).join('');

                timelineHTML = `
                    <div class="timeline-horizontal-container">
                        <div class="timeline-line"></div>
                        ${points}
                    </div>
                    <div id="timeline-detail-card" class="timeline-card">
                        <div class="placeholder-text">Click an event to view details</div>
                    </div>
                `;
            } else {
                // Vertical
                timelineHTML = `
                    <div class="timeline-vertical-container">
                        ${events.map((evt, idx) => `
                            <div class="timeline-vertical-item ${idx % 2 === 0 ? 'left' : 'right'}">
                                <div class="timeline-vertical-content">
                                    <h3 class="timeline-date">${evt.date}</h3>
                                    ${evt.image ? `<img src="${evt.image}" alt="${evt.title}" class="timeline-image">` : ''}
                                    <h4 class="timeline-title">${evt.title}</h4>
                                    <p class="timeline-desc">${evt.description}</p>
                                </div>
                            </div>
                        `).join('')}
                    </div>
                `;
            }

            return `
                <div style="background: white; padding: 30px; border-radius: 12px; max-width: 900px; width: 90%; max-height: 90vh; overflow-y: auto; position: relative; display: flex; flex-direction: column;">
                    <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                    <h2 style="margin: 0 0 20px 0; color: #333;">Timeline</h2>
                    ${timelineHTML}
                </div>
            `;
        };

        // Helper to select event (Horizontal only)
        window.timelineState = { events };
        this.openModal(renderTimeline());
    }

    selectTimelineEvent(index) {
        const evt = window.timelineState.events[index];
        const card = document.getElementById('timeline-detail-card');
        if (card) {
            card.innerHTML = `
                <div class="timeline-card-content animate-fade-in">
                    ${evt.image ? `<img src="${evt.image}" class="timeline-card-image" />` : ''}
                    <div class="timeline-card-text">
                        <h3>${evt.date} - ${evt.title}</h3>
                        <p>${evt.description}</p>
                    </div>
                </div>
            `;

            // Highlight active point
            document.querySelectorAll('.timeline-point').forEach((el, i) => {
                if (i === index) el.classList.add('active');
                else el.classList.remove('active');
            });
        }
    }

    showAccordion(hotspot) {
        const accordionData = hotspot.content.accordion || {};
        const items = accordionData.items || [];

        if (items.length === 0) {
            this.showToast('Accordion not configured (add items in Editor)', 'error');
            return;
        }

        const renderAccordion = () => {
            // We can check which one is active if we want persistence, 
            // but strictly vanilla logic usually starts all closed or first open.
            // We'll let them start all closed.

            const itemsHTML = items.map((item, idx) => `
                <div class="accordion-item">
                    <button class="accordion-header" onclick="window.InteractionHandler.toggleAccordion(${idx})">
                        <span class="accordion-title">${item.title}</span>
                        <span class="accordion-icon" id="acc-icon-${idx}">+</span>
                    </button>
                    <div class="accordion-content" id="acc-content-${idx}" style="max-height: 0; overflow: hidden; transition: max-height 0.3s ease;">
                        <div class="accordion-body">
                            ${item.image ? `<img src="${item.image}" alt="Section Image" class="accordion-image" style="width: 100%; max-height: 300px; object-fit: contain; margin-bottom: 15px; border-radius: 4px;" />` : ''}
                            ${item.content}
                        </div>
                    </div>
                </div>
             `).join('');

            return `
                <div style="background: white; padding: 30px; border-radius: 12px; max-width: 800px; width: 90%; max-height: 90vh; overflow-y: auto; position: relative; display: flex; flex-direction: column;">
                    <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                    <h2 style="margin: 0 0 20px 0; color: #333;">Info Section</h2>
                    <div class="accordion-container">
                        ${itemsHTML}
                    </div>
                </div>
             `;
        };

        this.openModal(renderAccordion());
    }

    toggleAccordion(index) {
        const content = document.getElementById(`acc-content-${index}`);
        const icon = document.getElementById(`acc-icon-${index}`);

        // Check current state
        const isOpen = content.style.maxHeight !== '0px' && content.style.maxHeight !== '0';

        if (isOpen) {
            content.style.maxHeight = '0px';
            icon.textContent = '+';
            icon.style.transform = 'rotate(0deg)';
        } else {
            // Close others (Optional, usually better UX)
            // document.querySelectorAll('.accordion-content').forEach(el => el.style.maxHeight = '0px');
            // document.querySelectorAll('.accordion-icon').forEach(el => { el.textContent = '+'; el.style.transform = 'rotate(0deg)';});

            content.style.maxHeight = content.scrollHeight + 'px';
            icon.textContent = '−'; // Minus sign
            icon.style.transform = 'rotate(180deg)';
        }
    }

    showTabs(hotspot) {
        const tabsData = hotspot.content.tabs || {};
        const items = tabsData.items || [];

        if (items.length === 0) {
            this.showToast('Tabs not configured (add items in Editor)', 'error');
            return;
        }

        const renderTabs = () => {
            const tabHeaders = items.map((item, idx) => `
                <button class="tab-header ${idx === 0 ? 'active' : ''}" onclick="window.InteractionHandler.switchTab(${idx})">
                    ${item.title}
                </button>
             `).join('');

            const tabContents = items.map((item, idx) => `
                <div class="tab-content ${idx === 0 ? 'active' : ''}" id="tab-content-${idx}">
                    ${item.image ? `<img src="${item.image}" alt="Tab Image" class="tab-image" style="width: 100%; max-height: 300px; object-fit: contain; margin-bottom: 20px; border-radius: 8px;" />` : ''}
                    <div class="tab-body">
                        ${item.content}
                    </div>
                </div>
             `).join('');

            return `
                <div style="background: white; padding: 30px; border-radius: 12px; max-width: 800px; width: 90%; max-height: 90vh; overflow-y: auto; position: relative; display: flex; flex-direction: column;">
                    <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                    <h2 style="margin: 0 0 20px 0; color: #333;">Info Tabs</h2>
                    <div class="tabs-container">
                        <div class="tabs-header-row">
                            ${tabHeaders}
                        </div>
                        <div class="tabs-body-area">
                            ${tabContents}
                        </div>
                    </div>
                </div>
             `;
        };

        this.openModal(renderTabs());
    }

    showFindHotspot(hotspot) {
        const gameData = hotspot.content.find_hotspot || {};
        const targets = gameData.targets || [];
        const image = gameData.image;

        if (!image) {
            this.showToast('Find Hotspot not configured (missing image)', 'error');
            return;
        }

        const renderGame = () => {
            return `
                <div style="background: #1a1a1a; padding: 20px; border-radius: 12px; max-width: 900px; width: 95%; max-height: 90vh; display: flex; flex-direction: column; color: white;">
                    <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn" style="color: white; z-index: 10;">&times;</button>
                    
                    <div style="text-align: center; margin-bottom: 10px; flex-shrink: 0;">
                        <h2 style="margin: 0; color: #fff;">${gameData.prompt || 'Find the item in the image'}</h2>
                        <p style="margin: 5px 0 0 0; font-size: 14px; color: #aaa;">Click the correct area on the image</p>
                    </div>

                    <div id="fh-container" style="position: relative; width: 100%; aspect-ratio: 16/9; margin: 0 auto; border: 2px solid #333; border-radius: 8px; overflow: hidden; cursor: crosshair; display: flex; justify-content: center; align-items: center; background: #000;">
                        <img src="${image}" style="width: 100%; height: 100%; object-fit: contain; display: block;" id="fh-image" />
                        
                        <!-- Click Feedback Layer -->
                        <div id="fh-feedback" style="position: absolute; inset: 0; pointer-events: none;"></div>
                    </div>
                </div>
             `;
        };

        this.openModal(renderGame());

        // Attach Click Listener after render
        setTimeout(() => {
            const container = document.getElementById('fh-container');
            const img = document.getElementById('fh-image');

            if (container && img) {
                container.onclick = (e) => {
                    // Calculate click position as percentage
                    const rect = container.getBoundingClientRect();
                    const x = ((e.clientX - rect.left) / rect.width) * 100;
                    const y = ((e.clientY - rect.top) / rect.height) * 100;

                    // Check if hit any target
                    // Target structure: { x, y, width, height } (all in %)
                    const hit = targets.find(t =>
                        x >= parseFloat(t.x) && x <= (parseFloat(t.x) + parseFloat(t.width)) &&
                        y >= parseFloat(t.y) && y <= (parseFloat(t.y) + parseFloat(t.height))
                    );

                    const feedbackEl = document.getElementById('fh-feedback');
                    const marker = document.createElement('div');
                    marker.style.position = 'absolute';
                    marker.style.left = x + '%';
                    marker.style.top = y + '%';
                    marker.style.transform = 'translate(-50%, -50%)';
                    marker.style.width = '40px';
                    marker.style.height = '40px';
                    marker.style.borderRadius = '50%';
                    marker.style.border = '3px solid';
                    marker.style.animation = 'ping 1s cubic-bezier(0, 0, 0.2, 1) infinite';

                    if (hit) {
                        // Success
                        marker.style.borderColor = '#4ade80'; // Green
                        marker.style.backgroundColor = 'rgba(74, 222, 128, 0.3)';
                        this.showToast('Correct! You found it.', 'success');

                        // Optional: Highlight the target box
                        const targetBox = document.createElement('div');
                        targetBox.style.position = 'absolute';
                        targetBox.style.left = hit.x + '%';
                        targetBox.style.top = hit.y + '%';
                        targetBox.style.width = hit.width + '%';
                        targetBox.style.height = hit.height + '%';
                        targetBox.style.border = '2px solid #4ade80';
                        targetBox.style.backgroundColor = 'rgba(74, 222, 128, 0.2)';
                        targetBox.style.animation = 'fadeIn 0.5s';
                        feedbackEl.appendChild(targetBox);
                    } else {
                        // Miss
                        marker.style.borderColor = '#ef4444'; // Red
                        marker.style.backgroundColor = 'rgba(239, 68, 68, 0.3)';
                        this.showToast('Not quite. Keep looking.', 'error');

                        // Shake effect on container
                        container.animate([
                            { transform: 'translate(0px, 0px)' },
                            { transform: 'translate(-5px, 0px)' },
                            { transform: 'translate(5px, 0px)' },
                            { transform: 'translate(0px, 0px)' }
                        ], { duration: 300 });
                    }

                    feedbackEl.appendChild(marker);

                    // Remove marker after animation
                    setTimeout(() => marker.remove(), 1000);
                };
            }
        }, 100);
    }

    switchTab(index) {
        // Remove active class from all headers and contents
        document.querySelectorAll('.tab-header').forEach(el => el.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));

        // Add active class to clicked index (NOTE: This assumes one set of tabs open at a time, which is true for modal)
        document.querySelectorAll('.tabs-header-row .tab-header')[index].classList.add('active');
        document.getElementById(`tab-content-${index}`).classList.add('active');
    }

    showSequencing(hotspot) {
        const correctItems = hotspot.content.sequenceItems || [];
        if (correctItems.length < 2) {
            this.showToast('Sequence not configured (needs 2+ items)', 'error');
            return;
        }

        // Shuffle logic
        const shuffled = [...correctItems];
        for (let i = shuffled.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
        }

        const renderList = () => {
            return shuffled.map(item => `
                <div class="sequence-item" draggable="true" data-id="${item.id}"
                     style="padding: 12px; margin: 8px 0; background: white; border: 1px solid #ddd; border-radius: 6px; cursor: move; display: flex; align-items: center; gap: 10px; user-select: none; transition: transform 0.2s, box-shadow 0.2s;">
                    <div style="color: #999; cursor: grab;">☰</div>
                    ${item.image ? `<img src="${item.image}" style="height: 40px; width: auto; border-radius: 4px; pointer-events: none;">` : ''}
                    <div style="flex: 1; pointer-events: none;">${item.text || 'Item'}</div>
                </div>
            `).join('');
        };

        const content = `
            <div style="background: white; padding: 30px; border-radius: 12px; max-width: 600px; width: 90%; max-height: 90vh; overflow-y: auto; position: relative;">
                <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                <h2 style="margin: 0 0 10px 0; color: #333;">Arrange in Correct Order</h2>
                <p style="margin-bottom: 20px; color: #666; font-size: 14px;">Drag and drop the items to reorder them.</p>

                <div id="sequence-list" style="margin-bottom: 20px;">
                    ${renderList()}
                </div>

                <div id="seq-feedback" style="margin-bottom: 15px; padding: 10px; border-radius: 6px; display: none;"></div>

                <div style="display: flex; gap: 10px;">
                    <button id="seq-submit" style="padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 6px; cursor: pointer; flex: 1;">Check Order</button>
                    <button id="seq-reset" style="padding: 10px 20px; background: #6c757d; color: white; border: none; border-radius: 6px; cursor: pointer;">Reset</button>
                </div>
            </div>
        `;

        this.openModal(content);

        // Vanilla JS Drag & Drop Logic
        setTimeout(() => {
            const list = document.getElementById('sequence-list');
            const submitBtn = document.getElementById('seq-submit');
            const resetBtn = document.getElementById('seq-reset');

            let draggedItem = null;

            list.addEventListener('dragstart', (e) => {
                draggedItem = e.target;
                e.target.style.opacity = '0.5';
                e.dataTransfer.effectAllowed = 'move';
            });

            list.addEventListener('dragend', (e) => {
                e.target.style.opacity = '1';
                draggedItem = null;
                // Update internal 'shuffled' array to match DOM order
                const newOrderIds = Array.from(list.children).map(el => el.getAttribute('data-id'));
                // Re-sort 'shuffled' based on newOrderIds
                const newShuffled = [];
                newOrderIds.forEach(id => {
                    const item = shuffled.find(i => i.id === id);
                    if (item) newShuffled.push(item);
                });
                // Update reference (mutating array contents)
                shuffled.length = 0;
                shuffled.push(...newShuffled);
            });

            list.addEventListener('dragover', (e) => {
                e.preventDefault(); // Allow drop
                const afterElement = getDragAfterElement(list, e.clientY);
                if (afterElement == null) {
                    list.appendChild(draggedItem);
                } else {
                    list.insertBefore(draggedItem, afterElement);
                }
            });

            // Helper to find position
            function getDragAfterElement(container, y) {
                const draggableElements = [...container.querySelectorAll('.sequence-item:not([style*="opacity: 0.5"])')];

                return draggableElements.reduce((closest, child) => {
                    const box = child.getBoundingClientRect();
                    const offset = y - box.top - box.height / 2;
                    if (offset < 0 && offset > closest.offset) {
                        return { offset: offset, element: child };
                    } else {
                        return closest;
                    }
                }, { offset: Number.NEGATIVE_INFINITY }).element;
            }

            // Logic
            submitBtn.onclick = () => {
                // Check order
                let isCorrect = true;
                for (let i = 0; i < shuffled.length; i++) {
                    if (shuffled[i].id !== correctItems[i].id) {
                        isCorrect = false;
                        break;
                    }
                }

                const feedback = document.getElementById('seq-feedback');
                feedback.style.display = 'block';
                feedback.style.background = isCorrect ? '#d4edda' : '#fff3cd';
                feedback.style.color = isCorrect ? '#155724' : '#856404';
                feedback.style.border = `1px solid ${isCorrect ? '#c3e6cb' : '#ffeaa7'}`;
                feedback.innerHTML = isCorrect ? '✓ Correct Sequence!' : '✗ Incorrect order. Try again.';
            };

            resetBtn.onclick = () => {
                this.closeModal();
                this.showSequencing(hotspot); // Reload to reshuffle
            };

        }, 100);
    }

    showImageSlider(hotspot) {
        const beforeImg = hotspot.content.beforeImage;
        const afterImg = hotspot.content.afterImage;
        const labelBefore = hotspot.content.labelBefore || 'Before';
        const labelAfter = hotspot.content.labelAfter || 'After';

        if (!beforeImg || !afterImg) {
            this.showToast('Image Slider incomplete (missing images)', 'error');
            return;
        }

        const content = `
            <div style="background: white; padding: 20px; border-radius: 12px; max-width: 900px; width: 90%; height: 80vh; position: relative; display: flex; flex-direction: column;">
                <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                <div style="margin-bottom: 10px; text-align: center; color: #333; font-weight: bold;">Compare: ${labelBefore} vs ${labelAfter}</div>
                
                <div class="compare-container" id="slider-compare">
                    <img src="${afterImg}" class="compare-img" style="position: absolute; top:0; left:0;">
                    
                    <div class="compare-overlay" id="slider-overlay">
                        <img src="${beforeImg}" class="compare-img" style="width: auto; height: 100%; max-width: none;">
                    </div>
                    
                    <div class="compare-handle" id="slider-handle">
                        <div style="width: 30px; height: 30px; background: white; border-radius: 50%; box-shadow: 0 2px 6px rgba(0,0,0,0.3); display: flex; align-items: center; justify-content: center;">
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                                <path d="M18 8L22 12L18 16"></path>
                                <path d="M6 8L2 12L6 16"></path>
                            </svg>
                        </div>
                    </div>

                    <div style="position: absolute; bottom: 10px; left: 10px; background: rgba(0,0,0,0.6); color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; z-index: 20; pointer-events: none;">
                        ${labelBefore}
                    </div>
                    <div style="position: absolute; bottom: 10px; right: 10px; background: rgba(0,0,0,0.6); color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; z-index: 20; pointer-events: none;">
                        ${labelAfter}
                    </div>
                </div>
            </div>
        `;

        this.openModal(content);

        // Initialize Slider Logic
        setTimeout(() => {
            const container = document.getElementById('slider-compare');
            const overlay = document.getElementById('slider-overlay');
            const handle = document.getElementById('slider-handle');
            const beforeImgEl = overlay.querySelector('img');

            if (!container || !overlay || !handle) return;

            // Sync overlay image width to container to maintain aspect ratio match
            // Actually, for object-fit contain, checking real rendered dims is safer, 
            // but setting width to container's width works if both are 100% height/width
            const syncDimensions = () => {
                if (beforeImgEl) beforeImgEl.style.width = container.offsetWidth + 'px';
            };

            // Initial sync
            syncDimensions();
            new ResizeObserver(syncDimensions).observe(container);

            let isDragging = false;

            const move = (e) => {
                const rect = container.getBoundingClientRect();
                const clientX = e.touches ? e.touches[0].clientX : e.clientX;

                let x = clientX - rect.left;
                if (x < 0) x = 0;
                if (x > rect.width) x = rect.width;

                const percent = (x / rect.width) * 100;
                overlay.style.width = percent + '%';
                handle.style.left = percent + '%';
            };

            handle.addEventListener('mousedown', () => isDragging = true);
            handle.addEventListener('touchstart', () => isDragging = true);

            window.addEventListener('mouseup', () => isDragging = false);
            window.addEventListener('touchend', () => isDragging = false);

            container.addEventListener('mousemove', (e) => {
                if (!isDragging) return;
                move(e);
            });

            container.addEventListener('touchmove', (e) => {
                if (!isDragging) return;
                move(e);
            });

            // Allow click to jump
            container.addEventListener('click', (e) => {
                move(e);
            });
        }, 100);
    }

    showVideoPlayer(hotspot) {
        const content = `
            <div style="background: white; padding: 20px; border-radius: 12px; max-width: 800px; width: 90%; position: relative;">
                <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                <h2 style="margin: 0 0 15px 0; color: #333;">Video</h2>
                <video controls autoplay style="width: 100%; border-radius: 8px; max-height: 80vh;">
                    <source src="${hotspot.content.src}" type="video/mp4">
                    Your browser does not support video.
                </video>
            </div>
        `;
        this.openModal(content);
    }

    showAudioPlayer(hotspot) {
        const content = `
            <div style="background: white; padding: 30px; border-radius: 12px; max-width: 600px; width: 90%; position: relative;">
                <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                <h2 style="margin: 0 0 20px 0; color: #333; text-align: center;">Audio</h2>
                
                <div class="audio-player-container" style="display: flex; flex-direction: column; gap: 20px; align-items: center;">
                    ${hotspot.content.image ? `
                        <div style="width: 100%; max-height: 400px; display: flex; justify-content: center; align-items: center; border-radius: 12px; overflow: hidden; background: #f8fafc;">
                            <img src="${hotspot.content.image}" style="max-width: 100%; max-height: 100%; object-fit: contain; box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);">
                        </div>
                    ` : `
                        <div style="width: 100%; aspect-ratio: 1; display: flex; items-center; justify-center; background: #f1f5f9; border-radius: 12px;">
                           <svg style="width: 64px; height: 64px; color: #94a3b8;" fill="currentColor" viewBox="0 0 24 24"><path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/></svg>
                        </div>
                    `}
                    
                    <div style="width: 100%; padding: 10px 0;">
                        <audio controls style="width: 100%; height: 40px; border-radius: 8px;">
                            <source src="${hotspot.content.src}" type="audio/mpeg">
                            Your browser does not support audio.
                        </audio>
                    </div>
                </div>
            </div>
        `;
        this.openModal(content);
    }

    showImageViewer(hotspot) {
        const content = `
            <div style="background: white; padding: 20px; border-radius: 12px; max-width: 90%; max-height: 90vh; overflow: auto; position: relative; display: flex; flex-direction: column; align-items: center;">
                <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                <img src="${hotspot.content.src}" style="max-width: 100%; height: auto; border-radius: 8px;">
            </div>
        `;
        this.openModal(content);
    }

    showMCQ(hotspot) {
        const questions = hotspot.content.questions || [];
        if (questions.length === 0) {
            this.showToast('No questions configured', 'error');
            return;
        }

        // Initialize MCQ state globally FIRST
        window.mcqState = {
            questions,
            currentQuestionIndex: 0,
            userAnswers: new Array(questions.length).fill(null),
            controls: hotspot.content.controls || { hasSubmit: true, hasReset: true, hasShowAnswer: false },
            renderQuestion: null
        };

        const renderQuestion = () => {
            const { questions, currentQuestionIndex, userAnswers, controls } = window.mcqState;
            const q = questions[currentQuestionIndex];
            const isMulti = q.multiSelect || false;

            // userAnswer is either index (number) or array of indices (number[])
            const userAnswer = userAnswers[currentQuestionIndex];

            let optionsHTML = q.options.map((opt, idx) => {
                let isSelected = false;
                if (isMulti) {
                    isSelected = Array.isArray(userAnswer) && userAnswer.includes(idx);
                } else {
                    isSelected = userAnswer === idx;
                }

                return `
                    <div class="mcq-option" onclick="window.InteractionHandler.selectMCQOption(${currentQuestionIndex}, ${idx})" 
                         style="padding: 12px; margin: 8px 0; border: 2px solid ${isSelected ? '#4CAF50' : '#ddd'}; border-radius: 8px; cursor: pointer; background: ${isSelected ? '#e8f5e9' : 'white'}; display: flex; align-items: center; gap: 10px;">
                        <div style="width: 20px; height: 20px; border-radius: ${isMulti ? '4px' : '50%'}; border: 2px solid ${isSelected ? '#4CAF50' : '#999'}; background: ${isSelected ? '#4CAF50' : 'white'}; flex-shrink: 0; display: flex; align-items: center; justify-content: center;">
                            ${isSelected && isMulti ? '<span style="color: white; font-size: 14px; font-weight: bold;">✓</span>' : ''}
                        </div>
                        <div style="flex: 1;">
                            ${opt.image ? `<img src="${opt.image}" style="max-width: 100px; height: auto; margin-bottom: 5px; border-radius: 4px;">` : ''}
                            <div>${opt.text}</div>
                        </div>
                    </div>
                `;
            }).join('');

            const content = `
                <div style="background: white; padding: 30px; border-radius: 12px; max-width: 700px; width: 90%; max-height: 90vh; overflow-y: auto; position: relative;">
                    <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; margin-right: 30px;">
                        <h2 style="margin: 0; color: #333;">Question ${currentQuestionIndex + 1} of ${questions.length}</h2>
                        ${isMulti ? '<span style="background: #e0e7ff; color: #4338ca; text-xs px-2 py-1 rounded-full font-medium">Multiple Answers</span>' : ''}
                    </div>
                    
                    ${q.image ? `<img src="${q.image}" style="max-width: 100%; height: auto; margin-bottom: 15px; border-radius: 8px;">` : ''}
                    
                    <p style="font-size: 18px; margin-bottom: 20px; color: #333;">${q.text}</p>
                    
                    <div id="mcq-options">${optionsHTML}</div>
                    
                    <div id="mcq-feedback" style="margin-top: 15px; padding: 10px; border-radius: 6px; display: none;"></div>
                    
                    <div style="margin-top: 20px; display: flex; gap: 10px; flex-wrap: wrap;">
                        ${controls.hasSubmit ? `<button onclick="window.InteractionHandler.submitMCQ(${currentQuestionIndex})" style="padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 6px; cursor: pointer; flex: 1;">Submit</button>` : ''}
                        ${controls.hasReset ? `<button onclick="window.InteractionHandler.resetMCQ(${currentQuestionIndex})" style="padding: 10px 20px; background: #6c757d; color: white; border: none; border-radius: 6px; cursor: pointer;">Reset</button>` : ''}
                        ${controls.hasShowAnswer ? `<button onclick="window.InteractionHandler.showMCQAnswer(${currentQuestionIndex})" style="padding: 10px 20px; background: #28a745; color: white; border: none; border-radius: 6px; cursor: pointer;">Show Answer</button>` : ''}
                    </div>
                    
                    ${questions.length > 1 ? `
                        <div style="margin-top: 20px; display: flex; gap: 10px;">
                            <button onclick="window.InteractionHandler.prevMCQQuestion()" ${currentQuestionIndex === 0 ? 'disabled' : ''} style="padding: 10px 20px; background: #6c757d; color: white; border: none; border-radius: 6px; cursor: pointer; flex: 1;">← Previous</button>
                            <button onclick="window.InteractionHandler.nextMCQQuestion()" ${currentQuestionIndex === questions.length - 1 ? 'disabled' : ''} style="padding: 10px 20px; background: #6c757d; color: white; border: none; border-radius: 6px; cursor: pointer; flex: 1;">Next →</button>
                        </div>
                    ` : ''}
                </div>
            `;

            this.modal.innerHTML = content;
        };

        window.mcqState.renderQuestion = renderQuestion;
        this.openModal(''); // Show modal first
        renderQuestion();   // Then render content
    }


    selectMCQOption(questionIndex, optionIndex) {
        const { questions, userAnswers } = window.mcqState;
        const q = questions[questionIndex];
        const isMulti = q.multiSelect || false;

        if (isMulti) {
            let current = userAnswers[questionIndex];
            if (!Array.isArray(current)) current = [];

            if (current.includes(optionIndex)) {
                current = current.filter(i => i !== optionIndex);
            } else {
                current.push(optionIndex);
            }

            window.mcqState.userAnswers[questionIndex] = current.length > 0 ? current : null;
        } else {
            window.mcqState.userAnswers[questionIndex] = optionIndex;
        }
        window.mcqState.renderQuestion();
    }

    submitMCQ(questionIndex) {
        const { questions, userAnswers } = window.mcqState;
        const q = questions[questionIndex];
        const userAnswer = userAnswers[questionIndex];

        if (userAnswer === null) {
            this.showToast('Please select an answer first', 'error');
            return;
        }

        let isCorrect = false;
        if (q.multiSelect) {
            const correctIndices = q.options.map((o, i) => o.isCorrect ? i : -1).filter(i => i !== -1);
            const selectedIndices = userAnswer || [];

            isCorrect = correctIndices.length === selectedIndices.length &&
                correctIndices.every(i => selectedIndices.includes(i));
        } else {
            const correctIndex = q.options.findIndex(opt => opt.isCorrect);
            isCorrect = userAnswer === correctIndex;
        }

        const feedback = document.getElementById('mcq-feedback');
        feedback.style.display = 'block';
        feedback.style.background = isCorrect ? '#d4edda' : '#f8d7da';
        feedback.style.color = isCorrect ? '#155724' : '#721c24';
        feedback.style.border = `1px solid ${isCorrect ? '#c3e6cb' : '#f5c6cb'}`;
        feedback.innerHTML = isCorrect ? '✓ Correct!' : '✗ Incorrect. Try again!';
    }

    resetMCQ(questionIndex) {
        window.mcqState.userAnswers[questionIndex] = null;
        const feedback = document.getElementById('mcq-feedback');
        if (feedback) feedback.style.display = 'none';
        window.mcqState.renderQuestion();
    }

    showMCQAnswer(questionIndex) {
        const { questions } = window.mcqState;
        const q = questions[questionIndex];

        const correctOptions = q.options.filter(opt => opt.isCorrect);
        const answerText = correctOptions.map(o => o.text).join(', ');

        const feedback = document.getElementById('mcq-feedback');
        feedback.style.display = 'block';
        feedback.style.background = '#d1ecf1';
        feedback.style.color = '#0c5460';
        feedback.style.border = '1px solid #bee5eb';
        feedback.innerHTML = `Correct Answer(s): ${answerText}`;
    }

    nextMCQQuestion() {
        if (window.mcqState.currentQuestionIndex < window.mcqState.questions.length - 1) {
            window.mcqState.currentQuestionIndex++;
            window.mcqState.renderQuestion();
        }
    }

    prevMCQQuestion() {
        if (window.mcqState.currentQuestionIndex > 0) {
            window.mcqState.currentQuestionIndex--;
            window.mcqState.renderQuestion();
        }
    }

    showFillBlanks(hotspot) {
        const sentence = hotspot.content.sentence || '';
        const options = hotspot.content.blankOptions || [];
        const controls = hotspot.content.controls || { hasSubmit: true, hasReset: true, hasShowAnswer: false };

        if (!sentence || options.length === 0) {
            this.showToast('Fill in the Blanks not configured', 'error');
            return;
        }

        const blanks = sentence.split('{{blank}}');
        const userAnswers = new Array(blanks.length - 1).fill(null);

        const renderFIB = () => {
            let sentenceHTML = '';
            blanks.forEach((part, idx) => {
                sentenceHTML += `<span>${part}</span>`;
                if (idx < blanks.length - 1) {
                    const answer = userAnswers[idx];
                    sentenceHTML += `
                        <span class="blank-slot" data-index="${idx}" 
                              style="display: inline-block; min-width: 100px; padding: 5px 10px; margin: 0 5px; border: 2px dashed #007bff; border-radius: 4px; background: #f0f8ff; cursor: pointer;"
                              ondrop="window.InteractionHandler.dropOnBlank(event, ${idx})" 
                              ondragover="event.preventDefault()">
                            ${answer !== null ? options[answer].text : '_____'}
                        </span>
                    `;
                }
            });

            const optionsHTML = options.map((opt, idx) => {
                const isUsed = userAnswers.includes(idx);
                return `
                    <div draggable="true" 
                         ondragstart="window.InteractionHandler.dragStart(event, ${idx})"
                         style="padding: 10px 15px; margin: 5px; background: ${isUsed ? '#e0e0e0' : '#007bff'}; color: ${isUsed ? '#999' : 'white'}; border-radius: 6px; cursor: ${isUsed ? 'not-allowed' : 'grab'}; display: inline-block; user-select: none;">
                        ${opt.image ? `<img src="${opt.image}" style="max-width: 50px; height: auto; margin-right: 5px; vertical-align: middle;">` : ''}
                        ${opt.text}
                    </div>
                `;
            }).join('');

            const content = `
                <div style="background: white; padding: 30px; border-radius: 12px; max-width: 800px; width: 90%; max-height: 90vh; overflow-y: auto; position: relative;">
                    <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; margin-right: 30px;">
                        <h2 style="margin: 0; color: #333;">Fill in the Blanks</h2>
                    </div>
                    
                    <div style="font-size: 18px; line-height: 2; margin-bottom: 30px; padding: 20px; background: #f8f9fa; border-radius: 8px;">
                        ${sentenceHTML}
                    </div>
                    
                    <div style="margin-bottom: 20px;">
                        <h3 style="margin-bottom: 10px; color: #666;">Drag options below:</h3>
                        <div id="fib-options" style="display: flex; flex-wrap: wrap; gap: 5px;">
                            ${optionsHTML}
                        </div>
                    </div>
                    
                    <div id="fib-feedback" style="margin-top: 15px; padding: 10px; border-radius: 6px; display: none;"></div>
                    
                    <div style="margin-top: 20px; display: flex; gap: 10px;">
                        ${controls.hasSubmit ? `<button onclick="window.InteractionHandler.submitFIB()" style="padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 6px; cursor: pointer; flex: 1;">Submit</button>` : ''}
                        ${controls.hasReset ? `<button onclick="window.InteractionHandler.resetFIB()" style="padding: 10px 20px; background: #6c757d; color: white; border: none; border-radius: 6px; cursor: pointer;">Reset</button>` : ''}
                        ${controls.hasShowAnswer ? `<button onclick="window.InteractionHandler.showFIBAnswer()" style="padding: 10px 20px; background: #28a745; color: white; border: none; border-radius: 6px; cursor: pointer;">Show Answer</button>` : ''}
                    </div>
                </div>
            `;

            this.modal.innerHTML = content;
        };

        window.fibState = { sentence, options, userAnswers, controls, renderFIB };
        renderFIB();
        this.modal.style.display = 'flex';
    }

    dragStart(event, optionIndex) {
        event.dataTransfer.setData('optionIndex', optionIndex);
    }

    dropOnBlank(event, blankIndex) {
        event.preventDefault();
        const optionIndex = parseInt(event.dataTransfer.getData('optionIndex'));
        window.fibState.userAnswers[blankIndex] = optionIndex;
        window.fibState.renderFIB();
    }

    submitFIB() {
        const { options, userAnswers } = window.fibState;
        let correct = 0;
        let total = userAnswers.length;

        userAnswers.forEach((answer, idx) => {
            if (answer !== null && options[answer].blankIndex === idx) {
                correct++;
            }
        });

        const feedback = document.getElementById('fib-feedback');
        feedback.style.display = 'block';
        const isAllCorrect = correct === total;
        feedback.style.background = isAllCorrect ? '#d4edda' : '#fff3cd';
        feedback.style.color = isAllCorrect ? '#155724' : '#856404';
        feedback.style.border = `1px solid ${isAllCorrect ? '#c3e6cb' : '#ffeaa7'}`;
        feedback.innerHTML = `Score: ${correct}/${total} ${isAllCorrect ? '✓ Perfect!' : ''}`;
    }

    resetFIB() {
        window.fibState.userAnswers.fill(null);
        const feedback = document.getElementById('fib-feedback');
        if (feedback) feedback.style.display = 'none';
        window.fibState.renderFIB();
    }

    showFIBAnswer() {
        const { options } = window.fibState;
        const answers = options.map(opt => `Blank ${opt.blankIndex + 1}: ${opt.text}`).join('<br>');
        const feedback = document.getElementById('fib-feedback');
        feedback.style.display = 'block';
        feedback.style.background = '#d1ecf1';
        feedback.style.color = '#0c5460';
        feedback.style.border = '1px solid #bee5eb';
        feedback.innerHTML = `<strong>Answers:</strong><br>${answers}`;
    }

    showMatchColumn(hotspot) {
        const leftColumn = hotspot.content.leftColumn || [];
        const rightColumn = hotspot.content.rightColumn || [];
        const controls = hotspot.content.controls || { hasSubmit: true, hasReset: true, hasShowAnswer: false };

        if (leftColumn.length === 0 || rightColumn.length === 0) {
            this.showToast('Match the Column not configured', 'error');
            return;
        }

        const userMatches = {}; // rightId -> leftId

        const renderMatch = () => {
            const leftHTML = leftColumn.map((item, idx) => `
                <div style="padding: 15px; margin: 8px 0; background: #f8f9fa; border: 2px solid #dee2e6; border-radius: 8px;">
                    <strong>${idx + 1}.</strong>
                    ${item.image ? `<img src="${item.image}" style="max-width: 80px; height: auto; margin: 5px 0; display: block; border-radius: 4px;">` : ''}
                    <div>${item.text}</div>
                </div>
            `).join('');

            const rightHTML = rightColumn.map((item, idx) => {
                const matchedLeft = userMatches[item.id];
                const leftItem = leftColumn.find(l => l.id === matchedLeft);
                return `
                    <div style="padding: 15px; margin: 8px 0; background: white; border: 2px solid #007bff; border-radius: 8px;">
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 5px;">
                            <strong>${String.fromCharCode(65 + idx)}.</strong>
                            <select onchange="window.InteractionHandler.selectMatch('${item.id}', this.value)" style="padding: 5px; border-radius: 4px; border: 1px solid #ccc;">
                                <option value="">Select...</option>
                                ${leftColumn.map((l, i) => `<option value="${l.id}" ${matchedLeft === l.id ? 'selected' : ''}>${i + 1}</option>`).join('')}
                            </select>
                        </div>
                        ${item.image ? `<img src="${item.image}" style="max-width: 80px; height: auto; margin: 5px 0; display: block; border-radius: 4px;">` : ''}
                        <div>${item.text}</div>
                        ${leftItem ? `<div style="margin-top: 5px; padding: 5px; background: #e7f3ff; border-radius: 4px; font-size: 12px;">→ ${leftColumn.findIndex(l => l.id === matchedLeft) + 1}</div>` : ''}
                    </div>
                `;
            }).join('');

            const content = `
                <div style="background: white; padding: 30px; border-radius: 12px; max-width: 900px; width: 90%; max-height: 90vh; overflow-y: auto; position: relative;">
                    <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; margin-right: 30px;">
                        <h2 style="margin: 0; color: #333;">Match the Column</h2>
                    </div>
                    
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 20px;">
                        <div>
                            <h3 style="margin-bottom: 10px; color: #666;">Column A</h3>
                            ${leftHTML}
                        </div>
                        <div>
                            <h3 style="margin-bottom: 10px; color: #666;">Column B (Match to A)</h3>
                            ${rightHTML}
                        </div>
                    </div>
                    
                    <div id="match-feedback" style="margin-top: 15px; padding: 10px; border-radius: 6px; display: none;"></div>
                    
                    <div style="margin-top: 20px; display: flex; gap: 10px;">
                        ${controls.hasSubmit ? `<button onclick="window.InteractionHandler.submitMatch()" style="padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 6px; cursor: pointer; flex: 1;">Submit</button>` : ''}
                        ${controls.hasReset ? `<button onclick="window.InteractionHandler.resetMatch()" style="padding: 10px 20px; background: #6c757d; color: white; border: none; border-radius: 6px; cursor: pointer;">Reset</button>` : ''}
                        ${controls.hasShowAnswer ? `<button onclick="window.InteractionHandler.showMatchAnswer()" style="padding: 10px 20px; background: #28a745; color: white; border: none; border-radius: 6px; cursor: pointer;">Show Answer</button>` : ''}
                    </div>
                </div>
            `;

            this.modal.innerHTML = content;
        };

        window.matchState = { leftColumn, rightColumn, userMatches, controls, renderMatch };
        renderMatch();
        this.modal.style.display = 'flex';
    }

    selectMatch(rightId, leftId) {
        if (leftId) {
            window.matchState.userMatches[rightId] = leftId;
        } else {
            delete window.matchState.userMatches[rightId];
        }
        window.matchState.renderMatch();
    }

    submitMatch() {
        const { rightColumn, userMatches } = window.matchState;
        let correct = 0;

        rightColumn.forEach(right => {
            if (userMatches[right.id] === right.matchId) {
                correct++;
            }
        });

        const feedback = document.getElementById('match-feedback');
        feedback.style.display = 'block';
        const isAllCorrect = correct === rightColumn.length;
        feedback.style.background = isAllCorrect ? '#d4edda' : '#fff3cd';
        feedback.style.color = isAllCorrect ? '#155724' : '#856404';
        feedback.style.border = `1px solid ${isAllCorrect ? '#c3e6cb' : '#ffeaa7'}`;
        feedback.innerHTML = `Score: ${correct}/${rightColumn.length} ${isAllCorrect ? '✓ Perfect!' : ''}`;
    }

    resetMatch() {
        window.matchState.userMatches = {};
        const feedback = document.getElementById('match-feedback');
        if (feedback) feedback.style.display = 'none';
        window.matchState.renderMatch();
    }

    showMatchAnswer() {
        const { leftColumn, rightColumn } = window.matchState;
        const answers = rightColumn.map((right, idx) => {
            const leftIdx = leftColumn.findIndex(l => l.id === right.matchId);
            return `${String.fromCharCode(65 + idx)} → ${leftIdx + 1}`;
        }).join('<br>');

        const feedback = document.getElementById('match-feedback');
        feedback.style.display = 'block';
        feedback.style.background = '#d1ecf1';
        feedback.style.color = '#0c5460';
        feedback.style.border = '1px solid #bee5eb';
        feedback.innerHTML = `<strong>Correct Matches:</strong><br>${answers}`;
    }

    showDragDrop(hotspot) {
        const zones = hotspot.content.zones || [];
        const items = hotspot.content.items || [];
        const controls = hotspot.content.controls || { hasSubmit: true, hasReset: true, hasShowAnswer: false };

        if (zones.length === 0 || items.length === 0) {
            this.showToast('Drag & Drop not configured', 'error');
            return;
        }

        // State: itemId -> zoneId (where it is currently dropped)
        // null means it's in the "unassigned" pool
        const itemLocations = {};
        items.forEach(item => itemLocations[item.id] = null);

        const renderDragDrop = () => {
            // Render Zones
            const zonesHTML = zones.map(zone => {
                // Find items currently in this zone
                const zoneItems = items.filter(item => itemLocations[item.id] === zone.id);

                return `
                    <div style="flex: 1; min-width: 200px; background: #f8f9fa; border: 2px dashed #ccc; border-radius: 8px; display: flex; flex-direction: column; overflow: hidden;">
                        <div style="padding: 10px; background: #e9ecef; border-bottom: 1px solid #dee2e6; font-weight: bold; text-align: center; color: #495057;">
                            ${zone.label}
                        </div>
                        ${zone.image ? `
                            <div style="width: 100%; height: 120px; background-color: #f1f3f5; border-bottom: 1px solid #dee2e6; display: flex; justify-content: center; align-items: center; overflow: hidden;">
                                <img src="${zone.image}" style="max-width: 100%; max-height: 100%; object-fit: contain;">
                            </div>
                        ` : ''}
                        <div class="drop-zone" data-zone-id="${zone.id}" 
                             ondrop="window.InteractionHandler.dropItem(event, '${zone.id}')" 
                             ondragover="event.preventDefault()"
                             style="flex: 1; padding: 15px; min-height: 100px; display: flex; flex-wrap: wrap; gap: 8px; align-content: flex-start;">
                             ${zoneItems.map(item => this.renderDraggableItem(item)).join('')}
                        </div>
                    </div>
                `;
            }).join('');

            // Render Unassigned Items Pool
            const unassignedItems = items.filter(item => itemLocations[item.id] === null);
            const poolHTML = unassignedItems.map(item => this.renderDraggableItem(item)).join('');

            const content = `
                <div style="background: white; padding: 30px; border-radius: 12px; max-width: 900px; width: 90%; max-height: 90vh; overflow-y: auto; position: relative; display: flex; flex-direction: column;">
                    <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn">&times;</button>
                    <h2 style="margin: 0 0 20px 0; color: #333;">Drag & Drop</h2>
                    
                    <div style="margin-bottom: 20px;">
                        <h3 style="margin-bottom: 10px; color: #666; font-size: 14px; text-transform: uppercase;">Items</h3>
                        <div class="drop-zone" data-zone-id="pool"
                             ondrop="window.InteractionHandler.dropItem(event, null)" 
                             ondragover="event.preventDefault()"
                             style="padding: 20px; background: #fafdff; border: 1px solid #cce5ff; border-radius: 8px; min-height: 80px; display: flex; flex-wrap: wrap; gap: 10px;">
                             ${poolHTML.length > 0 ? poolHTML : '<span style="color: #999; font-style: italic;">Drag items to zones below...</span>'}
                        </div>
                    </div>

                    <div style="display: flex; gap: 20px; flex-wrap: wrap; margin-bottom: 20px;">
                        ${zonesHTML}
                    </div>

                    <div id="dnd-feedback" style="padding: 15px; border-radius: 6px; display: none; margin-bottom: 20px;"></div>

                    <div style="margin-top: auto; display: flex; gap: 10px;">
                        ${controls.hasSubmit ? `<button onclick="window.InteractionHandler.submitDragDrop()" style="padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 6px; cursor: pointer; flex: 1;">Submit</button>` : ''}
                        ${controls.hasReset ? `<button onclick="window.InteractionHandler.resetDragDrop()" style="padding: 10px 20px; background: #6c757d; color: white; border: none; border-radius: 6px; cursor: pointer;">Reset</button>` : ''}
                        ${controls.hasShowAnswer ? `<button onclick="window.InteractionHandler.showDragDropAnswer()" style="padding: 10px 20px; background: #28a745; color: white; border: none; border-radius: 6px; cursor: pointer;">Show Answer</button>` : ''}
                    </div>
                </div>
            `;

            this.modal.innerHTML = content;
        };

        window.dndState = { zones, items, itemLocations, renderDragDrop };
        renderDragDrop();
        this.modal.style.display = 'flex';
    }

    renderDraggableItem(item) {
        return `
            <div draggable="true" 
                 id="${item.id}"
                 ondragstart="window.InteractionHandler.dragStartItem(event, '${item.id}')"
                 style="padding: 8px 12px; background: white; border: 1px solid #bbb; border-radius: 6px; cursor: grab; display: flex; align-items: center; gap: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); user-select: none;">
                 ${item.type === 'image' && item.value
                ? `<img src="${item.value}" style="width: 30px; height: 30px; object-fit: cover; border-radius: 4px; pointer-events: none;">`
                : ''}
                 <span style="pointer-events: none;">${item.type === 'image' ? 'Image' : item.value}</span>
            </div>
        `;
    }

    dragStartItem(event, itemId) {
        event.dataTransfer.setData('itemId', itemId);
        event.dataTransfer.effectAllowed = 'move';
    }

    dropItem(event, zoneId) {
        event.preventDefault();
        const itemId = event.dataTransfer.getData('itemId');
        if (!itemId) return;

        // Update state
        window.dndState.itemLocations[itemId] = zoneId === 'pool' ? null : zoneId;
        window.dndState.renderDragDrop();
    }

    submitDragDrop() {
        const { items, itemLocations } = window.dndState;
        let correctCount = 0;
        let totalItems = items.length;

        items.forEach(item => {
            const placedZone = itemLocations[item.id];
            // Check if item is in the correct zone
            if (placedZone === item.targetZoneId) {
                correctCount++;
            }
        });

        const feedback = document.getElementById('dnd-feedback');
        feedback.style.display = 'block';
        const isAllCorrect = correctCount === totalItems && totalItems > 0;

        feedback.style.background = isAllCorrect ? '#d4edda' : '#fff3cd';
        feedback.style.color = isAllCorrect ? '#155724' : '#856404';
        feedback.style.border = `1px solid ${isAllCorrect ? '#c3e6cb' : '#ffeaa7'}`;
        feedback.innerHTML = `<strong>Result:</strong> ${correctCount} / ${totalItems} correct items. ${isAllCorrect ? 'Great job!' : 'Keep trying.'}`;
    }

    resetDragDrop() {
        const { items, itemLocations } = window.dndState;
        // Reset all to pool (null) - Mutate existing object to preserve reference for render closure
        items.forEach(item => itemLocations[item.id] = null);

        const feedback = document.getElementById('dnd-feedback');
        if (feedback) feedback.style.display = 'none';

        window.dndState.renderDragDrop();
    }

    showDragDropAnswer() {
        const { items, itemLocations } = window.dndState;
        // Move all items to their correct zones - Mutate existing object
        items.forEach(item => itemLocations[item.id] = item.targetZoneId);

        const feedback = document.getElementById('dnd-feedback');
        feedback.style.display = 'block';
        feedback.style.background = '#d1ecf1';
        feedback.style.color = '#0c5460';
        feedback.style.border = '1px solid #bee5eb';
        feedback.innerHTML = `<strong>Solution Shown:</strong> All items moved to correct zones.`;

        window.dndState.renderDragDrop();
    }

    showFlashcards(hotspot) {
        const cards = hotspot.content.flashcards || [];
        if (cards.length === 0) {
            this.showToast('No cards in this deck', 'error');
            return;
        }

        // Initialize State
        window.flashcardState = {
            cards,
            currentIndex: 0,
            isFlipped: false,
            render: null
        };

        const render = () => {
            const { currentIndex, isFlipped } = window.flashcardState;
            const card = cards[currentIndex];

            const content = `
                <div style="background: transparent; border-radius: 12px; max-width: 900px; width: 90%; height: 80vh; position: relative; display: flex; flex-direction: column; align-items: center; justify-content: center;">
                    <button onclick="window.InteractionHandler.closeModal()" class="modal-close-btn" style="background: white; color: #333; box-shadow: 0 2px 5px rgba(0,0,0,0.2);">&times;</button>
                    
                    <div class="flashcard-container">
                        <div class="flashcard-deck" onclick="window.InteractionHandler.flipFlashcard()">
                            <div class="flashcard ${isFlipped ? 'is-flipped' : ''}" id="current-flashcard">
                                <div class="flashcard-face flashcard-front">
                                    <div class="flashcard-label">Front (Question)</div>
                                    ${card.frontImage ? `<img src="${card.frontImage}" class="flashcard-image" />` : ''}
                                    <div class="flashcard-text">${card.frontText || ''}</div>
                                    <div style="position: absolute; bottom: 10px; font-size: 10px; color: #94a3b8; text-transform: uppercase;">Tap to Flip</div>
                                </div>
                                <div class="flashcard-face flashcard-back">
                                    <div class="flashcard-label" style="color: #10b981;">Back (Answer)</div>
                                    ${card.backImage ? `<img src="${card.backImage}" class="flashcard-image" />` : ''}
                                    <div class="flashcard-text">${card.backText || ''}</div>
                                </div>
                            </div>
                        </div>

                        <div class="flashcard-controls">
                            <button class="flashcard-btn" onclick="window.InteractionHandler.prevFlashcard(event)" ${currentIndex === 0 ? 'disabled' : ''}>←</button>
                            <div class="flashcard-progress">${currentIndex + 1} / ${cards.length}</div>
                            <button class="flashcard-btn" onclick="window.InteractionHandler.nextFlashcard(event)" ${currentIndex === cards.length - 1 ? 'disabled' : ''}>→</button>
                        </div>
                    </div>
                </div>
            `;
            this.openModal(content);
        };

        window.flashcardState.render = render;

        // Define global helpers just for this session
        window.InteractionHandler.flipFlashcard = () => {
            const cardEl = document.getElementById('current-flashcard');
            if (cardEl) {
                cardEl.classList.toggle('is-flipped');
                window.flashcardState.isFlipped = cardEl.classList.contains('is-flipped');
            }
        };

        window.InteractionHandler.nextFlashcard = (e) => {
            if (e) e.stopPropagation();
            if (window.flashcardState.currentIndex < window.flashcardState.cards.length - 1) {
                window.flashcardState.currentIndex++;
                window.flashcardState.isFlipped = false;
                window.flashcardState.render();
            }
        };

        window.InteractionHandler.prevFlashcard = (e) => {
            if (e) e.stopPropagation();
            if (window.flashcardState.currentIndex > 0) {
                window.flashcardState.currentIndex--;
                window.flashcardState.isFlipped = false;
                window.flashcardState.render();
            }
        };

        render();
    }

    openModal(content) {
        this.modal.innerHTML = content;
        this.modal.style.display = 'flex';
    }

    closeModal() {
        this.modal.style.display = 'none';
        this.modal.innerHTML = '';
    }
}

window.InteractionHandler = new InteractionHandler();
