// Firebase initialization (must be included before this script)
// Assumes Firebase SDK is already loaded

// Firebase SDK initialization happens later in the script




window.upcomingLaunches = [];
let countdownInterval = null;
const LAUNCHES_CACHE_KEY = 'esz_launches_cache';

// Load launches from cache first (instant), then sync from Firebase
function loadLaunchesFromCache() {
  try {
    const cached = localStorage.getItem(LAUNCHES_CACHE_KEY);
    if (cached) {
      const data = JSON.parse(cached);
      const now = new Date();
      upcomingLaunches = data
        .filter(event => new Date(event.datetimeISO) > now)
        .sort((a, b) => new Date(a.datetimeISO) - new Date(b.datetimeISO))
        .slice(0, 6);
      renderLaunches();
      startCountdowns();
      console.log("Lanzamientos cargados desde cache:", upcomingLaunches.length);

      // Update Homepage Ticker from Cache
      const homepageTicker = document.getElementById('homepage-next-launch-ticker');
      if (homepageTicker && upcomingLaunches.length > 0) {
        const nextMission = upcomingLaunches[0];
        const missionNameEl = document.getElementById('homepage-next-launch-mission');
        const countdownEl = document.getElementById('homepage-next-launch-countdown');
        
        if (missionNameEl) missionNameEl.textContent = nextMission.mission || 'Misión';
        if (countdownEl) {
          countdownEl.setAttribute('data-target', nextMission.datetimeISO);
        }
        homepageTicker.style.display = 'inline-flex';
      }
      return true;
    }
  } catch (e) {
    console.warn('Error loading launches cache:', e);
  }
  return false;
}

// Load launches from Firebase
async function loadLaunches() {
  try {
    const snapshot = await database.ref('events').once('value');
    const data = snapshot.val() || {};
    const events = Object.keys(data).map(key => ({ id: key, ...data[key] }));

    // Filter upcoming launches (future dates only)
    const now = new Date();
    upcomingLaunches = events
      .filter(event => new Date(event.datetimeISO) > now)
      .sort((a, b) => new Date(a.datetimeISO) - new Date(b.datetimeISO))
      .slice(0, 6); // Show max 6 launches

    renderLaunches();
    startCountdowns();
    console.log("Lanzamientos sincronizados desde Firebase:", upcomingLaunches.length);

    // Update Homepage Ticker if present
    const homepageTicker = document.getElementById('homepage-next-launch-ticker');
    if (homepageTicker && upcomingLaunches.length > 0) {
      const nextMission = upcomingLaunches[0];
      const missionNameEl = document.getElementById('homepage-next-launch-mission');
      const countdownEl = document.getElementById('homepage-next-launch-countdown');
      
      if (missionNameEl) missionNameEl.textContent = nextMission.mission || 'Misión';
      if (countdownEl) {
        countdownEl.setAttribute('data-target', nextMission.datetimeISO);
        // Start individual countdown if not already started by startCountdowns
      }
      homepageTicker.style.display = 'inline-flex';
    }

    // Try to save to cache (non-blocking, ignore if quota exceeded)
    try {
      // Only cache lightweight data (no base64 images)
      const lightEvents = events.map(e => ({
        id: e.id,
        vehicle: e.vehicle,
        mission: e.mission,
        site: e.site,
        datetimeISO: e.datetimeISO,
        description: e.description,
        streamUrl: e.streamUrl
      }));
      localStorage.setItem(LAUNCHES_CACHE_KEY, JSON.stringify(lightEvents));
    } catch (cacheError) {
      console.warn('Could not cache launches (quota exceeded):', cacheError);
    }
  } catch (error) {
    console.error('Error loading launches:', error);
    if (upcomingLaunches.length === 0) {
      document.getElementById('launches-list').innerHTML =
        '<div class="no-launches"><div class="no-launches-icon">🚀</div><div>Error al cargar lanzamientos</div></div>';
    }
  }
}

// Render launch cards
function renderLaunches() {
  const container = document.getElementById('launches-list');
  if (!container) return; // Not on a page with launches list

  if (upcomingLaunches.length === 0) {
    container.innerHTML = `
              <div class="no-launches">
                <div class="no-launches-icon">🚀</div>
                <div class="no-launches-text">No hay lanzamientos programados</div>
              </div>`;
    return;
  }

  container.innerHTML = upcomingLaunches.map((launch) => {
    const launchDate = new Date(launch.datetimeISO);
    const dateStr = launchDate.toLocaleString('es-ES', {
      day: 'numeric',
      month: 'short',
      hour: '2-digit',
      minute: '2-digit'
    });

    return `
            <div class="launch-card" data-launch-id="${launch.id}" onclick="showEventModal('${launch.id}')">
              <div class="launch-card-inner">
                <div class="launch-info-section">
                  <div class="launch-vehicle">${launch.vehicle || 'Vehículo'}</div>
                  ${launch.mission ? `<div class="launch-mission">${launch.mission}</div>` : ''}
                  <div class="launch-site">${launch.site || ''}</div>
                </div>
                <div class="launch-countdown-section">
                  <div class="launch-countdown">
                    <div class="launch-t">T-</div>
                    <div class="launch-time" data-target="${launch.datetimeISO}">--:--:--</div>
                  </div>
                  <div class="launch-date">${dateStr}</div>
                </div>
              </div>
            </div>
          `;
  }).join('');
}

// Start countdown timers
function startCountdowns() {
  if (countdownInterval) {
    clearInterval(countdownInterval);
  }

  function update() {
    const now = new Date();
    document.querySelectorAll('.launch-time').forEach(timeEl => {
      const targetStr = timeEl.getAttribute('data-target');
      if (!targetStr) return;

      const target = new Date(targetStr);
      const diff = target - now;

      if (diff <= 0) {
        timeEl.textContent = '¡LANZADO!';
        timeEl.style.color = '#51cf66';
        return;
      }

      // Calculate time remaining
      const totalSeconds = Math.floor(diff / 1000);
      const days = Math.floor(totalSeconds / 86400);
      const hours = Math.floor((totalSeconds % 86400) / 3600);
      const minutes = Math.floor((totalSeconds % 3600) / 60);
      const seconds = totalSeconds % 60;

      // Format: "Xd HH:MM:SS" or "HH:MM:SS" if < 1 day
      if (days > 0) {
        timeEl.textContent = `${days}d ${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
      } else {
        timeEl.textContent = `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
      }
    });
  }

  update();
  countdownInterval = setInterval(update, 1000);
}

// Initialize on page load - cache first, then sync
function initLaunches() {
  // Try to load from cache first (instant)
  loadLaunchesFromCache();
  // Then sync from Firebase in background
  loadLaunches();
}

// initLaunches will be called after database is initialized (below)

// Event Modal Functions (global scope for onclick)
let modalCountdownInterval = null;
let currentLaunchData = null;

