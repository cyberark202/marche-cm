import http from 'k6/http';
import ws from 'k6/ws';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

// Custom metrics
const wsConnectionDelay = new Trend('ws_connection_delay');
const wsConnectionErrors = new Rate('ws_connection_errors');
const apiRequestSuccess = new Rate('api_request_success');

// Load configurations from environment or default values
const BASE_URL = __ENV.LOADTEST_HOST || 'https://cm.digital-get.com';
const WS_BASE_URL = BASE_URL.replace('http', 'ws');
const PWD = __ENV.LOADTEST_PWD || 'ChangeMe123!';
const SELLER_EMAIL = __ENV.LOADTEST_SELLER_EMAIL || 'supplier@marche-cm.local';
const BUYER_EMAIL = __ENV.LOADTEST_BUYER_EMAIL || 'buyer@marche-cm.local';
const BYPASS_TOKEN = __ENV.LOADTEST_BYPASS_TOKEN || '';

// Options for different scaling scenarios (100, 500, 1000, 5000 VUs)
export const options = {
  stages: [
    { duration: '1m', target: 50 },  // Ramp-up to 50 users
    { duration: '3m', target: 50 },  // Stay at 50
    { duration: '2m', target: 100 }, // Ramp-up to 100
    { duration: '5m', target: 100 }, // Stay at 100 (Nominal Phase 5 Target)
    { duration: '1m', target: 0 },   // Ramp-down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests must complete in <500ms
    api_request_success: ['rate>0.99'], // 99%+ of HTTP requests must succeed
    ws_connection_errors: ['rate<0.01'], // <1% WS connection errors
  },
};

// Generates correlation IDs and standard security headers
function getHeaders(token = null) {
  const headers = {
    'Content-Type': 'application/json',
    'X-Correlation-ID': `k6-${Math.random().toString(36).substring(2, 15)}`,
    'X-Device-ID': 'k6-load-agent',
    'X-App-Client': 'k6-loadtest',
    'User-Agent': 'K6-LoadTest/1.0',
  };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  if (BYPASS_TOKEN) {
    headers['X-Loadtest-Bypass-Token'] = BYPASS_TOKEN;
  }
  return headers;
}

// 1x1 px transparent PNG in hex to simulate lightweight product images
const DUMMY_PNG_HEX = '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360606060000000050001a5f645400000000049454e44ae426082';
const DUMMY_PNG_BYTES = new Uint8Array(DUMMY_PNG_HEX.match(/.{1,2}/g).map(val => parseInt(val, 16))).buffer;

