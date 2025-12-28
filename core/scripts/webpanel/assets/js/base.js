$(function () {
    // ===== ELEMENTS =====
    const sidebar = document.getElementById('sidebar');
    const wrapper = document.getElementById('mainWrapper');
    const sidebarToggle = document.getElementById('sidebarToggle');
    const mobileHamburger = document.getElementById('mobileHamburger');
    const sidebarOverlay = document.getElementById('sidebarOverlay');
    const submenus = document.querySelectorAll('.has-submenu > .nav-link');
    const darkModeToggle = document.getElementById('darkModeToggle');
    const darkModeIcon = document.getElementById('darkModeIcon');

    // ===== HELPER: Check if Mobile =====
    function isMobile() {
        return window.innerWidth <= 991;
    }

    // ===== SIDEBAR STATE (Desktop) =====
    if (sidebar && !isMobile()) {
        const isCollapsed = localStorage.getItem('sidebarCollapsed') === 'true';
        if (isCollapsed) {
            sidebar.classList.add('collapsed');
            document.body.classList.add('sidebar-collapsed');
        }
    }

    // ===== DESKTOP SIDEBAR TOGGLE =====
    if (sidebarToggle && sidebar) {
        sidebarToggle.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            
            if (isMobile()) {
                // On mobile, close sidebar
                sidebar.classList.remove('mobile-open');
                if (sidebarOverlay) sidebarOverlay.classList.remove('active');
            } else {
                // Desktop: Collapse/Expand
                sidebar.classList.toggle('collapsed');
                document.body.classList.toggle('sidebar-collapsed');
                localStorage.setItem('sidebarCollapsed', sidebar.classList.contains('collapsed'));
                
                // Close submenus when collapsing
                if (sidebar.classList.contains('collapsed')) {
                    submenus.forEach(function (link) {
                        link.setAttribute('aria-expanded', 'false');
                        const submenu = link.nextElementSibling;
                        if (submenu) submenu.classList.remove('open');
                    });
                }
            }
        });
    }

    // ===== MOBILE HAMBURGER TOGGLE =====
    if (mobileHamburger && sidebar && sidebarOverlay) {
        mobileHamburger.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            
            sidebar.classList.toggle('mobile-open');
            sidebarOverlay.classList.toggle('active');
        });
    }

    // ===== CLOSE SIDEBAR ON OVERLAY CLICK (Mobile) =====
    if (sidebarOverlay && sidebar) {
        sidebarOverlay.addEventListener('click', function () {
            sidebar.classList.remove('mobile-open');
            sidebarOverlay.classList.remove('active');
        });
    }

    // ===== HANDLE WINDOW RESIZE =====
    window.addEventListener('resize', function () {
        if (!isMobile() && sidebar && sidebarOverlay) {
            sidebar.classList.remove('mobile-open');
            sidebarOverlay.classList.remove('active');
        }
    });

    // ===== SUBMENU LOGIC =====
    submenus.forEach(function (link) {
        link.addEventListener('click', function (e) {
            e.preventDefault();

            // Don't open submenu when sidebar is collapsed (desktop)
            if (sidebar && sidebar.classList.contains('collapsed') && !isMobile()) {
                return;
            }

            const submenu = this.nextElementSibling;
            const isExpanded = this.getAttribute('aria-expanded') === 'true';

            this.setAttribute('aria-expanded', !isExpanded);
            if (submenu) submenu.classList.toggle('open');
        });
    });

    // ===== DARK MODE =====
    const isDarkMode = localStorage.getItem('darkMode') !== 'disabled';
    setDarkMode(isDarkMode);

    if (darkModeToggle) {
        darkModeToggle.addEventListener('click', function (e) {
            e.preventDefault();
            const enabled = document.body.classList.contains('dark-mode');
            localStorage.setItem('darkMode', enabled ? 'disabled' : 'enabled');
            setDarkMode(!enabled);
        });
    }

    function setDarkMode(enabled) {
        if (enabled) {
            document.body.classList.add('dark-mode');
            document.documentElement.classList.add('dark-mode');
            if (darkModeIcon) {
                darkModeIcon.classList.remove('fa-moon');
                darkModeIcon.classList.add('fa-sun');
            }
        } else {
            document.body.classList.remove('dark-mode');
            document.documentElement.classList.remove('dark-mode');
            if (darkModeIcon) {
                darkModeIcon.classList.remove('fa-sun');
                darkModeIcon.classList.add('fa-moon');
            }
        }
    }

});