function showEventModal(launchId) {
  // Find the launch data
  const launch = upcomingLaunches.find(l => l.id === launchId);
  if (!launch) {
    console.error('Launch not found:', launchId);
    return;
  }

  currentLaunchData = launch;

  // Update modal title
  document.getElementById('modal-title').textContent = launch.vehicle || 'Lanzamiento';

  // Update goal pill
  const launchDate = new Date(launch.datetimeISO);
  const dateStr = launchDate.toLocaleString('es-ES', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZoneName: 'short'
  });
  document.getElementById('modal-goal').innerHTML = `
          <span class="goal-dot"></span>
          Ventana objetivo: ${dateStr}
        `;

  // Populate modal info
  let infoHTML = '';
  if (launch.vehicle) {
    infoHTML += `<div class="modal-info-row"><div class="modal-info-label">Vehículo</div><div class="modal-info-value">${launch.vehicle}</div></div>`;
  }
  if (launch.mission) {
    infoHTML += `<div class="modal-info-row"><div class="modal-info-label">Misión</div><div class="modal-info-value">${launch.mission}</div></div>`;
  }
  if (launch.site) {
    infoHTML += `<div class="modal-info-row"><div class="modal-info-label">Lugar</div><div class="modal-info-value">${launch.site}</div></div>`;
  }
  if (launch.vehicleFull) {
    infoHTML += `<div class="modal-info-row"><div class="modal-info-label">Vehículo Completo</div><div class="modal-info-value">${launch.vehicleFull}</div></div>`;
  }
  if (launch.payload) {
    infoHTML += `<div class="modal-info-row"><div class="modal-info-label">Carga útil</div><div class="modal-info-value">${launch.payload}</div></div>`;
  }
  if (launch.orbit) {
    infoHTML += `<div class="modal-info-row"><div class="modal-info-label">Órbita objetivo</div><div class="modal-info-value">${launch.orbit}</div></div>`;
  }
  document.getElementById('modal-info').innerHTML = infoHTML;

  // Description
  document.getElementById('modal-desc').textContent = launch.description || 'No hay descripción disponible.';

  // Stream link
  const watchBtn = document.getElementById('modal-watch');
  if (launch.streamUrl) {
    watchBtn.href = launch.streamUrl;
    watchBtn.style.display = 'inline-flex';
  } else {
    watchBtn.style.display = 'none';
  }

  // Start modal countdown
  const countdownEl = document.getElementById('modal-countdown');
  countdownEl.setAttribute('data-countdown-dt', launch.datetimeISO);

  function updateModalCountdown() {
    const target = new Date(launch.datetimeISO);
    const now = new Date();
    const diff = target - now;

    if (diff <= 0) {
      countdownEl.textContent = '¡LANZADO!';
      countdownEl.style.color = '#51cf66';
      if (modalCountdownInterval) {
        clearInterval(modalCountdownInterval);
      }
      return;
    }

    const totalSeconds = Math.floor(diff / 1000);
    const days = Math.floor(totalSeconds / 86400);
    const hours = Math.floor((totalSeconds % 86400) / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    let timeStr = '';
    if (days > 0) {
      timeStr = `T- ${days}d ${String(hours).padStart(2, '0')}h ${String(minutes).padStart(2, '0')}m ${String(seconds).padStart(2, '0')}s`;
    } else if (hours > 0) {
      timeStr = `T- ${String(hours).padStart(2, '0')}h ${String(minutes).padStart(2, '0')}m ${String(seconds).padStart(2, '0')}s`;
    } else {
      timeStr = `T- ${String(minutes).padStart(2, '0')}m ${String(seconds).padStart(2, '0')}s`;
    }
    countdownEl.textContent = timeStr;
  }

  updateModalCountdown();
  if (modalCountdownInterval) {
    clearInterval(modalCountdownInterval);
  }
  modalCountdownInterval = setInterval(updateModalCountdown, 1000);

  // Show modal
  document.getElementById('event-modal-overlay').classList.add('show');
}

function closeEventModal() {
  document.getElementById('event-modal-overlay').classList.remove('show');
  if (modalCountdownInterval) {
    clearInterval(modalCountdownInterval);
    modalCountdownInterval = null;
  }
  currentLaunchData = null;
}

// Close modal on escape key
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && document.getElementById('event-modal-overlay').classList.contains('show')) {
    closeEventModal();
  }
});

// Close modal when clicking outside
document.getElementById('event-modal-overlay')?.addEventListener('click', (e) => {
  if (e.target.id === 'event-modal-overlay') {
    closeEventModal();
  }
});
// ===== CONFIGURACIÓN DE FIREBASE =====
const firebaseConfig = {
  apiKey: "AIzaSyDKvGLsd1jKfsSlzgTjBas-8WvbFqVlixU",
  authDomain: "eszunspace-bc900.firebaseapp.com",
  databaseURL: "https://eszunspace-bc900-default-rtdb.europe-west1.firebasedatabase.app",
  projectId: "eszunspace-bc900",
  storageBucket: "eszunspace-bc900.firebasestorage.app",
  messagingSenderId: "1056516834829",
  appId: "1:1056516834829:web:5c8fd5051c8c2daf24f744",
  measurementId: "G-ZDM5GF0WBW"
};

if (!firebase.apps.length) {
  console.log("Inicializando Firebase con API Key:", firebaseConfig.apiKey);
  firebase.initializeApp(firebaseConfig);
}
const database = firebase.database();

// Now that database is ready, initialize launches
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initLaunches);
} else {
  initLaunches();
}

// ===== SHA-256 HASHING HELPER =====
async function hashPassword(message) {
  const msgBuffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  return hashHex;
}

// ===== AUTH SYSTEM (RTDB) =====
let currentUser = null;
let allUsers = {};
const SESSION_KEY = 'esz_user';
const USERS_CACHE_KEY = 'esz_users_cache';

// Load users from localStorage first (instant), then sync from Firebase
function loadUsersFromCache() {
  try {
    const cached = localStorage.getItem(USERS_CACHE_KEY);
    if (cached) {
      allUsers = JSON.parse(cached);
      console.log("Usuarios cargados desde cache:", Object.keys(allUsers).length);
      return true;
    }
  } catch (e) {
    console.warn('Error loading users cache:', e);
  }
  return false;
}

async function loadUsers() {
  try {
    const snapshot = await database.ref('users').once('value');
    allUsers = snapshot.val() || {};
    // Save to cache for next time
    localStorage.setItem(USERS_CACHE_KEY, JSON.stringify(allUsers));
    console.log("Usuarios sincronizados desde Firebase:", Object.keys(allUsers).length);
  } catch (error) {
    console.error('Error al cargar usuarios:', error);
    // Keep cached users if Firebase fails
  }
}

// Refactored Auth Check (Official Firebase Auth)
firebase.auth().onAuthStateChanged((user) => {
  if (user) {
    // User is signed in via Google
    currentUser = user.displayName || user.email.split('@')[0];

    // Sync user to Realtime Database
    saveGoogleUser(user, currentUser);

    const avatarChar = currentUser.charAt(0).toUpperCase();

    updateUIForLogin(currentUser, avatarChar, user.photoURL);
    updatePresence(true);
  } else {
    // Not signed in via Google, check legacy session
    const saved = localStorage.getItem(SESSION_KEY);
    if (saved) {
      currentUser = saved;
      updateUIForLogin(currentUser, currentUser.charAt(0).toUpperCase());
    } else {
      updateUIForLogout();
    }
  }
});

function updateUIForLogin(username, avatarChar, photoURL = null) {
  document.getElementById('login-btn').style.display = 'none';
  document.getElementById('user-display').style.display = 'flex';
  document.getElementById('user-name').textContent = username;

  const avatarEl = document.getElementById('user-avatar');
  if (photoURL) {
    avatarEl.innerHTML = `<img src="${photoURL}" style="width:100%;height:100%;border-radius:50%;object-fit:cover;">`;
    avatarEl.style.padding = '0';
  } else {
    avatarEl.textContent = avatarChar;
    avatarEl.style.padding = '';
  }
}

function updateUIForLogout() {
  document.getElementById('login-btn').style.display = 'inline-flex';
  document.getElementById('user-display').style.display = 'none';
}

// Keep multiple tabs/pages in sync
window.addEventListener('storage', (e) => {
  if (e.key === SESSION_KEY) {
    hydrateSessionFromStorage();
  }
});

async function saveUser(username, password) {
  try {
    // Double check against DB to be sure
    const snapshot = await database.ref('users/' + username).once('value');
    if (snapshot.exists()) {
      return false; // Already exists
    }

    // Save password as plain text
    await database.ref('users/' + username).set(password);
    allUsers[username] = password;
    return true;
  } catch (error) {
    console.error('Error al guardar usuario:', error);
    return false;
  }
}

// Helper to save Google users to DB
async function saveGoogleUser(user, username) {
  try {
    const userRef = database.ref('users/' + username);
    const snapshot = await userRef.once('value');

    if (!snapshot.exists()) {
      // Create new user entry
      await userRef.set({
        provider: 'google',
        email: user.email,
        uid: user.uid,
        photoURL: user.photoURL,
        displayName: user.displayName,
        createdAt: Date.now(),
        lastLogin: Date.now()
      });
      console.log('Usuario de Google guardado en DB:', username);
    } else {
      // Update last login
      await userRef.update({
        lastLogin: Date.now(),
        // Update photo/email if they changed
        photoURL: user.photoURL,
        email: user.email
      });
    }

    // Add to local cache for consistency
    allUsers[username] = { provider: 'google', email: user.email };
  } catch (e) {
    console.error('Error syncing Google user to DB:', e);
  }
}

