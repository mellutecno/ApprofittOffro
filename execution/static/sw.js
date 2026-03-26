const CACHE_NAME = 'approfittoffro-v143';
const ASSETS = [
    '/',
    '/dashboard',
  '/static/css/styles.css?v=84',
    '/static/js/app.js?v=3',
  '/static/img/approfitto.png?v=2',
  '/static/img/WhatsApp_Image_2026-03-22_at_21.54.07-removebg-preview.png',
    '/static/img/hero.png',
    '/static/img/hero-friends.jpg',
    '/static/img/hero-dinner.jpg',
    '/static/img/hero-brunch.jpg',
    '/static/img/icon-512.png',
    'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css',
    'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'
];

self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => cache.addAll(ASSETS))
    );
    self.skipWaiting();
});

self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(cacheNames =>
            Promise.all(
                cacheNames
                    .filter(cacheName => cacheName !== CACHE_NAME)
                    .map(cacheName => caches.delete(cacheName))
            )
        )
    );
    self.clients.claim();
});

self.addEventListener('fetch', event => {
    event.respondWith(
        caches.match(event.request)
            .then(response => response || fetch(event.request))
    );
});