export default function () {
  // Determine user role profile by weight:
  // S1 (60% weights): Anonymous Catalogue Browsing
  // S2 (20% weights): Authenticated Seller
  // S3 (10% weights): Authenticated Buyer
  // S4 (5% weights): Wallet User
  // S5 (5% weights): Messaging/WebSocket User
  const rand = Math.random() * 100;

  if (rand < 60) {
    runCatalogueScenario();
  } else if (rand < 80) {
    runSellerScenario();
  } else if (rand < 90) {
    runBuyerScenario();
  } else if (rand < 95) {
    runWalletScenario();
  } else {
    runMessagingWebSocketScenario();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// S1: CATALOGUE NAVIGATION (60%)
// ─────────────────────────────────────────────────────────────────────────────
function runCatalogueScenario() {
  // 1. Get UI Config
  let res = http.get(`${BASE_URL}/api/ui-config/`, { headers: getHeaders() });
  check(res, {
    'UI Config 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(res.status === 200);
  sleep(1);

  // 2. Search Products
  const searchTerms = ['riz', 'huile', 'ciment', 'tissu', 'savon', 'the', ''];
  const term = searchTerms[Math.floor(Math.random() * searchTerms.length)];
  res = http.get(`${BASE_URL}/api/products/?search=${encodeURIComponent(term)}`, { headers: getHeaders() });
  check(res, {
    'Search 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(res.status === 200);
  sleep(2);

  // 3. Filter Products
  const categories = ['Alimentaire', 'Construction', 'Textile', 'Electronique', ''];
  const cat = categories[Math.floor(Math.random() * categories.length)];
  res = http.get(`${BASE_URL}/api/products/?category_name=${encodeURIComponent(cat)}&ordering=-created_at`, { headers: getHeaders() });
  check(res, {
    'Filter 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(res.status === 200);
  sleep(2);

  // 4. Product Detail (probes a small ID spread, tolerates 404)
  const productId = Math.floor(Math.random() * 50) + 1;
  res = http.get(`${BASE_URL}/api/products/${productId}/`, { headers: getHeaders() });
  check(res, {
    'Product Detail 200 or 404': (r) => r.status === 200 || r.status === 404,
  });
  apiRequestSuccess.add(res.status === 200 || res.status === 404);
  sleep(3);
}

// ─────────────────────────────────────────────────────────────────────────────
// S2: SELLER SCENARIO (20%)
// ─────────────────────────────────────────────────────────────────────────────
function runSellerScenario() {
  // 1. Login
  const loginRes = http.post(`${BASE_URL}/api/auth/login/`, JSON.stringify({
    email: SELLER_EMAIL,
    password: PWD,
  }), { headers: getHeaders() });

  const success = check(loginRes, {
    'Seller Login 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(loginRes.status === 200);
  if (!success) {
    sleep(2);
    return;
  }

  const token = loginRes.json('access');
  sleep(1);

  // 2. Browse Own Products
  let res = http.get(`${BASE_URL}/api/products/?mine=true`, { headers: getHeaders(token) });
  check(res, {
    'Own Products 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(res.status === 200);
  sleep(2);

  // 3. Publish Product (Multipart Image)
  const imageFilename = `load-${Math.random().toString(36).substring(7)}.png`;
  const postData = {
    title: `Load k6 ${Math.random().toString(36).substring(7)}`,
    description: 'Load test item (k6)',
    brand: 'k6-load',
    category_name: 'Alimentaire',
    weight_kg: '1.5',
    min_order_qty: '1',
    max_order_qty: '10',
    price_for_min_qty: '5000',
    price_for_max_qty: '4500',
    // We send raw bytes for image
    image: http.file(DUMMY_PNG_BYTES, imageFilename, 'image/png'),
  };

  const uploadHeaders = getHeaders(token);
  delete uploadHeaders['Content-Type']; // Let k6 set the boundary

  res = http.post(`${BASE_URL}/api/products/`, postData, {
    headers: uploadHeaders
  });

  check(res, {
    'Publish Product 201': (r) => r.status === 201,
  });
  apiRequestSuccess.add(res.status === 201);
  sleep(3);
}

// ─────────────────────────────────────────────────────────────────────────────
// S3: BUYER SCENARIO (10%)
// ─────────────────────────────────────────────────────────────────────────────
function runBuyerScenario() {
  // 1. Login
  const loginRes = http.post(`${BASE_URL}/api/auth/login/`, JSON.stringify({
    email: BUYER_EMAIL,
    password: PWD,
  }), { headers: getHeaders() });

  const success = check(loginRes, {
    'Buyer Login 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(loginRes.status === 200);
  if (!success) {
    sleep(2);
    return;
  }

  const token = loginRes.json('access');
  sleep(1);

  // 2. Browse Products
  let res = http.get(`${BASE_URL}/api/products/`, { headers: getHeaders(token) });
  check(res, {
    'Browse Catalog 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(res.status === 200);
  sleep(2);

  // 3. Order validation (checks validation rules without creating actual escrows if unfunded)
  res = http.post(`${BASE_URL}/api/orders/`, JSON.stringify({
    product: Math.floor(Math.random() * 50) + 1,
    quantity: 1,
    preferred_transit_agent: 7,
    transport_mode: 'SEA',
  }), { headers: getHeaders(token) });

  check(res, {
    'Order Gate Check (201 or 400/403/404)': (r) => [200, 201, 400, 403, 404].includes(r.status),
  });
  apiRequestSuccess.add([200, 201, 400, 403, 404].includes(res.status));
  sleep(3);
}

// ─────────────────────────────────────────────────────────────────────────────
// S4: WALLET SCENARIO (5%)
// ─────────────────────────────────────────────────────────────────────────────
function runWalletScenario() {
  // 1. Login
  const loginRes = http.post(`${BASE_URL}/api/auth/login/`, JSON.stringify({
    email: BUYER_EMAIL,
    password: PWD,
  }), { headers: getHeaders() });

  if (loginRes.status !== 200) {
    sleep(2);
    return;
  }

  const token = loginRes.json('access');
  sleep(1);

  // 2. Fetch Wallet Info
  let res = http.get(`${BASE_URL}/api/wallets/`, { headers: getHeaders(token) });
  check(res, {
    'Wallet View 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(res.status === 200);
  sleep(2);

  // 3. Fetch Transactions list
  res = http.get(`${BASE_URL}/api/wallets/transactions/`, { headers: getHeaders(token) });
  check(res, {
    'Wallet Tx History 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(res.status === 200);
  sleep(2);

  // 4. Test Topup Input Validation Gate (safely using invalid parameters)
  res = http.post(`${BASE_URL}/api/wallets/topup/`, JSON.stringify({
    amount: 'abc', // Invalid on purpose to block payout logic
    provider: 'MOBILE_MONEY',
    source_phone: '+237670000000',
    pin: '1234',
  }), { headers: getHeaders(token) });

  check(res, {
    'Topup Input Rejection 400/403': (r) => r.status === 400 || r.status === 403,
  });
  apiRequestSuccess.add(res.status === 400 || res.status === 403);
  sleep(2);
}

// ─────────────────────────────────────────────────────────────────────────────
// S5: MESSAGING & WEBSOCKET REALTIME SCENARIO (5%)
// ─────────────────────────────────────────────────────────────────────────────
function runMessagingWebSocketScenario() {
  // 1. Login
  const loginRes = http.post(`${BASE_URL}/api/auth/login/`, JSON.stringify({
    email: BUYER_EMAIL,
    password: PWD,
  }), { headers: getHeaders() });

  if (loginRes.status !== 200) {
    sleep(2);
    return;
  }

  const token = loginRes.json('access');
  sleep(1);

  // 2. HTTP: Fetch Rooms and Notifications
  let res = http.get(`${BASE_URL}/api/chat/rooms/`, { headers: getHeaders(token) });
  check(res, {
    'Chat Rooms 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(res.status === 200);

  res = http.get(`${BASE_URL}/api/notifications/`, { headers: getHeaders(token) });
  check(res, {
    'Notifications 200': (r) => r.status === 200,
  });
  apiRequestSuccess.add(res.status === 200);
  sleep(2);

  // 3. WS: Open Event WebSocket Stream (Simulate Mobile Client Connection)
  const tokenProto = `bearer, ${token}`; // standard subprotocol header auth
  const wsUrl = `${WS_BASE_URL}/ws/events/`;

  const startTime = Date.now();
  const wsRes = ws.connect(wsUrl, { protocols: [tokenProto] }, function (socket) {
    socket.on('open', () => {
      wsConnectionDelay.add(Date.now() - startTime);
      wsConnectionErrors.add(false);

      // Simulate a client listening for 10 seconds, then disconnecting
      socket.setTimeout(function () {
        socket.close();
      }, 10000);
    });

    socket.on('error', (err) => {
      wsConnectionErrors.add(true);
    });
  });

  check(wsRes, {
    'WS Handshake Success': (r) => r && r.status === 101,
  });
}