// ===== UI FUNCTIONS =====
function showLoginModal() {
  showLoginForm();
  var modal = document.getElementById('auth-modal-overlay');
  if (!modal) {
    console.error('Auth modal not found');
    return;
  }
  modal.classList.add('show');
  document.body.style.overflow = 'hidden';
}

function closeAuthModal() {
  var modal = document.getElementById('auth-modal-overlay');
  if (!modal) return;
  modal.classList.remove('show');
  document.body.style.overflow = '';

  var loginError = document.getElementById('login-error');
  var registerError = document.getElementById('register-error');
  var registerSuccess = document.getElementById('register-success');

  if (loginError) loginError.classList.remove('show');
  if (registerError) registerError.classList.remove('show');
  if (registerSuccess) registerSuccess.classList.remove('show');
}

function showLoginForm(e) {
  if (e) e.preventDefault();
  document.getElementById('auth-modal-title').textContent = 'Iniciar sesión';
  document.getElementById('login-form').style.display = 'flex';
  document.getElementById('register-form').style.display = 'none';
  document.getElementById('login-username').value = '';
  document.getElementById('login-password').value = '';
  document.getElementById('login-error').classList.remove('show');
}

function showRegisterForm(e) {
  if (e) e.preventDefault();
  document.getElementById('auth-modal-title').textContent = 'Crear cuenta';
  document.getElementById('login-form').style.display = 'none';
  document.getElementById('register-form').style.display = 'flex';
  document.getElementById('register-username').value = '';
  document.getElementById('register-password').value = '';
  document.getElementById('register-error').classList.remove('show');
  document.getElementById('register-success').classList.remove('show');
}

// ===== HANDLERS =====

async function loginWithGoogle() {
  const provider = new firebase.auth.GoogleAuthProvider();
  try {
    await firebase.auth().signInWithPopup(provider);
    closeAuthModal();
  } catch (error) {
    console.error('Error al iniciar sesión con Google:', error);
    alert('Error al conectar con Google: ' + error.message);
  }
}

async function handleLogin(e) {
  e.preventDefault();
  const username = document.getElementById('login-username').value.trim();
  const password = document.getElementById('login-password').value;
  const errEl = document.getElementById('login-error');

  if (!allUsers[username]) {
    errEl.textContent = 'Usuario no encontrado';
    errEl.classList.add('show');
    return;
  }

  // Legacy plain-text password check (as previously implemented)
  if (allUsers[username] === password) {
    currentUser = username;
    localStorage.setItem(SESSION_KEY, currentUser);
    updateUIForLogin(currentUser, currentUser.charAt(0).toUpperCase());
    updatePresence(true);
    closeAuthModal();
  } else {
    errEl.textContent = 'Contraseña incorrecta';
    errEl.classList.add('show');
  }
}

async function handleRegister(e) {
  e.preventDefault();
  const username = document.getElementById('register-username').value.trim();
  const password = document.getElementById('register-password').value;
  const errEl = document.getElementById('register-error');
  const successEl = document.getElementById('register-success');

  errEl.classList.remove('show');
  successEl.classList.remove('show');

  if (!username) {
    errEl.textContent = 'El nombre de usuario es obligatorio';
    errEl.classList.add('show');
    return;
  }

  if (password.length < 6) {
    errEl.textContent = 'La contraseña debe tener al menos 6 caracteres';
    errEl.classList.add('show');
    return;
  }

  const saved = await saveUser(username, password);
  if (!saved) {
    errEl.textContent = 'Este nombre de usuario ya está en uso';
    errEl.classList.add('show');
    return;
  }

  // Success — auto-login
  successEl.classList.add('show');
  currentUser = username;
  localStorage.setItem(SESSION_KEY, currentUser);
  updateUIForLogin(currentUser, currentUser.charAt(0).toUpperCase());
  updatePresence(true);

  setTimeout(() => {
    closeAuthModal();
  }, 1500);
}

// Refactored Logout
async function logout() {
  try {
    await firebase.auth().signOut();
    updatePresence(false);
    currentUser = null;
    localStorage.removeItem(SESSION_KEY);
    updateUIForLogout();
  } catch (error) {
    console.error('Error al cerrar sesión:', error);
  }
}

function getFirebaseErrorMessage(code) {
  return code;
}

// ===== PROFILE FUNCTIONS (Re-implemented for Custom Auth) =====
function showProfileModal() {
  if (!currentUser) return;

  var profileUsername = document.getElementById('profile-username');
  var profileAvatar = document.getElementById('profile-avatar');

  if (profileUsername) profileUsername.textContent = currentUser;
  if (profileAvatar) profileAvatar.textContent = currentUser.charAt(0).toUpperCase();

  var newUsernameInput = document.getElementById('new-username');
  var currentPasswordInput = document.getElementById('current-password');
  var newPasswordInput = document.getElementById('new-password');

  if (newUsernameInput) newUsernameInput.value = '';
  if (currentPasswordInput) currentPasswordInput.value = '';
  if (newPasswordInput) newPasswordInput.value = '';

  // Clear messages
  var usernameError = document.getElementById('username-change-error');
  var usernameSuccess = document.getElementById('username-change-success');
  var passwordError = document.getElementById('password-change-error');
  var passwordSuccess = document.getElementById('password-change-success');

  if (usernameError) usernameError.classList.remove('show');
  if (usernameSuccess) usernameSuccess.classList.remove('show');
  if (passwordError) passwordError.classList.remove('show');
  if (passwordSuccess) passwordSuccess.classList.remove('show');

  var modal = document.getElementById('profile-modal-overlay');
  if (modal) {
    modal.classList.add('show');
    document.body.style.overflow = 'hidden';
  }
}

function closeProfileModal() {
  var modal = document.getElementById('profile-modal-overlay');
  if (modal) {
    modal.classList.remove('show');
    document.body.style.overflow = '';
  }
}

async function handleChangeUsername(e) {
  e.preventDefault();
  const newUsername = document.getElementById('new-username').value.trim();

  const err = document.getElementById('username-change-error');
  err.classList.remove('show');

  if (newUsername === currentUser) {
    err.textContent = 'El nombre es el mismo';
    err.classList.add('show');
    return;
  }

  if (allUsers[newUsername]) {
    err.textContent = 'Este usuario ya está en uso';
    err.classList.add('show');
    return;
  }

  try {
    const passwordHash = allUsers[currentUser];

    // Remove old
    await database.ref('users/' + currentUser).remove();
    delete allUsers[currentUser];

    // Add new
    await database.ref('users/' + newUsername).set(passwordHash);
    allUsers[newUsername] = passwordHash;

    // Update session
    currentUser = newUsername;
    localStorage.setItem(SESSION_KEY, currentUser);

    document.getElementById('username-change-success').classList.add('show');
    document.getElementById('profile-username').textContent = newUsername;
    document.getElementById('user-name').textContent = newUsername;

    setTimeout(() => {
      closeProfileModal();
    }, 1500);
  } catch (error) {
    console.error('Error al cambiar nombre:', error);
    err.textContent = 'Error al procesar la solicitud';
    err.classList.add('show');
  }
}

async function handleChangePassword(e) {
  e.preventDefault();
  const newPassword = document.getElementById('new-password').value;
  const hashedNew = await hashPassword(newPassword);

  try {
    await database.ref('users/' + currentUser).set(hashedNew);
    allUsers[currentUser] = hashedNew;

    document.getElementById('password-change-success').classList.add('show');
    document.getElementById('new-password').value = '';
    setTimeout(() => {
      document.getElementById('password-change-success').classList.remove('show');
    }, 3000);
  } catch (error) {
    console.error('Error al cambiar contraseña:', error);
    document.getElementById('password-change-error').textContent = 'Error al cambiar contraseña';
    document.getElementById('password-change-error').classList.add('show');
  }
}

