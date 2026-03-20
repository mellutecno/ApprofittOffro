/**
 * ApprofittOffro — JavaScript utilities
 * Toast notifications, logout, common helpers.
 */

// ============================================================
// Toast notifications
// ============================================================

function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `toast`;

    const icons = {
        success: '✅',
        error: '❌',
        info: 'ℹ️',
        warning: '⚠️',
    };

    const colors = {
        success: 'var(--success)',
        error: 'var(--error)',
        info: 'var(--accent)',
        warning: 'var(--warning)',
    };

    toast.style.borderLeft = `3px solid ${colors[type] || colors.info}`;
    toast.innerHTML = `${icons[type] || icons.info} ${message}`;

    container.appendChild(toast);

    // Auto remove after 4 seconds
    setTimeout(() => {
        if (toast.parentNode) {
            toast.parentNode.removeChild(toast);
        }
    }, 4000);
}

// ============================================================
// Logout
// ============================================================

async function logout() {
    try {
        const res = await fetch('/api/logout', { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            window.location.href = data.redirect || '/';
        }
    } catch {
        window.location.href = '/';
    }
}

// ============================================================
// Format helpers
// ============================================================

function formatDate(isoString) {
    return new Date(isoString).toLocaleString('it-IT', {
        weekday: 'short',
        day: 'numeric',
        month: 'short',
        hour: '2-digit',
        minute: '2-digit',
    });
}

function formatRelativeTime(isoString) {
    const now = new Date();
    const date = new Date(isoString);
    const diff = date - now;
    const hours = Math.floor(diff / (1000 * 60 * 60));
    const days = Math.floor(hours / 24);

    if (days > 1) return `tra ${days} giorni`;
    if (days === 1) return 'domani';
    if (hours > 1) return `tra ${hours} ore`;
    if (hours === 1) return `tra 1 ora`;
    return 'a breve';
}
