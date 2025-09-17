document.addEventListener('DOMContentLoaded', () => {
    const themeToggle = document.getElementById('dark-mode-toggle');
    const themeIcon = document.getElementById('theme-icon');
    let isDarkMode = localStorage.getItem('darkMode') === 'enabled';

    const enableDarkMode = () => {
        document.body.classList.add('dark-mode');
        themeIcon.classList.replace('fa-sun', 'fa-moon');
        localStorage.setItem('darkMode', 'enabled');
        isDarkMode = true;
    };

    const disableDarkMode = () => {
        document.body.classList.remove('dark-mode');
        themeIcon.classList.replace('fa-moon', 'fa-sun');
        localStorage.setItem('darkMode', 'disabled');
        isDarkMode = false;
    };

    if (isDarkMode) {
        enableDarkMode();
    } else {
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        if (prefersDark && localStorage.getItem('darkMode') === null) {
            enableDarkMode();
        }
    }

    themeToggle.addEventListener('click', () => {
        isDarkMode ? disableDarkMode() : enableDarkMode();
    });

    // --- Loading Indicator ---
    const loadingIndicator = document.getElementById('loading-indicator');
    window.addEventListener('load', () => {
        loadingIndicator.style.opacity = '0';
        setTimeout(() => {
            loadingIndicator.style.display = 'none';
        }, 300);
    });

    // --- App Import Tabs ---
    const tabsContainer = document.querySelector('.app-tabs');
    if (tabsContainer) {
        const tabButtons = tabsContainer.querySelectorAll('.app-tab-btn');
        const tabPanes = tabsContainer.querySelectorAll('.app-tab-pane');

        tabButtons.forEach(button => {
            button.addEventListener('click', () => {
                const targetId = button.getAttribute('data-target');
                
                tabButtons.forEach(btn => btn.classList.remove('active'));
                button.classList.add('active');
                
                tabPanes.forEach(pane => {
                    if ('#' + pane.id === targetId) {
                        pane.classList.add('active');
                    } else {
                        pane.classList.remove('active');
                    }
                });
            });
        });
    }
});

function copyToClipboard(text) {
    if (!navigator.clipboard) {
        alert('Clipboard API not available.');
        return;
    }
    navigator.clipboard.writeText(text).then(() => {
        showToast('Copied to clipboard!');
    }).catch(err => {
        console.error('Failed to copy text: ', err);
        alert('Failed to copy.');
    });
}

function showToast(message) {
    let toast = document.querySelector('.toast');
    if (toast) {
        toast.remove();
    }

    toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    
    document.body.appendChild(toast);
    
    const toastStyles = `
        position: fixed;
        bottom: 2rem;
        left: 50%;
        transform: translateX(-50%) translateY(20px);
        background-color: var(--text-light-primary);
        color: var(--bg-light);
        padding: 0.75rem 1.5rem;
        border-radius: 0.75rem;
        font-weight: 500;
        z-index: 1001;
        opacity: 0;
        transition: opacity 0.3s ease, transform 0.3s ease;
        box-shadow: var(--shadow-lg);
    `;
    toast.style.cssText = toastStyles;

    setTimeout(() => {
        toast.style.opacity = '1';
        toast.style.transform = 'translateX(-50%) translateY(0)';
    }, 10);

    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(-50%) translateY(20px)';
        toast.addEventListener('transitionend', () => toast.remove());
    }, 2000);
}