async function deleteAccount() {
  if (!confirm('¿Estás seguro?')) return;

  try {
    await database.ref('users/' + currentUser).remove();
    delete allUsers[currentUser];
    logout();
    closeProfileModal();
    alert('Cuenta eliminada');
  } catch (error) {
    alert('Error al eliminar');
  }
}

const ADMIN_USER = 'Esstor';
const ADMIN_EMAIL = 'hectorruiz1515@gmail.com';
const ADMIN_UID = 'l79MdkW1sOalZGjZcfr28kvrOA23'; // UID from screenshot (lowercase L or capital I)
const ADMIN_UID_ALT = 'I79MdkW1sOalZGjZcfr28kvrOA23'; // Alternative interpretation of the font

function isAdmin() {
  if (!currentUser) return false;

  // 1. Firebase Auth object check (Most secure, requires active session)
  const fbUser = firebase.auth().currentUser;
  if (fbUser) {
    if (fbUser.email && fbUser.email.toLowerCase() === ADMIN_EMAIL.toLowerCase()) return true;
    if (fbUser.uid === ADMIN_UID || fbUser.uid === ADMIN_UID_ALT) return true;
  }

  // 2. Database cache check (For when the page is reloading but localStorage session exists)
  if (allUsers && allUsers[currentUser]) {
    const userObj = allUsers[currentUser];
    // Solamente confiar si el registro en DB tiene el email o UID de admin original
    if (typeof userObj === 'object') {
      if (userObj.email && userObj.email.toLowerCase() === ADMIN_EMAIL.toLowerCase()) return true;
      if (userObj.uid === ADMIN_UID || userObj.uid === ADMIN_UID_ALT) return true;
    }
  }

  return false;
}

let updatesData = [];

// ===== CONTACT CHAT SYSTEM =====
let currentChatPartner = null;
let chatUnsubscribe = null;
let pendingAttachment = null; // Stores {base64, fileName, fileType, isImage}
let typingTimeout = null;
let presenceUnsubscribe = null;
let typingUnsubscribe = null;
let lastMessageCount = 0; // Track message count to detect new messages

// Chat notification sound system
const CHAT_MUTE_KEY = 'eszunspace_chat_muted';
let isChatMuted = localStorage.getItem(CHAT_MUTE_KEY) === 'true';

function initChatMuteState() {
  const btn = document.getElementById('chat-mute-btn');
  const iconOn = document.getElementById('mute-icon-on');
  const iconOff = document.getElementById('mute-icon-off');

  if (isChatMuted) {
    btn.classList.add('muted');
    btn.title = 'Activar notificaciones';
    iconOn.style.display = 'block';
    iconOff.style.display = 'none';
  } else {
    btn.classList.remove('muted');
    btn.title = 'Silenciar notificaciones';
    iconOn.style.display = 'none';
    iconOff.style.display = 'block';
  }
}

function toggleChatMute() {
  isChatMuted = !isChatMuted;
  localStorage.setItem(CHAT_MUTE_KEY, isChatMuted);
  initChatMuteState();
}

function playNotificationSound() {
  if (isChatMuted) return;

  // Create a simple beep using Web Audio API
  try {
    const audioContext = new (window.AudioContext || window.webkitAudioContext)();
    const oscillator = audioContext.createOscillator();
    const gainNode = audioContext.createGain();

    oscillator.connect(gainNode);
    gainNode.connect(audioContext.destination);

    oscillator.frequency.value = 800;
    oscillator.type = 'sine';
    gainNode.gain.setValueAtTime(0.3, audioContext.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.3);

    oscillator.start(audioContext.currentTime);
    oscillator.stop(audioContext.currentTime + 0.3);
  } catch (e) {
    console.log('Could not play notification sound:', e);
  }
}

// ===== PRESENCE SYSTEM =====
function updatePresence(online) {
  if (!currentUser) return;
  const presenceRef = database.ref(`presence/${currentUser}`);
  presenceRef.set({
    online: online,
    lastSeen: Date.now()
  });
  // Set offline on disconnect
  if (online) {
    presenceRef.onDisconnect().set({
      online: false,
      lastSeen: Date.now()
    });
  }
}

function listenToPartnerPresence(partnerUsername) {
  // Unsubscribe from previous listener
  if (presenceUnsubscribe) {
    presenceUnsubscribe();
  }

  const presenceRef = database.ref(`presence/${partnerUsername}`);
  const listener = presenceRef.on('value', (snapshot) => {
    const data = snapshot.val();
    const statusDot = document.getElementById('chat-partner-status-dot');
    const statusText = document.getElementById('chat-partner-status-text');

    if (data && data.online) {
      statusDot.className = 'status-dot online';
      statusDot.title = 'Conectado';
      if (partnerUsername === ADMIN_USER) {
        statusText.textContent = 'En línea';
      } else {
        statusText.textContent = 'En línea';
      }
    } else {
      statusDot.className = 'status-dot offline';
      statusDot.title = 'Desconectado';
      if (data && data.lastSeen) {
        const lastSeen = new Date(data.lastSeen);
        const now = new Date();
        const diffMins = Math.floor((now - lastSeen) / 60000);
        if (diffMins < 60) {
          statusText.textContent = `Últ. vez hace ${diffMins}min`;
        } else {
          statusText.textContent = 'Desconectado';
        }
      } else {
        statusText.textContent = partnerUsername === ADMIN_USER ? 'Admin de EsZunSpace' : 'Usuario';
      }
    }
  });

  presenceUnsubscribe = () => presenceRef.off('value', listener);
}

// ===== TYPING INDICATOR =====
function setTypingStatus(isTyping) {
  if (!currentUser || !currentChatPartner) return;
  const chatPath = isAdmin() ? currentChatPartner : currentUser;
  database.ref(`typing/${chatPath}/${currentUser}`).set(isTyping ? true : null);
}

function listenToTypingStatus() {
  if (typingUnsubscribe) {
    typingUnsubscribe();
  }

  if (!currentChatPartner) return;

  const chatPath = isAdmin() ? currentChatPartner : currentUser;
  const partnerUsername = isAdmin() ? currentChatPartner : ADMIN_USER;
  const typingRef = database.ref(`typing/${chatPath}/${partnerUsername}`);

  const listener = typingRef.on('value', (snapshot) => {
    const isTyping = snapshot.val();
    const indicator = document.getElementById('typing-indicator');
    if (isTyping) {
      indicator.style.display = 'flex';
    } else {
      indicator.style.display = 'none';
    }
  });

  typingUnsubscribe = () => typingRef.off('value', listener);
}

function handleTyping() {
  setTypingStatus(true);

  // Clear previous timeout
  if (typingTimeout) {
    clearTimeout(typingTimeout);
  }

  // Set typing to false after 2 seconds of no typing
  typingTimeout = setTimeout(() => {
    setTypingStatus(false);
  }, 2000);
}

// Clean up typing status when closing chat
function cleanupTyping() {
  setTypingStatus(false);
  if (typingTimeout) {
    clearTimeout(typingTimeout);
    typingTimeout = null;
  }
  if (typingUnsubscribe) {
    typingUnsubscribe();
    typingUnsubscribe = null;
  }
  if (presenceUnsubscribe) {
    presenceUnsubscribe();
    presenceUnsubscribe = null;
  }
}


// File attachment functions
function handleFileSelect(e) {
  const file = e.target.files[0];
  if (!file) return;

  // Validate file size (2MB max)
  const maxSize = 2 * 1024 * 1024; // 2MB
  if (file.size > maxSize) {
    alert('El archivo es demasiado grande. El tamaño máximo es 2MB.');
    e.target.value = '';
    return;
  }

  const reader = new FileReader();
  reader.onloadend = function () {
    const base64 = reader.result;
    const isImage = file.type.startsWith('image/');

    pendingAttachment = {
      base64: base64,
      fileName: file.name,
      fileType: file.type,
      isImage: isImage
    };

    // Show preview
    const previewContainer = document.getElementById('chat-attachment-preview');
    const previewImg = document.getElementById('attachment-preview-img');
    const previewFile = document.getElementById('attachment-preview-file');
    const fileName = document.getElementById('attachment-file-name');

    if (isImage) {
      previewImg.src = base64;
      previewImg.style.display = 'block';
      previewFile.style.display = 'none';
    } else {
      previewImg.style.display = 'none';
      previewFile.style.display = 'flex';
      fileName.textContent = file.name;
    }

    previewContainer.style.display = 'flex';
  };
  reader.readAsDataURL(file);
}

function clearAttachment() {
  pendingAttachment = null;
  document.getElementById('chat-file-input').value = '';
  document.getElementById('chat-attachment-preview').style.display = 'none';
  document.getElementById('attachment-preview-img').src = '';
  document.getElementById('attachment-preview-img').style.display = 'none';
  document.getElementById('attachment-preview-file').style.display = 'none';
}

function renderAttachment(attachment) {
  if (!attachment) return '';

  if (attachment.isImage) {
    return `
          <div class="chat-message-attachment">
            <img src="${attachment.base64}" alt="${attachment.fileName}" onclick="openLightbox('${attachment.base64}', '${attachment.fileName}')">
          </div>
        `;
  } else {
    return `
          <div class="chat-message-attachment">
            <a href="${attachment.base64}" download="${attachment.fileName}" class="chat-message-file">
              <span class="file-icon">📄</span>
              <span>${attachment.fileName}</span>
              <span class="download-icon">⬇️</span>
            </a>
          </div>
        `;
  }
}

function openLightbox(imageSrc, fileName) {
  const lightbox = document.getElementById('image-lightbox');
  const img = document.getElementById('lightbox-image');
  const downloadBtn = document.getElementById('lightbox-download');

  img.src = imageSrc;
  downloadBtn.href = imageSrc;
  downloadBtn.download = fileName;

  lightbox.classList.add('show');
  document.body.style.overflow = 'hidden';
}

function closeLightbox() {
  document.getElementById('image-lightbox').classList.remove('show');
  document.body.style.overflow = '';
}

// Close lightbox on Escape key
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && document.getElementById('image-lightbox').classList.contains('show')) {
    closeLightbox();
  }
});

function showContactModal() {
  const modal = document.getElementById('contact-modal');
  modal.classList.add('show');
  document.body.style.overflow = 'hidden';

  // Initialize mute button state and reset message counter
  initChatMuteState();
  lastMessageCount = 0;

  // Verificar si hay usuario logueado
  if (currentUser) {
    document.getElementById('contact-login-required').style.display = 'none';
    document.getElementById('contact-chat').style.display = 'flex';

    // Si es admin, mostrar lista de conversaciones
    if (isAdmin()) {
      document.getElementById('chat-conversations').style.display = 'block';
      document.getElementById('chat-partner-info').style.display = 'none';
      document.getElementById('chat-messages-area').style.display = 'none';
      document.getElementById('contact-chat').classList.add('conversations-only');
      currentChatPartner = null;
      loadConversations();
    } else {
      // Usuario normal: chat directo con admin
      document.getElementById('chat-conversations').style.display = 'none';
      document.getElementById('chat-partner-info').style.display = 'flex';
      document.getElementById('chat-messages-area').style.display = 'flex';
      document.getElementById('contact-chat').classList.remove('conversations-only');
      currentChatPartner = ADMIN_USER;
      loadChatMessages(currentUser, ADMIN_USER);

      // Start presence and typing listeners
      listenToPartnerPresence(ADMIN_USER);
      listenToTypingStatus();

      // Add typing detection to input
      const chatInput = document.getElementById('chat-input');
      chatInput.removeEventListener('input', handleTyping);
      chatInput.addEventListener('input', handleTyping);
    }
  } else {
    document.getElementById('contact-login-required').style.display = 'block';
    document.getElementById('contact-chat').style.display = 'none';
  }
}

function closeContactModal() {
  document.getElementById('contact-modal').classList.remove('show');
  document.body.style.overflow = '';
  if (chatUnsubscribe) {
    chatUnsubscribe();
    chatUnsubscribe = null;
  }
  cleanupTyping();
}

// ===== CACHE PARA CONVERSACIONES =====
const CONVERSATIONS_CACHE_KEY = 'esz_conversations_cache';

// Renderizar lista de conversaciones desde datos procesados
function renderConversationsList(conversationsData) {
  const list = document.getElementById('conversations-list');

  if (!conversationsData || conversationsData.length === 0) {
    list.innerHTML = '<div style="padding:20px; text-align:center; color:rgba(255,255,255,0.5);">No hay conversaciones aún.</div>';
    return;
  }

  list.innerHTML = '';
  for (const conv of conversationsData) {
    const timeStr = conv.lastTime
      ? new Date(conv.lastTime).toLocaleDateString('es-ES', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
      : '';

    const item = document.createElement('div');
    item.className = 'conversation-item' + (currentChatPartner === conv.username ? ' active' : '');
    item.innerHTML = `
          <span class="conversation-avatar">${conv.username.charAt(0).toUpperCase()}</span>
          <div class="conversation-info">
            <div class="conversation-name">${conv.username}</div>
            <div class="conversation-preview">${conv.lastMessage.substring(0, 25)}${conv.lastMessage.length > 25 ? '...' : ''}</div>
            <div class="conversation-meta">${conv.messageCount} mensaje${conv.messageCount !== 1 ? 's' : ''} · ${timeStr}</div>
          </div>
          <div class="conversation-actions">
            ${conv.hasUnread ? '<span class="conversation-unread"></span>' : ''}
            <button class="conversation-delete" onclick="event.stopPropagation(); deleteConversation('${conv.username}')" title="Eliminar chat">🗑️</button>
          </div>
        `;
    item.onclick = () => selectConversation(conv.username);
    list.appendChild(item);
  }
}

// Procesar chats raw en formato listo para mostrar
function processChatsData(chats) {
  const conversationUsers = Object.keys(chats || {});

  if (conversationUsers.length === 0) return [];

  const conversationsData = conversationUsers.map(username => {
    const userMessages = chats[username];
    const messagesArray = Object.values(userMessages || {});

    // Ordenar por timestamp para obtener el último mensaje
    messagesArray.sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));

    const lastMsg = messagesArray[messagesArray.length - 1];
    const hasUnread = messagesArray.some(msg => msg.from !== ADMIN_USER && msg.from !== currentUser && !msg.read);

    return {
      username,
      lastMessage: lastMsg?.text || '',
      lastTime: lastMsg?.timestamp || null,
      hasUnread,
      messageCount: messagesArray.length
    };
  });

  // Ordenar por último mensaje (más reciente primero)
  conversationsData.sort((a, b) => (b.lastTime || 0) - (a.lastTime || 0));

  return conversationsData;
}

// Cargar conversaciones desde caché (instantáneo)
function loadConversationsFromCache() {
  try {
    const cached = localStorage.getItem(CONVERSATIONS_CACHE_KEY);
    if (cached) {
      const conversationsData = JSON.parse(cached);
      renderConversationsList(conversationsData);
      console.log("Conversaciones cargadas desde cache:", conversationsData.length);
      return true;
    }
  } catch (e) {
    console.warn('Error loading conversations cache:', e);
  }
  return false;
}

// Cargar lista de conversaciones para Esstor (CON CACHÉ)
async function loadConversations() {
  const list = document.getElementById('conversations-list');

  // 1. Mostrar caché primero (instantáneo)
  const hadCache = loadConversationsFromCache();

  // Solo mostrar "cargando" si no hay caché
  if (!hadCache) {
    list.innerHTML = '<div style="padding:20px; text-align:center; color:rgba(255,255,255,0.5);">Cargando conversaciones...</div>';
  }

  try {
    // 2. Sincronizar con Firebase en segundo plano
    const snapshot = await database.ref('chats').once('value');
    const chats = snapshot.val() || {};

    // Procesar datos
    const conversationsData = processChatsData(chats);

    // Guardar en caché para próxima vez
    try {
      localStorage.setItem(CONVERSATIONS_CACHE_KEY, JSON.stringify(conversationsData));
    } catch (cacheError) {
      console.warn('Could not cache conversations:', cacheError);
    }

    // Renderizar datos frescos
    renderConversationsList(conversationsData);
    console.log("Conversaciones sincronizadas desde Firebase:", conversationsData.length);

  } catch (error) {
    console.error('Error loading conversations:', error);
    // Solo mostrar error si no teníamos caché
    if (!hadCache) {
      list.innerHTML = '<div style="padding:20px; text-align:center; color:#ff6b6b;">Error al cargar conversaciones</div>';
    }
  }
}

// Pre-cargar conversaciones en segundo plano para Esstor (sin UI)
let conversationsPreloaded = false;
async function preloadConversationsForAdmin() {
  if (!isAdmin() || conversationsPreloaded) return;

  console.log("Pre-cargando conversaciones para Esstor...");
  conversationsPreloaded = true;

  try {
    const snapshot = await database.ref('chats').once('value');
    const chats = snapshot.val() || {};
    const conversationsData = processChatsData(chats);

    // Solo guardar en caché, no renderizar
    try {
      localStorage.setItem(CONVERSATIONS_CACHE_KEY, JSON.stringify(conversationsData));
      console.log("Conversaciones pre-cargadas:", conversationsData.length);
    } catch (cacheError) {
      console.warn('Could not cache conversations:', cacheError);
    }
  } catch (error) {
    console.error('Error pre-loading conversations:', error);
  }
}

async function deleteConversation(username) {
  if (!confirm(`¿Eliminar la conversación con ${username}? Esta acción no se puede deshacer.`)) {
    return;
  }

  try {
    await database.ref(`chats/${username}`).remove();

    // Limpiar caché para forzar recarga fresca
    localStorage.removeItem(CONVERSATIONS_CACHE_KEY);

    // Si era la conversación activa, limpiar la vista
    if (currentChatPartner === username) {
      currentChatPartner = null;
      document.getElementById('chat-messages').innerHTML = `
            <div class="chat-welcome">
              <p>Selecciona una conversación para ver los mensajes.</p>
            </div>
          `;
      document.getElementById('chat-partner-info').style.display = 'none';
      document.getElementById('chat-messages-area').style.display = 'none';
      document.getElementById('contact-chat').classList.add('conversations-only');
    }

    loadConversations();
  } catch (error) {
    console.error('Error deleting conversation:', error);
    alert('Error al eliminar la conversación');
  }
}

function selectConversation(username) {
  currentChatPartner = username;

  // Ocultar lista de conversaciones y mostrar chat
  document.getElementById('chat-conversations').style.display = 'none';
  document.getElementById('chat-partner-info').style.display = 'flex';
  document.getElementById('chat-messages-area').style.display = 'flex';
  document.getElementById('contact-chat').classList.remove('conversations-only');

  // Mostrar botón de volver solo para admin
  if (isAdmin()) {
    document.getElementById('chat-back-btn').classList.add('show');
  }

  document.querySelector('.chat-partner-avatar').textContent = username.charAt(0).toUpperCase();
  document.querySelector('.chat-partner-name').textContent = username;

  loadChatMessages(username, ADMIN_USER);

  // Start presence and typing listeners
  listenToPartnerPresence(username);
  listenToTypingStatus();

  // Add typing detection to input
  const chatInput = document.getElementById('chat-input');
  chatInput.removeEventListener('input', handleTyping);
  chatInput.addEventListener('input', handleTyping);
}

function backToConversations() {
  // Ocultar chat y mostrar lista de conversaciones
  document.getElementById('chat-conversations').style.display = 'block';
  document.getElementById('chat-partner-info').style.display = 'none';
  document.getElementById('chat-messages-area').style.display = 'none';
  document.getElementById('contact-chat').classList.add('conversations-only');
  document.getElementById('chat-back-btn').classList.remove('show');

  // Desuscribir del chat actual
  if (chatUnsubscribe) {
    chatUnsubscribe();
    chatUnsubscribe = null;
  }

  currentChatPartner = null;
  loadConversations();
}

function loadChatMessages(username, partner) {
  const container = document.getElementById('chat-messages');
  
  // Safely remove old messages without destroying the form structure
  container.querySelectorAll('.chat-message, .chat-welcome').forEach(el => el.remove());
  
  // Show loading state safely
  const loadingEl = document.createElement('div');
  loadingEl.className = 'chat-welcome';
  loadingEl.id = 'chat-loading-msg';
  loadingEl.innerHTML = '<p>Cargando mensajes...</p>';
  container.appendChild(loadingEl);

  // Desuscribir listener anterior
  if (chatUnsubscribe) {
    chatUnsubscribe();
  }

  // La ruta del chat es siempre por el nombre del usuario normal (no Esstor)
  const chatPath = isAdmin() ? username : currentUser;

  // Use simple ref without orderByChild for faster loading (sort client-side)
  const ref = database.ref(`chats/${chatPath}`);

  const listener = ref.on('value', (snapshot) => {
    const messages = [];
    snapshot.forEach(child => {
      messages.push({ id: child.key, ...child.val() });
    });

    // Sort by timestamp client-side (faster than Firebase orderByChild without index)
    messages.sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));

    // Check for new incoming messages to play notification
    if (messages.length > lastMessageCount && lastMessageCount > 0) {
      const lastMsg = messages[messages.length - 1];
      // Only play notification if message is from the OTHER user
      if (lastMsg && lastMsg.from !== currentUser) {
        playNotificationSound();
      }
    }
    lastMessageCount = messages.length;

    // Remove loading message if it exists
    const loader = document.getElementById('chat-loading-msg');
    if (loader) loader.remove();

    if (messages.length === 0) {
      if (!isAdmin()) {
        // Mostrar de primeras el panel de bienvenida y acciones rápidas
        const quickActionsEl = document.getElementById('chat-quick-actions');
        if (quickActionsEl) quickActionsEl.style.display = 'block';
        
        const missionFormEl = document.getElementById('chat-mission-form');
        if (missionFormEl) missionFormEl.style.display = 'none';

        // Remove loading and old messages
        container.querySelectorAll('.chat-message, .chat-welcome').forEach(el => el.remove());
      } else {
        const quickActionsEl = document.getElementById('chat-quick-actions');
        if (quickActionsEl) quickActionsEl.style.display = 'none';
        
        // Remove old messages safely
        container.querySelectorAll('.chat-message, .chat-welcome').forEach(el => el.remove());
        
        // Add welcome message for admin
        const welcomeEl = document.createElement('div');
        welcomeEl.className = 'chat-welcome';
        welcomeEl.innerHTML = `
          <p>👋 Chat con ${username}</p>
          <p class="chat-hint">No hay mensajes aún.</p>
        `;
        container.appendChild(welcomeEl);
      }
      return;
    }

    // Hide quick actions when there are messages
    const quickActionsEl = document.getElementById('chat-quick-actions');
    if (quickActionsEl) quickActionsEl.style.display = 'none';
    
    // Hide mission form when there are messages
    const missionFormEl = document.getElementById('chat-mission-form');
    if (missionFormEl) missionFormEl.style.display = 'none';

    // Safely remove only the message bubbles and welcome messages
    container.querySelectorAll('.chat-message, .chat-welcome').forEach(el => el.remove());
    messages.forEach(msg => {
      const isSent = msg.from === currentUser;
      const msgEl = document.createElement('div');
      msgEl.className = `chat-message ${isSent ? 'sent' : 'received'}`;

      const time = new Date(msg.timestamp).toLocaleTimeString('es-ES', { hour: '2-digit', minute: '2-digit' });

      // Render attachment if present
      let attachmentHtml = '';
      if (msg.attachment) {
        attachmentHtml = renderAttachment(msg.attachment);
      }

      // Render topic tag if present
      let topicHtml = '';
      if (msg.topic) {
        topicHtml = `<div class="chat-topic-tag">${msg.topic}</div>`;
      }

      msgEl.innerHTML = `
            ${topicHtml}
            ${msg.text ? `<div>${msg.text}</div>` : ''}
            ${attachmentHtml}
            <div class="chat-message-time">${time}</div>
          `;
      container.appendChild(msgEl);

      // Marcar como leído si es para el usuario actual
      if (!isSent && !msg.read) {
        database.ref(`chats/${chatPath}/${msg.id}`).update({ read: true });
      }
    });

    // Scroll to bottom
    container.scrollTop = container.scrollHeight;
  });

  chatUnsubscribe = () => ref.off('value', listener);
}

async function sendChatMessage(e) {
  e.preventDefault();
  const input = document.getElementById('chat-input');
  const text = input.value.trim();

  // Require either text or attachment
  if (!text && !pendingAttachment) return;
  if (!currentUser) return;

  // Determinar la ruta del chat
  const chatPath = isAdmin() ? currentChatPartner : currentUser;

  if (!chatPath) {
    alert('Selecciona una conversación primero');
    return;
  }

  const message = {
    from: currentUser,
    to: isAdmin() ? currentChatPartner : ADMIN_USER,
    text: text,
    timestamp: Date.now(),
    read: false
  };

  // Add attachment if present
  if (pendingAttachment) {
    message.attachment = {
      base64: pendingAttachment.base64,
      fileName: pendingAttachment.fileName,
      fileType: pendingAttachment.fileType,
      isImage: pendingAttachment.isImage
    };
  }

  try {
    await database.ref(`chats/${chatPath}`).push(message);
    input.value = '';

    // Clear attachment after sending
    clearAttachment();

    // Si Esstor está respondiendo, actualizar la lista de conversaciones
    if (isAdmin()) {
      loadConversations();
    }
  } catch (error) {
    console.error('Error sending message:', error);
    alert('Error al enviar el mensaje');
  }
}

// ===== QUICK ACTIONS =====
const QUICK_ACTION_MESSAGES = {
  launch: { text: '🚀 Me gustaría programar un lanzamiento', tag: 'Lanzamiento' },
  satellite: { text: '📡 Quiero información sobre la constelación EsZunSat', tag: 'Satélites' },
  support: { text: '🔧 Necesito soporte técnico', tag: 'Soporte' },
  other: { text: '', tag: 'Consulta' }
};

async function selectQuickAction(topic) {
  const action = QUICK_ACTION_MESSAGES[topic];
  if (!action) return;

  // For "launch" topic, show the advanced mission form
  if (topic === 'launch') {
    showMissionForm();
    return;
  }

  // For "other" topic, just focus the input
  if (topic === 'other') {
    document.getElementById('chat-input').focus();
    // Hide quick actions
    const qa = document.getElementById('chat-quick-actions');
    if (qa) qa.style.display = 'none';
    return;
  }

  // Send the prefilled message
  if (!currentUser || !currentChatPartner) return;

  const chatPath = isAdmin() ? currentChatPartner : currentUser;
  if (!chatPath) return;

  const message = {
    from: currentUser,
    to: ADMIN_USER,
    text: action.text,
    topic: action.tag,
    timestamp: Date.now(),
    read: false
  };

  try {
    await database.ref(`chats/${chatPath}`).push(message);
    // Hide quick actions after sending
    const qa = document.getElementById('chat-quick-actions');
    if (qa) qa.style.display = 'none';
  } catch (error) {
    console.error('Error sending quick action:', error);
  }
}

// ===== MISSION FORM LOGIC =====
function showMissionForm() {
  const qa = document.getElementById('chat-quick-actions');
  const mf = document.getElementById('chat-mission-form');
  if (qa) qa.style.display = 'none';
  if (mf) mf.style.display = 'flex';
  
  // Scroll to make it visible
  setTimeout(() => {
    const container = document.getElementById('chat-messages');
    if (container) container.scrollTop = container.scrollHeight;
  }, 50);
}

function hideMissionForm() {
  const qa = document.getElementById('chat-quick-actions');
  const mf = document.getElementById('chat-mission-form');
  if (mf) mf.style.display = 'none';
  if (qa) qa.style.display = 'flex';
}

function escapeHTML(str) {
  return str.replace(/[&<>'"]/g, 
    tag => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      "'": '&#39;',
      '"': '&quot;'
    }[tag] || tag)
  );
}

async function submitMissionForm(e) {
  e.preventDefault();
  
  if (!currentUser || !currentChatPartner) return;
  const chatPath = isAdmin() ? currentChatPartner : currentUser;
  if (!chatPath) return;

  const payloadType = document.getElementById('mission-payload-type').value;
  const orbit = document.getElementById('mission-orbit').value;
  const weight = document.getElementById('mission-weight').value;
  const count = document.getElementById('mission-count').value;
  const dateStr = document.getElementById('mission-date').value;
  const extra = document.getElementById('mission-extra').value.trim();

  let formattedDate = 'No especificada';
  if (dateStr) {
    const [year, month] = dateStr.split('-');
    const dateObj = new Date(year, parseInt(month) - 1);
    formattedDate = dateObj.toLocaleDateString('es-ES', { year: 'numeric', month: 'long' });
    formattedDate = formattedDate.charAt(0).toUpperCase() + formattedDate.slice(1);
  }

  const safeExtra = extra ? escapeHTML(extra).replace(/\n/g, '<br>') : '';

  const messageText = `🚀 <strong>SOLICITUD DE MISIÓN</strong><br><br>` +
    `• <strong>Tipo de Carga:</strong> ${escapeHTML(payloadType)}<br>` +
    `• <strong>Órbita Objetivo:</strong> ${escapeHTML(orbit)}<br>` +
    `• <strong>Peso Estimado:</strong> ${weight} kg<br>` +
    `• <strong>Lanzamientos:</strong> ${count}<br>` +
    `• <strong>Fecha Deseada:</strong> ${formattedDate}` +
    (safeExtra ? `<br><br><em>Detalles adicionales:</em><br>${safeExtra}` : '');

  const message = {
    from: currentUser,
    to: ADMIN_USER,
    text: messageText,
    topic: 'Misión',
    timestamp: Date.now(),
    read: false
  };

  try {
    const btn = e.target.querySelector('button[type="submit"]');
    const originalText = btn.innerHTML;
    btn.innerHTML = 'Enviando...';
    btn.disabled = true;

    await database.ref(`chats/${chatPath}`).push(message);
    
    // Clean up
    document.getElementById('mission-request-form').reset();
    document.getElementById('chat-mission-form').style.display = 'none';
    
    // Reset button
    btn.innerHTML = originalText;
    btn.disabled = false;
  } catch (error) {
    console.error('Error enviando solicitud de misión:', error);
    alert('Error al enviar la solicitud');
    e.target.querySelector('button[type="submit"]').disabled = false;
  }
}

// Cerrar modal al hacer clic fuera
document.getElementById('contact-modal')?.addEventListener('click', (e) => {
  if (e.target.id === 'contact-modal') {
    closeContactModal();
  }
});

function showUpdatesModal() {
  document.getElementById('updates-modal').classList.add('show');
  document.body.style.overflow = 'hidden';

  // Mostrar formulario de admin si es Esstor
  const adminForm = document.getElementById('update-admin-form');
  if (isAdmin()) {
    adminForm.style.display = 'block';
  } else {
    adminForm.style.display = 'none';
  }

  loadUpdates();
}

function closeUpdatesModal() {
  document.getElementById('updates-modal').classList.remove('show');
  document.body.style.overflow = '';
}

async function loadUpdates() {
  const container = document.getElementById('updates-list');
  container.innerHTML = '<div class="loading">Cargando actualizaciones...</div>';

  try {
    const snapshot = await database.ref('updates').orderByChild('timestamp').once('value');
    updatesData = [];

    snapshot.forEach((child) => {
      updatesData.push({
        id: child.key,
        ...child.val()
      });
    });

    // Ordenar de más reciente a más antiguo
    updatesData.reverse();

    renderUpdates();
  } catch (error) {
    console.error('Error cargando actualizaciones:', error);
    container.innerHTML = '<div class="no-updates">Error al cargar actualizaciones</div>';
  }
}

function renderUpdates() {
  const container = document.getElementById('updates-list');
  const isAdmin = currentUser === ADMIN_USER;

  if (updatesData.length === 0) {
    container.innerHTML = '<div class="no-updates">No hay actualizaciones disponibles</div>';
    return;
  }

  const now = Date.now();
  const threeDays = 3 * 24 * 60 * 60 * 1000; // 3 días en ms

  container.innerHTML = updatesData.map((update, index) => {
    const isNew = (now - update.timestamp) < threeDays;
    const date = new Date(update.timestamp);
    const dateStr = date.toLocaleDateString('es-ES', { day: 'numeric', month: 'long', year: 'numeric' }).toUpperCase();

    // Truncar descripción en la lista
    const shortDesc = update.description.length > 150 ?
      update.description.substring(0, 150) + '...' : update.description;

    const imageHtml = update.imageUrl ?
      `<img src="${escapeHtml(update.imageUrl)}" alt="" class="update-image" loading="lazy">` : '';

    return `
          <div class="update-item ${isNew ? 'new' : ''}" onclick="openUpdateDetail(${index})" data-index="${index}">
            ${isNew ? '<div class="update-badge">NUEVO</div>' : ''}
            ${isAdmin ? `<button class="update-delete-btn" onclick="event.stopPropagation(); deleteUpdate('${update.id}')" title="Eliminar">🗑</button>` : ''}
            <div class="update-date">${dateStr}</div>
            <h3 class="update-name">${escapeHtml(update.title)}</h3>
            <p class="update-desc">${escapeHtml(shortDesc)}</p>
            ${imageHtml}
          </div>
        `;
  }).join('');
}

function openUpdateDetail(index) {
  const update = updatesData[index];
  if (!update) return;

  const date = new Date(update.timestamp);
  const dateStr = date.toLocaleDateString('es-ES', { day: 'numeric', month: 'long', year: 'numeric' }).toUpperCase();

  const imageHtml = update.imageUrl ?
    `<img src="${update.imageUrl}" alt="" class="detail-image">` : '';

  const linkHtml = update.linkUrl ?
    `<a href="${escapeHtml(update.linkUrl)}" class="detail-link-btn" target="_blank" rel="noopener">${escapeHtml(update.linkText || 'Ver más')}</a>` : '';

  const content = `
        ${imageHtml}
        <div class="detail-body">
          <div class="detail-date">${dateStr}</div>
          <h2 class="detail-title">${escapeHtml(update.title)}</h2>
          <p class="detail-description">${escapeHtml(update.description)}</p>
          ${linkHtml}
        </div>
      `;

  document.getElementById('update-detail-content').innerHTML = content;
  document.getElementById('update-detail-modal').classList.add('show');
}

function closeUpdateDetail() {
  document.getElementById('update-detail-modal').classList.remove('show');
}

// Cerrar modal de detalle con click fuera o Escape
document.getElementById('update-detail-modal')?.addEventListener('click', (e) => {
  if (e.target.id === 'update-detail-modal') {
    closeUpdateDetail();
  }
});

function escapeHtml(text) {
  if (!text) return '';
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

async function createUpdate() {
  if (currentUser !== ADMIN_USER) {
    alert('No tienes permisos para crear actualizaciones');
    return;
  }

  const title = document.getElementById('update-title-input').value.trim();
  const description = document.getElementById('update-desc-input').value.trim();
  const imageBase64 = document.getElementById('update-image-base64').value;
  const linkUrl = document.getElementById('update-link-input').value.trim();
  const linkText = document.getElementById('update-link-text-input').value.trim();

  if (!title || !description) {
    alert('Por favor, completa el título y la descripción');
    return;
  }

  try {
    const newUpdate = {
      title: title,
      description: description,
      timestamp: Date.now(),
      author: ADMIN_USER
    };

    // Añadir campos opcionales solo si tienen valor
    if (imageBase64) newUpdate.imageUrl = imageBase64;
    if (linkUrl) {
      newUpdate.linkUrl = linkUrl;
      newUpdate.linkText = linkText || 'Ver más';
    }

    await database.ref('updates').push(newUpdate);

    // Limpiar formulario
    document.getElementById('update-title-input').value = '';
    document.getElementById('update-desc-input').value = '';
    document.getElementById('update-image-file').value = '';
    document.getElementById('update-image-base64').value = '';
    document.getElementById('update-image-preview').style.display = 'none';
    document.getElementById('update-link-input').value = '';
    document.getElementById('update-link-text-input').value = 'Ver más';

    // Recargar lista
    loadUpdates();
  } catch (error) {
    console.error('Error creando actualización:', error);
    alert('Error al crear la actualización');
  }
}

async function deleteUpdate(updateId) {
  if (currentUser !== ADMIN_USER) {
    alert('No tienes permisos para eliminar actualizaciones');
    return;
  }

  if (!confirm('¿Estás seguro de que quieres eliminar esta actualización?')) {
    return;
  }

  try {
    await database.ref('updates/' + updateId).remove();
    loadUpdates();
  } catch (error) {
    console.error('Error eliminando actualización:', error);
    alert('Error al eliminar la actualización');
  }
}

// Cerrar modal con Escape o click fuera
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    closeUpdateDetail();
    closeUpdatesModal();
  }
});

document.getElementById('updates-modal')?.addEventListener('click', (e) => {
  if (e.target.id === 'updates-modal') {
    closeUpdatesModal();
  }
});

document.addEventListener("DOMContentLoaded", () => {
  document.body.classList.add("fade-in");
  document.getElementById("year").textContent = new Date().getFullYear();

  // INITIALIZE CUSTOM AUTH - Load from cache first (instant), then sync from Firebase in background
  loadUsersFromCache();
  hydrateSessionFromStorage();

  // Set user as online if logged in
  if (currentUser) {
    updatePresence(true);
  }

  // Sync users from Firebase in background (non-blocking)
  loadUsers();

  // Image upload handler for updates
  const updateImageInput = document.getElementById('update-image-file');
  if (updateImageInput) {
    updateImageInput.addEventListener('change', function (e) {
      const file = e.target.files[0];
      if (!file) return;

      if (file.size > 2 * 1024 * 1024) { // 2MB limit
        alert('La imagen es muy grande. Se recomienda menos de 2MB.');
      }

      const reader = new FileReader();
      reader.onloadend = function () {
        const base64 = reader.result;
        document.getElementById('update-image-base64').value = base64;
        const preview = document.getElementById('update-image-preview');
        preview.style.backgroundImage = `url('${base64}')`;
        preview.style.display = 'block';
      };
      reader.readAsDataURL(file);
    });
  }

  const path = location.pathname.split("/").pop() || "index.html";
  document.querySelectorAll(".menu a").forEach(a => {
    const href = a.getAttribute("href");
    if ((path === "" && href === "index.html") || href === path) {
      a.setAttribute("aria-current", "page");
    }
  });

  // Transición suave entre páginas internas
  document.querySelectorAll('a[href]').forEach(link => {
    const url = new URL(link.href, location.href);
    if (url.origin === location.origin && !link.target) {
      link.addEventListener("click", e => {
        if (url.pathname === location.pathname && url.hash) return;
        const menu = document.querySelector('.menu');
        if (menu && menu.classList.contains('open')) return;
        e.preventDefault();
        document.body.classList.add("fade-out");
        setTimeout(() => location.href = url.href, 600);
      });
    }
  });

  // Toggle del menú en móvil
  const toggle = document.querySelector('.menu-toggle');
  const menu = document.getElementById('primary-menu');
  function setOpen(open) {
    menu.classList.toggle('open', open);
    toggle.setAttribute('aria-expanded', String(open));
    toggle.setAttribute('aria-label', open ? 'Cerrar menú' : 'Abrir menú');
  }
  toggle.addEventListener('click', () => setOpen(!menu.classList.contains('open')));
  menu.addEventListener('click', (e) => {
    if (e.target.closest('a')) setOpen(false);
  });
  document.addEventListener('click', (e) => {
    if (menu.classList.contains('open')) {
      const within = e.target.closest('.nav-shell');
      if (!within) setOpen(false);
    }
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') setOpen(false);
  });

  // Keyboard support for user-info
  document.querySelector('.user-info')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      showProfileModal();
    }
  });

  // Set offline when leaving page
  window.addEventListener('beforeunload', () => {
    if (currentUser) {
      updatePresence(false);
    }
  });
});
