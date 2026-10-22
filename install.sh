#!/usr/bin/env bash
# =============================================================================
#  SS-fast — self-steal nginx для remnanode (Reality fallback), МУЛЬТИДОМЕН
#  Сайт встроен в скрипт. Установка нового домена ДОБАВЛЯЕТ его рядом,
#  существующие домены на этой ноде не трогаются.
#
#  УСТАНОВКА:
#    Cloudflare: CF_Token=.. [CF_Account_ID=..] ACME_EMAIL=you@mail bash install.sh <domain>
#    CF (email): CF_Key=.. CF_Email=..           ACME_EMAIL=you@mail bash install.sh <domain>
#    reg.ru:     REGRU_USER=.. REGRU_PASS=..      ACME_EMAIL=you@mail bash install.sh <domain>
#
#  ВЫБОР САЙТА:
#    -z, --zro   Northvale Cloud (по умолчанию; SS_SITE=zro)
#    -m, --mona  Tarnex          (SS_SITE=mona)
#    Флаг можно ставить где угодно:  bash install.sh -m <domain>   |   bash install.sh update -m
#
#  ОБНОВЛЕНИЕ САЙТА (для ВСЕХ доменов ноды, без cert/compose):
#    bash install.sh update [-z|-m]
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
GRAY='\033[0;90m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}━━━━━━━━━  $*  ━━━━━━━━━${NC}"; }

REMNANODE_DIR="/opt/remnanode"
NGINX_DIR="/opt/nginx"
WEBROOT="${NGINX_DIR}/html"
ACME_HOME="/root/.acme.sh"
NGINX_SOCK="/dev/shm/nginx.sock"
CONTAINER="remnanode-nginx"

MODE="install"
SITE="${SS_SITE:-zro}"      # какой встроенный сайт ставить: zro (Northvale Cloud, по умолчанию) или mona (Tarnex)
_POS=()
for _a in "$@"; do
    case "${_a}" in
        -z|--zro)  SITE="zro" ;;
        -m|--mona) SITE="mona" ;;
        *)         _POS+=("${_a}") ;;
    esac
done
set -- ${_POS[@]+"${_POS[@]}"}
if [[ "${1:-}" == "update" ]]; then MODE="update"; shift; fi
case "${SITE}" in zro|mona) ;; *) echo "Неизвестный сайт '${SITE}': используйте -z (zro) или -m (mona)" >&2; exit 1 ;; esac
DOMAIN="${1:-}"
EMAIL="${ACME_EMAIL:-${2:-}}"
[[ $EUID -ne 0 ]] && error "Запусти от root"

write_html_zro() {
    mkdir -p "${WEBROOT}/assets/v1"
cat > "${WEBROOT}/404.html" <<'EOF_404_HTML'
<!DOCTYPE html><html lang="en"><head>
<title>Page not found — Northvale Cloud</title>
<meta name="description" content="The page you requested could not be found.">
<link rel="canonical" href="https://northvale.cloud/404.html">
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="manifest" href="/site.webmanifest"><link rel="stylesheet" href="/assets/v1/style.css">
</head><body>
<header class="site"><div class="wrap nav">
  <a class="brand" href="/">
    <svg class="logo" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg>
    Northvale Cloud
  </a>
  <nav class="nav-links">
    <a href="/features.html">Features</a>
    <a href="/pricing.html">Pricing</a>
    <a href="/docs.html">Docs</a>
    <a href="/login.html">Sign in</a>
  </nav>
  <div class="nav-cta">
    <a class="btn btn-ghost" href="/login.html">Sign in</a>
    <a class="btn btn-primary" href="/login.html">Get started</a>
    <button class="burger" aria-label="Menu">☰</button>
  </div>
</div></header>
<main class="nf">
  <div class="code">404</div>
  <h1>Page not found</h1>
  <p>The page you're looking for doesn't exist or was moved.</p>
  <a class="btn btn-primary" href="/">Back to home</a>
</main>
<footer class="site"><div class="wrap">
  <div class="foot-grid">
    <div class="foot-brand">
      <a class="brand" href="/"><svg class="logo" viewBox="0 0 32 32" fill="none"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg> Northvale Cloud</a>
      <p>Secure cloud storage and file sync for modern teams. Your data, encrypted and available anywhere.</p>
    </div>
    <div class="foot-col"><h4>Product</h4><a href="/features.html">Features</a><a href="/pricing.html">Pricing</a><a href="/docs.html">Docs</a><a href="/login.html">Sign in</a></div>
    <div class="foot-col"><h4>Company</h4><a href="/#about">About</a><a href="/#careers">Careers</a><a href="/#blog">Blog</a><a href="mailto:hello@northvale.cloud">Contact</a></div>
    <div class="foot-col"><h4>Legal</h4><a href="/terms.html">Terms</a><a href="/privacy.html">Privacy</a><a href="/#status">Status</a></div>
  </div>
  <div class="foot-bottom"><span>© <span class="year">2026</span> Northvale Cloud. All rights reserved.</span><span>Made for teams worldwide</span></div>
</div></footer>
<script src="/assets/v1/app.js"></script></body></html>
EOF_404_HTML

base64 -d > "${WEBROOT}/apple-touch-icon.png" <<'EOF_APPLE_TOUCH_ICON_PNG'
iVBORw0KGgoAAAANSUhEUgAAALQAAAC0CAYAAAA9zQYyAAAEnklEQVR4nO3dXXbTOgCFUaXrzg/m
AsOgc6Ej7H1gpZQ0P44t2dLR3s+QGOfrQU0W5VQ69u3X+/vR18BXbz9Pp6Ov4ZZuLky8Y+sl8kMv
QsSZjox79ycW8Vz2jnu3JxPy3PYKu/mTCJnPWofd7MGFzD2twn5p8aBi5pFWjVT9KhEya9Rc62oL
LWbWqtlOlaDFzFa1Gto09UKmhS1HkNULLWZa2dLWqqDFTGtrG3s6aDGzlzWtPRW0mNnbs801+WAF
jrI4aOvMUZ5pb1HQYuZoSxt8GLSY6cWSFp2hiXI3aOtMbx41eTNoMdOre206chDlatDWmd7datRC
E+VL0NaZUVxr1UIT5Z+grTOjuWzWQhNF0ET5CNpxg1F9btdCE0XQRHkpxXGD8Z0bttBEETRRBE0U
QRPl5BtCklhoogiaKIImiqCJImiiCJoogiaKoIkiaKIImiiCJoqgiSJoogiaKIImiqCJImii/Hf0
BfDX7x/Lf+3313bXMTJBH+iZgB/9XoH/IegDbAn50WPOHragd9Qi5FvPMWvYgt7BHiHfes7ZwvYu
R2NHxNzT8+/NQjfSU0gzrbWFbqCnmD/r9bpqEnRlvUfT+/VtJeiKRolllOtcQ9CVjBbJaNe7lKAr
GDWOUa/7HkETRdAbjb5yo1//JUFvkBJDyp+jFB+sLHoxZ/hAIsV0P8G/xhp9f81atbOEL9xpFrpm
gIkxp4g/Q//+IcClEu5T7EInvDg8L3Khxbze6PcuLujRXxC2iQpazMQELWZKCQlazHWNfD+HD3rk
m099QwctZi4NHTRcGjZo68w1wwYN1wwZtHXmliGDhluGC9o6c89wQcM9giaKoPli5H+KNVTQzs88
MlTQ8IigiSJo/jHy+bkUQRNG0HwYfZ1LETRhBE0pJWOdSxE0YYYKOmVFepN0X4cKmvqSYi5F0IQR
9MTS1rmUAYNOfBGOkHofhwua7VJjLmXQoJNfkNbS792QQbNOesylDBz0DC9OLd9f57lfwwbNMrOE
fDZ00LO9WM+a8f4MHXQpc75o3DZ80KWImr8igi5F1PwRE3QpoiYs6FJEPbu4oEsR9cxi/2vkc9R7
/LQlX0D9iA36rGXYQu5PfNBnNcMWcr+mCfrsMsYlgQt4HNMFfUmsWSLf5WBegiaKoIkiaKIImiiC
JoqgiSJoogiaKIImiqCJImiiCJoogiaKoIkiaKIImigvbz9Pp6MvAmp4+3k6WWiiCJoogiaKoIny
Usqfw/TRFwJbnBu20EQRNFE+gnbsYFSf27XQRBE0Uf4J2rGD0Vw2a6GJ8iVoK80orrVqoYlyNWgr
Te9uNWqhiXIzaCtNr+61eXehRU1vHjXpyEGUh0FbaXqxpMVFCy1qjra0wcVHDlFzlGfac4YmylNB
W2n29mxzTy+0qNnLmtZWHTlETWtrG1t9hhY1rWxpq0qU3369v9d4HOZWYySrvMthrdmqVkPV3rYT
NWvVbKdJhI4gLNFiBJt8sGKteaRVI83Ds9Z81nrsdltSYc9tr7+1dz8aCHsuex8/Dz3rijvTkd9D
dfPNm7jH1ssbAV1cxC0i71Mv8V7zPyRxN7xwDPllAAAAAElFTkSuQmCC
EOF_APPLE_TOUCH_ICON_PNG

cat > "${WEBROOT}/assets/v1/app.js" <<'EOF_ASSETS_V1_APP_JS'
(function () {
  // mobile nav
  var burger = document.querySelector('.burger');
  var links = document.querySelector('.nav-links');
  if (burger && links) {
    burger.addEventListener('click', function () {
      links.classList.toggle('open');
    });
  }

  // auth tabs
  var tabSignin = document.getElementById('tab-signin');
  var tabSignup = document.getElementById('tab-signup');
  var title = document.getElementById('auth-title');
  var submit = document.getElementById('auth-submit');
  var nameField = document.getElementById('field-name');
  function setMode(mode) {
    if (!tabSignin) return;
    var isUp = mode === 'signup';
    tabSignup.classList.toggle('active', isUp);
    tabSignin.classList.toggle('active', !isUp);
    if (title) title.textContent = isUp ? 'Create your account' : 'Welcome back';
    if (submit) submit.textContent = isUp ? 'Create account' : 'Sign in';
    if (nameField) nameField.style.display = isUp ? 'block' : 'none';
  }
  if (tabSignin) tabSignin.addEventListener('click', function () { setMode('signin'); });
  if (tabSignup) tabSignup.addEventListener('click', function () { setMode('signup'); });

  // auth submit -> realistic client-side rejection
  var form = document.getElementById('auth-form');
  var err = document.getElementById('auth-err');
  if (form) {
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var btn = document.getElementById('auth-submit');
      if (btn) { btn.disabled = true; btn.textContent = 'Please wait…'; }
      setTimeout(function () {
        if (err) {
          err.textContent = 'Invalid email or password. Please try again.';
          err.classList.add('show');
        }
        if (btn) { btn.disabled = false; btn.textContent = tabSignup && tabSignup.classList.contains('active') ? 'Create account' : 'Sign in'; }
      }, 700);
    });
  }

  // year
  var y = document.querySelectorAll('.year');
  for (var i = 0; i < y.length; i++) y[i].textContent = new Date().getFullYear();
})();
EOF_ASSETS_V1_APP_JS

cat > "${WEBROOT}/assets/v1/style.css" <<'EOF_ASSETS_V1_STYLE_CSS'
:root{
  --bg:#0b0d12;--bg-soft:#12151c;--card:#161a22;--border:#232834;
  --fg:#e7e9ee;--muted:#98a1b3;--muted-2:#6b7385;
  --accent:#4f8cff;--accent-2:#38d39f;--accent-ink:#0b0d12;
  --radius:14px;--maxw:1120px;--ff:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,"Apple Color Emoji","Segoe UI Emoji",sans-serif;
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;font-family:var(--ff);background:var(--bg);color:var(--fg);line-height:1.55;-webkit-font-smoothing:antialiased}
a{color:inherit;text-decoration:none}
img,svg{display:block;max-width:100%}
.wrap{max-width:var(--maxw);margin:0 auto;padding:0 24px}
.btn{display:inline-flex;align-items:center;gap:8px;padding:11px 18px;border-radius:10px;font-weight:600;font-size:15px;border:1px solid transparent;cursor:pointer;transition:.15s}
.btn-primary{background:var(--accent);color:#fff}
.btn-primary:hover{background:#3f7bef}
.btn-ghost{border-color:var(--border);color:var(--fg);background:transparent}
.btn-ghost:hover{border-color:#33394a;background:var(--bg-soft)}
.btn-lg{padding:14px 24px;font-size:16px}

/* header */
header.site{position:sticky;top:0;z-index:40;background:rgba(11,13,18,.82);backdrop-filter:blur(10px);border-bottom:1px solid var(--border)}
.nav{display:flex;align-items:center;justify-content:space-between;height:64px}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;font-size:17px;letter-spacing:-.01em}
.brand .logo{width:28px;height:28px}
.nav-links{display:flex;align-items:center;gap:28px}
.nav-links a{color:var(--muted);font-size:15px;font-weight:500}
.nav-links a:hover{color:var(--fg)}
.nav-cta{display:flex;align-items:center;gap:12px}
.burger{display:none;background:none;border:0;color:var(--fg);cursor:pointer;padding:6px}
@media(max-width:860px){
  .nav-links,.nav-cta .btn-ghost{display:none}
  .burger{display:block}
  .nav-links.open{display:flex;position:absolute;top:64px;left:0;right:0;flex-direction:column;gap:0;background:var(--bg-soft);border-bottom:1px solid var(--border);padding:8px 24px 16px}
  .nav-links.open a{padding:12px 0;border-bottom:1px solid var(--border)}
}

/* hero */
.hero{padding:96px 0 72px;text-align:center;position:relative;overflow:hidden}
.hero::before{content:"";position:absolute;inset:-40% 0 auto 0;height:600px;background:radial-gradient(600px 300px at 50% 0,rgba(79,140,255,.18),transparent 70%);pointer-events:none}
.eyebrow{display:inline-block;font-size:13px;font-weight:600;color:var(--accent);background:rgba(79,140,255,.1);border:1px solid rgba(79,140,255,.25);padding:5px 12px;border-radius:999px;margin-bottom:22px}
h1{font-size:clamp(34px,6vw,56px);line-height:1.05;letter-spacing:-.03em;margin:0 0 18px;font-weight:800}
.hero p.lead{font-size:19px;color:var(--muted);max-width:620px;margin:0 auto 32px}
.hero-cta{display:flex;gap:14px;justify-content:center;flex-wrap:wrap}
.hero-note{margin-top:16px;font-size:13px;color:var(--muted-2)}

.logos{padding:36px 0;border-top:1px solid var(--border);border-bottom:1px solid var(--border);background:var(--bg-soft)}
.logos .wrap{display:flex;align-items:center;justify-content:center;gap:44px;flex-wrap:wrap;opacity:.6}
.logos span{font-weight:700;font-size:18px;color:var(--muted);letter-spacing:-.02em}

section.block{padding:80px 0}
.section-head{text-align:center;max-width:640px;margin:0 auto 52px}
.section-head h2{font-size:clamp(26px,4vw,38px);letter-spacing:-.02em;margin:0 0 14px;font-weight:800}
.section-head p{color:var(--muted);font-size:17px;margin:0}

.grid{display:grid;gap:20px}
.grid.cols-3{grid-template-columns:repeat(3,1fr)}
.grid.cols-2{grid-template-columns:repeat(2,1fr)}
@media(max-width:860px){.grid.cols-3,.grid.cols-2{grid-template-columns:1fr}}
.card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:26px}
.card .ico{width:40px;height:40px;border-radius:10px;background:rgba(79,140,255,.12);display:flex;align-items:center;justify-content:center;margin-bottom:16px;color:var(--accent)}
.card h3{margin:0 0 8px;font-size:18px;letter-spacing:-.01em}
.card p{margin:0;color:var(--muted);font-size:15px}

.cta-band{margin:0 24px;background:linear-gradient(135deg,#182036,#131a2b);border:1px solid var(--border);border-radius:20px;padding:56px 32px;text-align:center}
.cta-band h2{font-size:clamp(24px,4vw,34px);margin:0 0 12px;letter-spacing:-.02em}
.cta-band p{color:var(--muted);margin:0 0 26px;font-size:17px}

/* pricing */
.plans{display:grid;grid-template-columns:repeat(3,1fr);gap:20px;align-items:stretch}
@media(max-width:860px){.plans{grid-template-columns:1fr}}
.plan{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:30px;display:flex;flex-direction:column}
.plan.featured{border-color:var(--accent);box-shadow:0 0 0 1px var(--accent),0 20px 60px -30px rgba(79,140,255,.6)}
.plan .tag{font-size:12px;font-weight:700;color:var(--accent);text-transform:uppercase;letter-spacing:.05em}
.plan .price{font-size:44px;font-weight:800;letter-spacing:-.03em;margin:14px 0 2px}
.plan .price span{font-size:16px;font-weight:500;color:var(--muted)}
.plan ul{list-style:none;padding:0;margin:22px 0 26px;display:flex;flex-direction:column;gap:12px;flex:1}
.plan li{display:flex;gap:10px;font-size:15px;color:var(--muted)}
.plan li svg{flex:0 0 auto;color:var(--accent-2)}

/* auth */
.auth-shell{min-height:calc(100vh - 64px);display:flex;align-items:center;justify-content:center;padding:48px 24px}
.auth{width:100%;max-width:400px;background:var(--card);border:1px solid var(--border);border-radius:16px;padding:36px}
.auth h1{font-size:24px;text-align:center;margin:0 0 6px}
.auth .sub{text-align:center;color:var(--muted);font-size:14px;margin:0 0 26px}
.tabs{display:flex;background:var(--bg-soft);border:1px solid var(--border);border-radius:10px;padding:4px;margin-bottom:22px}
.tabs button{flex:1;background:none;border:0;color:var(--muted);font-weight:600;font-size:14px;padding:8px;border-radius:7px;cursor:pointer}
.tabs button.active{background:var(--card);color:var(--fg)}
.field{margin-bottom:16px}
.field label{display:block;font-size:13px;color:var(--muted);margin-bottom:7px;font-weight:500}
.field input{width:100%;background:var(--bg-soft);border:1px solid var(--border);border-radius:9px;padding:11px 13px;color:var(--fg);font-size:15px;font-family:inherit}
.field input:focus{outline:none;border-color:var(--accent)}
.auth .btn{width:100%;justify-content:center}
.auth .err{display:none;background:rgba(255,86,86,.1);border:1px solid rgba(255,86,86,.3);color:#ff9b9b;font-size:13px;padding:10px 12px;border-radius:9px;margin-bottom:16px}
.auth .err.show{display:block}
.auth .alt{text-align:center;font-size:13px;color:var(--muted-2);margin-top:18px}
.auth .alt a{color:var(--accent)}

/* legal / generic page */
.doc{max-width:760px;margin:0 auto;padding:64px 0}
.doc h1{font-size:34px;margin:0 0 8px}
.doc .updated{color:var(--muted-2);font-size:14px;margin-bottom:36px}
.doc h2{font-size:20px;margin:34px 0 12px}
.doc p,.doc li{color:var(--muted);font-size:15px}
.doc ul{padding-left:20px}

/* 404 */
.nf{min-height:calc(100vh - 64px);display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:48px 24px}
.nf .code{font-size:96px;font-weight:800;letter-spacing:-.04em;background:linear-gradient(135deg,var(--accent),var(--accent-2));-webkit-background-clip:text;background-clip:text;color:transparent;line-height:1}
.nf h1{font-size:26px;margin:8px 0 10px}
.nf p{color:var(--muted);margin:0 0 26px}

/* footer */
footer.site{border-top:1px solid var(--border);background:var(--bg-soft);padding:56px 0 32px;margin-top:40px}
.foot-grid{display:grid;grid-template-columns:1.6fr 1fr 1fr 1fr;gap:32px}
@media(max-width:860px){.foot-grid{grid-template-columns:1fr 1fr}}
.foot-brand p{color:var(--muted);font-size:14px;max-width:280px;margin:12px 0 0}
.foot-col h4{font-size:13px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted-2);margin:0 0 14px}
.foot-col a{display:block;color:var(--muted);font-size:14px;padding:5px 0}
.foot-col a:hover{color:var(--fg)}
.foot-bottom{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px;margin-top:44px;padding-top:24px;border-top:1px solid var(--border);color:var(--muted-2);font-size:13px}
EOF_ASSETS_V1_STYLE_CSS

cat > "${WEBROOT}/docs.html" <<'EOF_DOCS_HTML'
<!DOCTYPE html><html lang="en"><head>
<title>Docs — Northvale Cloud</title>
<meta name="description" content="Setup guides, security model, CLI reference and REST API documentation for Northvale Cloud.">
<link rel="canonical" href="https://northvale.cloud/docs.html">
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="manifest" href="/site.webmanifest"><link rel="stylesheet" href="/assets/v1/style.css">
</head><body>
<header class="site"><div class="wrap nav">
  <a class="brand" href="/">
    <svg class="logo" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg>
    Northvale Cloud
  </a>
  <nav class="nav-links">
    <a href="/features.html">Features</a>
    <a href="/pricing.html">Pricing</a>
    <a href="/docs.html">Docs</a>
    <a href="/login.html">Sign in</a>
  </nav>
  <div class="nav-cta">
    <a class="btn btn-ghost" href="/login.html">Sign in</a>
    <a class="btn btn-primary" href="/login.html">Get started</a>
    <button class="burger" aria-label="Menu">☰</button>
  </div>
</div></header>
<main>
<section class="hero" style="padding:80px 0 32px"><div class="wrap">
  <span class="eyebrow">Documentation</span>
  <h1 style="font-size:clamp(30px,5vw,44px)">Docs &amp; guides</h1>
  <p class="lead">Everything you need to set up Northvale, connect your devices, and automate with the API.</p>
</div></section>
<section class="block" style="padding-top:16px"><div class="wrap">
  <div class="grid cols-3">
    <div class="card"><h3>Getting started</h3><p>Create your workspace, install a client, and sync your first folder in under five minutes.</p></div>
    <div class="card"><h3>Desktop &amp; mobile</h3><p>Install guides and selective-sync setup for macOS, Windows, Linux, iOS and Android.</p></div>
    <div class="card"><h3>Sharing &amp; permissions</h3><p>Link options, team roles, and how access inheritance works across spaces.</p></div>
    <div class="card"><h3>Security model</h3><p>How zero-knowledge encryption, key handling, and recovery codes work under the hood.</p></div>
    <div class="card"><h3>CLI reference</h3><p>Install the <code>northvale</code> CLI and script uploads, backups, and restores.</p></div>
    <div class="card"><h3>REST API</h3><p>Authenticate, list files, and manage shares programmatically. Rate limits and examples.</p></div>
  </div>
</div></section>
</main>
<footer class="site"><div class="wrap">
  <div class="foot-grid">
    <div class="foot-brand">
      <a class="brand" href="/"><svg class="logo" viewBox="0 0 32 32" fill="none"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg> Northvale Cloud</a>
      <p>Secure cloud storage and file sync for modern teams. Your data, encrypted and available anywhere.</p>
    </div>
    <div class="foot-col"><h4>Product</h4><a href="/features.html">Features</a><a href="/pricing.html">Pricing</a><a href="/docs.html">Docs</a><a href="/login.html">Sign in</a></div>
    <div class="foot-col"><h4>Company</h4><a href="/#about">About</a><a href="/#careers">Careers</a><a href="/#blog">Blog</a><a href="mailto:hello@northvale.cloud">Contact</a></div>
    <div class="foot-col"><h4>Legal</h4><a href="/terms.html">Terms</a><a href="/privacy.html">Privacy</a><a href="/#status">Status</a></div>
  </div>
  <div class="foot-bottom"><span>© <span class="year">2026</span> Northvale Cloud. All rights reserved.</span><span>Made for teams worldwide</span></div>
</div></footer>
<script src="/assets/v1/app.js"></script></body></html>
EOF_DOCS_HTML

base64 -d > "${WEBROOT}/favicon.ico" <<'EOF_FAVICON_ICO'
AAABAAIAEBAAAAAAIADqAQAAJgAAACAgAAAAACAA7wAAABACAACJUE5HDQoaCgAAAA1JSERSAAAA
EAAAABAIBgAAAB/z/2EAAAGxSURBVHicpZMxqxNBFIW/uTvLbgybYKuVhQqvsxARO0EEm2yjlT9B
EEtBHryH3VPzJ6wUJY0/wMpGS61EC7GWGF+yk9mdazHZl40sWnjgFjvDOefee2YNwO0XmtTfeRwa
HgAZf4eThKk9y6OXd0xjbhzpcCg8zwrK6icBkH8IhHyEuAWz48BdGcB+VlBWc1wf2WyqA6nmuKyg
HMC+mRzpGkPSJbcEY6AOoAqJxG/VbScojUVI0Y68gbqJKt7D+FQ8++WAAElyIiIIYv8kr9ZwegiV
hysX4d5NSC18/AYHr0AbsEKkKZjJk6iXGPixhOt7cP9WFCzy3eE/fIGD19GohW2dj9dw7QI8LOO8
LVTjOKpw6RwUA5gvId10Ie2yKg9Xz0eybyKhSxYDzoOvd6OS1iVP4d3nKJQmUdSYmIgYCArP3sBi
BTbhZHUW4uUwg7efYO8MlJehCbGbTRMs1/D+axTvRImZPFXtJmElbr0PzkezLRssAd99SL4BV/cL
JLvvNBBoRGGajxAU1y7USn9to8HlI0RhKis4dAtm+ZgMCPG+v1rnfEzmFsxWcGjg/37n363sr3iN
7ifeAAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAtklEQVR4
nO2X0Q2AIAxEbeN+uouMobvohPpFokhtATkS431W8D0vkQTqhAzzvkvPcrI5otj8NnwbrIkwEh5j
sPQAJcFoeCjB2sLaoRZff07zBn6BvvQF63SfjYt9f1EDMfjTPBZzAykv9estTZgaSIWn7FMFcuHW
PArUhqsCiHxboPgvSDlQcveqDZRIvCJQO6aTsGYLzRv4BVi6sSCyOaL2DXgTNNgzORwg4RcBlETI
EIGo6/kBeLI5sA6PadQAAAAASUVORK5CYII=
EOF_FAVICON_ICO

cat > "${WEBROOT}/favicon.svg" <<'EOF_FAVICON_SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg>
EOF_FAVICON_SVG

cat > "${WEBROOT}/features.html" <<'EOF_FEATURES_HTML'
<!DOCTYPE html><html lang="en"><head>
<title>Features — Northvale Cloud</title>
<meta name="description" content="Encryption, selective sync, sharing controls, audit logs and native apps — everything Northvale Cloud offers.">
<link rel="canonical" href="https://northvale.cloud/features.html">
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="manifest" href="/site.webmanifest"><link rel="stylesheet" href="/assets/v1/style.css">
</head><body>
<header class="site"><div class="wrap nav">
  <a class="brand" href="/">
    <svg class="logo" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg>
    Northvale Cloud
  </a>
  <nav class="nav-links">
    <a href="/features.html">Features</a>
    <a href="/pricing.html">Pricing</a>
    <a href="/docs.html">Docs</a>
    <a href="/login.html">Sign in</a>
  </nav>
  <div class="nav-cta">
    <a class="btn btn-ghost" href="/login.html">Sign in</a>
    <a class="btn btn-primary" href="/login.html">Get started</a>
    <button class="burger" aria-label="Menu">☰</button>
  </div>
</div></header>
<main>
<section class="hero" style="padding:80px 0 40px"><div class="wrap">
  <span class="eyebrow">Features</span>
  <h1 style="font-size:clamp(30px,5vw,46px)">Built for the way teams work</h1>
  <p class="lead">From encryption to sharing controls, every part of Northvale is designed to stay out of your way.</p>
</div></section>
<section class="block" style="padding-top:24px"><div class="wrap">
  <div class="grid cols-2">
    <div class="card"><h3>Zero-knowledge encryption</h3><p>Keys are derived on your device. Northvale stores only ciphertext — a breach on our side reveals nothing about your files.</p></div>
    <div class="card"><h3>Selective sync</h3><p>Keep only what you need on each device. Pin folders offline, stream the rest on demand without filling your disk.</p></div>
    <div class="card"><h3>Smart sharing links</h3><p>Set expiry, download limits, passwords, and view-only mode per link. Revoke access in one click.</p></div>
    <div class="card"><h3>Activity &amp; audit log</h3><p>See who opened, edited, or shared a file, and when. Export the full trail for compliance.</p></div>
    <div class="card"><h3>Native apps</h3><p>Desktop clients for macOS, Windows, and Linux, plus iOS and Android — all sharing one sync engine.</p></div>
    <div class="card"><h3>Developer API</h3><p>A clean REST API and CLI to automate uploads, backups, and integrations with your own tooling.</p></div>
  </div>
</div></section>
<section class="block" style="padding-top:0"><div class="cta-band"><h2>See it on your own files</h2><p>Free for 14 days, no card required.</p><a class="btn btn-primary btn-lg" href="/login.html">Start free trial</a></div></section>
</main>
<footer class="site"><div class="wrap">
  <div class="foot-grid">
    <div class="foot-brand">
      <a class="brand" href="/"><svg class="logo" viewBox="0 0 32 32" fill="none"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg> Northvale Cloud</a>
      <p>Secure cloud storage and file sync for modern teams. Your data, encrypted and available anywhere.</p>
    </div>
    <div class="foot-col"><h4>Product</h4><a href="/features.html">Features</a><a href="/pricing.html">Pricing</a><a href="/docs.html">Docs</a><a href="/login.html">Sign in</a></div>
    <div class="foot-col"><h4>Company</h4><a href="/#about">About</a><a href="/#careers">Careers</a><a href="/#blog">Blog</a><a href="mailto:hello@northvale.cloud">Contact</a></div>
    <div class="foot-col"><h4>Legal</h4><a href="/terms.html">Terms</a><a href="/privacy.html">Privacy</a><a href="/#status">Status</a></div>
  </div>
  <div class="foot-bottom"><span>© <span class="year">2026</span> Northvale Cloud. All rights reserved.</span><span>Made for teams worldwide</span></div>
</div></footer>
<script src="/assets/v1/app.js"></script></body></html>
EOF_FEATURES_HTML

cat > "${WEBROOT}/index.html" <<'EOF_INDEX_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Northvale Cloud — Secure file storage &amp; sync for teams</title>
<meta name="description" content="Northvale Cloud gives your team fast, encrypted file storage and sync across every device. Share securely, control access, and keep everything in one place.">
<link rel="canonical" href="https://northvale.cloud/">
<meta property="og:title" content="Northvale Cloud — Secure file storage &amp; sync">
<meta property="og:description" content="Fast, encrypted cloud storage and sync for modern teams.">
<meta property="og:type" content="website">
<meta property="og:url" content="https://northvale.cloud/">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/v1/style.css">
</head>
<body>
<header class="site"><div class="wrap nav">
  <a class="brand" href="/">
    <svg class="logo" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg>
    Northvale Cloud
  </a>
  <nav class="nav-links">
    <a href="/features.html">Features</a>
    <a href="/pricing.html">Pricing</a>
    <a href="/docs.html">Docs</a>
    <a href="/login.html">Sign in</a>
  </nav>
  <div class="nav-cta">
    <a class="btn btn-ghost" href="/login.html">Sign in</a>
    <a class="btn btn-primary" href="/login.html">Get started</a>
    <button class="burger" aria-label="Menu">☰</button>
  </div>
</div></header>

<main>
<section class="hero"><div class="wrap">
  <span class="eyebrow">New · Team spaces &amp; granular sharing</span>
  <h1>Your files, everywhere.<br>Secure by default.</h1>
  <p class="lead">Northvale Cloud keeps your team's documents encrypted, synced, and instantly available — on any device, in any place, without the friction.</p>
  <div class="hero-cta">
    <a class="btn btn-primary btn-lg" href="/login.html">Start free trial</a>
    <a class="btn btn-ghost btn-lg" href="/features.html">See how it works</a>
  </div>
  <div class="hero-note">14-day trial · No card required · 10 GB free forever</div>
</div></section>

<div class="logos"><div class="wrap">
  <span>Vireon</span><span>Halbrook</span><span>Ostara</span><span>Kettleman</span><span>Norlund</span>
</div></div>

<section class="block"><div class="wrap">
  <div class="section-head">
    <h2>Everything your files need</h2>
    <p>One workspace for storage, sync, and sharing — built for speed and privacy.</p>
  </div>
  <div class="grid cols-3">
    <div class="card"><div class="ico"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 3l8 4v5c0 5-3.4 7.7-8 9-4.6-1.3-8-4-8-9V7z"/></svg></div><h3>End-to-end encryption</h3><p>Files are encrypted on your device before they ever leave it. Only you and the people you choose hold the keys.</p></div>
    <div class="card"><div class="ico"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 12a8 8 0 0 1 8-8v8z"/><circle cx="12" cy="12" r="8"/></svg></div><h3>Real-time sync</h3><p>Changes propagate to every device in milliseconds. Work offline and Northvale reconciles automatically when you reconnect.</p></div>
    <div class="card"><div class="ico"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M16 8a4 4 0 1 0-8 0M6 8h12l1 12H5z"/></svg></div><h3>Granular access</h3><p>Share a single file or an entire space. Set view-only, expiry dates, and password protection per link.</p></div>
    <div class="card"><div class="ico"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 8v4l3 2"/><circle cx="12" cy="12" r="9"/></svg></div><h3>Version history</h3><p>Every save is a restore point. Roll any file back up to 180 days — no accidental overwrite is ever final.</p></div>
    <div class="card"><div class="ico"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18"/></svg></div><h3>Team spaces</h3><p>Give each project its own shared home with roles, activity logs, and per-member quotas.</p></div>
    <div class="card"><div class="ico"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 17l6-6 4 4 6-8"/></svg></div><h3>Fast everywhere</h3><p>A global edge network puts your data close to you. Uploads and previews stay quick from anywhere on the planet.</p></div>
  </div>
</div></section>

<section class="block" id="security" style="background:var(--bg-soft);border-top:1px solid var(--border);border-bottom:1px solid var(--border)"><div class="wrap">
  <div class="grid cols-2" style="align-items:center;gap:48px">
    <div>
      <span class="eyebrow">Security</span>
      <h2 style="font-size:34px;letter-spacing:-.02em;margin:14px 0 16px">Privacy isn't a setting. It's the default.</h2>
      <p style="color:var(--muted);font-size:16px">We can't read your files, and neither can anyone else. Northvale uses AES-256 at rest, TLS 1.3 in transit, and zero-knowledge sharing links. Independent audits published every year.</p>
      <ul style="list-style:none;padding:0;margin:22px 0 0;display:flex;flex-direction:column;gap:12px;color:var(--muted)">
        <li>✓ AES-256 encryption at rest</li>
        <li>✓ SSO, SCIM &amp; 2FA on every plan</li>
        <li>✓ GDPR-ready · data residency options</li>
      </ul>
    </div>
    <div class="card" style="padding:32px">
      <div style="font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;color:var(--muted);line-height:1.9">
        <div style="color:var(--accent-2)">$ northvale push ./reports</div>
        <div>→ encrypting 42 files (AES-256)…</div>
        <div>→ uploading via edge/fra-1…</div>
        <div style="color:var(--accent)">✓ synced 42 files · 318 MB · 1.4s</div>
      </div>
    </div>
  </div>
</div></section>

<section class="block"><div class="cta-band">
  <h2>Ready to move your team to Northvale?</h2>
  <p>Start with 10 GB free. Upgrade whenever you're ready.</p>
  <a class="btn btn-primary btn-lg" href="/login.html">Create free account</a>
</div></section>
</main>

<footer class="site"><div class="wrap">
  <div class="foot-grid">
    <div class="foot-brand">
      <a class="brand" href="/"><svg class="logo" viewBox="0 0 32 32" fill="none"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg> Northvale Cloud</a>
      <p>Secure cloud storage and file sync for modern teams. Your data, encrypted and available anywhere.</p>
    </div>
    <div class="foot-col"><h4>Product</h4><a href="/features.html">Features</a><a href="/pricing.html">Pricing</a><a href="/docs.html">Docs</a><a href="/login.html">Sign in</a></div>
    <div class="foot-col"><h4>Company</h4><a href="/#about">About</a><a href="/#careers">Careers</a><a href="/#blog">Blog</a><a href="mailto:hello@northvale.cloud">Contact</a></div>
    <div class="foot-col"><h4>Legal</h4><a href="/terms.html">Terms</a><a href="/privacy.html">Privacy</a><a href="/#status">Status</a></div>
  </div>
  <div class="foot-bottom"><span>© <span class="year">2026</span> Northvale Cloud. All rights reserved.</span><span>Made for teams worldwide</span></div>
</div></footer>
<script src="/assets/v1/app.js"></script>
</body>
</html>
EOF_INDEX_HTML

cat > "${WEBROOT}/login.html" <<'EOF_LOGIN_HTML'
<!DOCTYPE html><html lang="en"><head>
<title>Sign in — Northvale Cloud</title>
<meta name="description" content="Sign in to your Northvale Cloud account.">
<meta name="robots" content="noindex">
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon.ico" sizes="any">
<link rel="manifest" href="/site.webmanifest"><link rel="stylesheet" href="/assets/v1/style.css">
</head><body>
<header class="site"><div class="wrap nav">
  <a class="brand" href="/">
    <svg class="logo" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg>
    Northvale Cloud
  </a>
  <nav class="nav-links">
    <a href="/features.html">Features</a>
    <a href="/pricing.html">Pricing</a>
    <a href="/docs.html">Docs</a>
    <a href="/login.html">Sign in</a>
  </nav>
  <div class="nav-cta">
    <a class="btn btn-ghost" href="/login.html">Sign in</a>
    <a class="btn btn-primary" href="/login.html">Get started</a>
    <button class="burger" aria-label="Menu">☰</button>
  </div>
</div></header>
<main class="auth-shell"><div class="auth">
  <div class="tabs"><button id="tab-signin" class="active">Sign in</button><button id="tab-signup">Sign up</button></div>
  <h1 id="auth-title">Welcome back</h1>
  <p class="sub">Access your files from anywhere.</p>
  <div class="err" id="auth-err"></div>
  <form id="auth-form" autocomplete="on">
    <div class="field" id="field-name" style="display:none"><label for="name">Full name</label><input id="name" type="text" placeholder="Jane Doe"></div>
    <div class="field"><label for="email">Email</label><input id="email" type="email" placeholder="you@company.com" required></div>
    <div class="field"><label for="password">Password</label><input id="password" type="password" placeholder="••••••••" required></div>
    <button class="btn btn-primary" id="auth-submit" type="submit">Sign in</button>
  </form>
  <p class="alt"><a href="/#reset">Forgot your password?</a></p>
</div></main>
<script src="/assets/v1/app.js"></script></body></html>
EOF_LOGIN_HTML

cat > "${WEBROOT}/pricing.html" <<'EOF_PRICING_HTML'
<!DOCTYPE html><html lang="en"><head>
<title>Pricing — Northvale Cloud</title>
<meta name="description" content="Free, Pro and Enterprise plans for secure cloud storage. Start free, upgrade as your team grows.">
<link rel="canonical" href="https://northvale.cloud/pricing.html">
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="manifest" href="/site.webmanifest"><link rel="stylesheet" href="/assets/v1/style.css">
</head><body>
<header class="site"><div class="wrap nav">
  <a class="brand" href="/">
    <svg class="logo" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg>
    Northvale Cloud
  </a>
  <nav class="nav-links">
    <a href="/features.html">Features</a>
    <a href="/pricing.html">Pricing</a>
    <a href="/docs.html">Docs</a>
    <a href="/login.html">Sign in</a>
  </nav>
  <div class="nav-cta">
    <a class="btn btn-ghost" href="/login.html">Sign in</a>
    <a class="btn btn-primary" href="/login.html">Get started</a>
    <button class="burger" aria-label="Menu">☰</button>
  </div>
</div></header>
<main>
<section class="hero" style="padding:80px 0 40px"><div class="wrap">
  <span class="eyebrow">Pricing</span>
  <h1 style="font-size:clamp(30px,5vw,46px)">Simple plans that scale</h1>
  <p class="lead">Start free. Upgrade when your team grows. Cancel anytime.</p>
</div></section>
<section class="block" style="padding-top:24px"><div class="wrap">
  <div class="plans">
    <div class="plan"><span class="tag">Free</span><div class="price">$0<span>/mo</span></div><p style="color:var(--muted);margin:0">For individuals getting started.</p>
      <ul><li>✓ 10 GB storage</li><li>✓ 2 devices</li><li>✓ 30-day version history</li><li>✓ Basic sharing links</li></ul>
      <a class="btn btn-ghost" href="/login.html">Get started</a></div>
    <div class="plan featured"><span class="tag">Pro</span><div class="price">$8<span>/user/mo</span></div><p style="color:var(--muted);margin:0">For teams that need control.</p>
      <ul><li>✓ 2 TB per user</li><li>✓ Unlimited devices</li><li>✓ 180-day version history</li><li>✓ Password &amp; expiry links</li><li>✓ SSO &amp; 2FA</li></ul>
      <a class="btn btn-primary" href="/login.html">Start free trial</a></div>
    <div class="plan"><span class="tag">Enterprise</span><div class="price">Custom</div><p style="color:var(--muted);margin:0">For organizations at scale.</p>
      <ul><li>✓ Unlimited storage</li><li>✓ Data residency options</li><li>✓ SCIM provisioning</li><li>✓ Audit exports &amp; SLA</li><li>✓ Dedicated support</li></ul>
      <a class="btn btn-ghost" href="mailto:sales@northvale.cloud">Contact sales</a></div>
  </div>
</div></section>
</main>
<footer class="site"><div class="wrap">
  <div class="foot-grid">
    <div class="foot-brand">
      <a class="brand" href="/"><svg class="logo" viewBox="0 0 32 32" fill="none"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg> Northvale Cloud</a>
      <p>Secure cloud storage and file sync for modern teams. Your data, encrypted and available anywhere.</p>
    </div>
    <div class="foot-col"><h4>Product</h4><a href="/features.html">Features</a><a href="/pricing.html">Pricing</a><a href="/docs.html">Docs</a><a href="/login.html">Sign in</a></div>
    <div class="foot-col"><h4>Company</h4><a href="/#about">About</a><a href="/#careers">Careers</a><a href="/#blog">Blog</a><a href="mailto:hello@northvale.cloud">Contact</a></div>
    <div class="foot-col"><h4>Legal</h4><a href="/terms.html">Terms</a><a href="/privacy.html">Privacy</a><a href="/#status">Status</a></div>
  </div>
  <div class="foot-bottom"><span>© <span class="year">2026</span> Northvale Cloud. All rights reserved.</span><span>Made for teams worldwide</span></div>
</div></footer>
<script src="/assets/v1/app.js"></script></body></html>
EOF_PRICING_HTML

cat > "${WEBROOT}/privacy.html" <<'EOF_PRIVACY_HTML'
<!DOCTYPE html><html lang="en"><head>
<title>Privacy Policy — Northvale Cloud</title>
<meta name="description" content="Privacy Policy for Northvale Cloud.">
<link rel="canonical" href="https://northvale.cloud/privacy.html">
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="manifest" href="/site.webmanifest"><link rel="stylesheet" href="/assets/v1/style.css">
</head><body>
<header class="site"><div class="wrap nav">
  <a class="brand" href="/">
    <svg class="logo" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg>
    Northvale Cloud
  </a>
  <nav class="nav-links">
    <a href="/features.html">Features</a>
    <a href="/pricing.html">Pricing</a>
    <a href="/docs.html">Docs</a>
    <a href="/login.html">Sign in</a>
  </nav>
  <div class="nav-cta">
    <a class="btn btn-ghost" href="/login.html">Sign in</a>
    <a class="btn btn-primary" href="/login.html">Get started</a>
    <button class="burger" aria-label="Menu">☰</button>
  </div>
</div></header>
<main><div class="doc">
<h1>Privacy Policy</h1>
<div class="updated">Last updated: January 2, 2026</div>
<p>This Privacy Policy explains what information Northvale Cloud collects and how we use it. We designed the Service to collect as little as possible.</p>
<h2>Information we collect</h2><ul><li>Account data: your email address and, for paid plans, billing details processed by our payment provider.</li><li>Usage metadata: file sizes, timestamps, and device identifiers needed to sync and secure your data.</li></ul>
<h2>What we cannot see</h2><p>Your file contents are encrypted on your device before upload. We store ciphertext only and cannot read your files.</p>
<h2>How we use data</h2><p>We use collected data to operate the Service, prevent abuse, provide support, and meet legal obligations. We do not sell personal data.</p>
<h2>Data retention</h2><p>Account data is kept while your account is active. Deleted files are purged from all replicas within 30 days.</p>
<h2>Your rights</h2><p>You may access, export, or delete your data at any time. To exercise these rights, contact <a href="mailto:privacy@northvale.cloud">privacy@northvale.cloud</a>.</p>
<h2>International transfers</h2><p>Enterprise customers may choose a data residency region. Standard accounts are hosted in the EU.</p>
</div></main>
<footer class="site"><div class="wrap">
  <div class="foot-grid">
    <div class="foot-brand">
      <a class="brand" href="/"><svg class="logo" viewBox="0 0 32 32" fill="none"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg> Northvale Cloud</a>
      <p>Secure cloud storage and file sync for modern teams. Your data, encrypted and available anywhere.</p>
    </div>
    <div class="foot-col"><h4>Product</h4><a href="/features.html">Features</a><a href="/pricing.html">Pricing</a><a href="/docs.html">Docs</a><a href="/login.html">Sign in</a></div>
    <div class="foot-col"><h4>Company</h4><a href="/#about">About</a><a href="/#careers">Careers</a><a href="/#blog">Blog</a><a href="mailto:hello@northvale.cloud">Contact</a></div>
    <div class="foot-col"><h4>Legal</h4><a href="/terms.html">Terms</a><a href="/privacy.html">Privacy</a><a href="/#status">Status</a></div>
  </div>
  <div class="foot-bottom"><span>© <span class="year">2026</span> Northvale Cloud. All rights reserved.</span><span>Made for teams worldwide</span></div>
</div></footer>
<script src="/assets/v1/app.js"></script></body></html>
EOF_PRIVACY_HTML

cat > "${WEBROOT}/robots.txt" <<'EOF_ROBOTS_TXT'
User-agent: *
Allow: /
Disallow: /login.html

Sitemap: https://northvale.cloud/sitemap.xml
EOF_ROBOTS_TXT

cat > "${WEBROOT}/site.webmanifest" <<'EOF_SITE_WEBMANIFEST'
{
  "name": "Northvale Cloud",
  "short_name": "Northvale",
  "description": "Secure file storage and sync for teams.",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0b0d12",
  "theme_color": "#4f8cff",
  "icons": [
    { "src": "/favicon.svg", "sizes": "any", "type": "image/svg+xml" },
    { "src": "/apple-touch-icon.png", "sizes": "180x180", "type": "image/png" }
  ]
}
EOF_SITE_WEBMANIFEST

cat > "${WEBROOT}/sitemap.xml" <<'EOF_SITEMAP_XML'
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://northvale.cloud/</loc><changefreq>weekly</changefreq><priority>1.0</priority></url>
  <url><loc>https://northvale.cloud/features.html</loc><changefreq>monthly</changefreq><priority>0.8</priority></url>
  <url><loc>https://northvale.cloud/pricing.html</loc><changefreq>monthly</changefreq><priority>0.8</priority></url>
  <url><loc>https://northvale.cloud/docs.html</loc><changefreq>monthly</changefreq><priority>0.6</priority></url>
  <url><loc>https://northvale.cloud/terms.html</loc><changefreq>yearly</changefreq><priority>0.3</priority></url>
  <url><loc>https://northvale.cloud/privacy.html</loc><changefreq>yearly</changefreq><priority>0.3</priority></url>
</urlset>
EOF_SITEMAP_XML

cat > "${WEBROOT}/terms.html" <<'EOF_TERMS_HTML'
<!DOCTYPE html><html lang="en"><head>
<title>Terms of Service — Northvale Cloud</title>
<meta name="description" content="Terms of Service for Northvale Cloud.">
<link rel="canonical" href="https://northvale.cloud/terms.html">
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="icon" href="/favicon.ico" sizes="any"><link rel="manifest" href="/site.webmanifest"><link rel="stylesheet" href="/assets/v1/style.css">
</head><body>
<header class="site"><div class="wrap nav">
  <a class="brand" href="/">
    <svg class="logo" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg>
    Northvale Cloud
  </a>
  <nav class="nav-links">
    <a href="/features.html">Features</a>
    <a href="/pricing.html">Pricing</a>
    <a href="/docs.html">Docs</a>
    <a href="/login.html">Sign in</a>
  </nav>
  <div class="nav-cta">
    <a class="btn btn-ghost" href="/login.html">Sign in</a>
    <a class="btn btn-primary" href="/login.html">Get started</a>
    <button class="burger" aria-label="Menu">☰</button>
  </div>
</div></header>
<main><div class="doc">
<h1>Terms of Service</h1>
<div class="updated">Last updated: January 2, 2026</div>
<p>These Terms of Service govern your access to and use of Northvale Cloud ("the Service"). By creating an account or using the Service, you agree to these terms.</p>
<h2>1. Accounts</h2><p>You are responsible for safeguarding your account credentials and for all activity that occurs under your account. Notify us promptly of any unauthorized use.</p>
<h2>2. Acceptable use</h2><p>You agree not to use the Service to store or distribute unlawful content, infringe intellectual property, or attempt to disrupt the integrity or performance of the Service.</p>
<h2>3. Your content</h2><p>You retain all rights to the files you upload. We process your content solely to provide the Service. Because content is encrypted, we cannot access it except as metadata required for delivery.</p>
<h2>4. Subscriptions</h2><p>Paid plans renew automatically until cancelled. You may cancel at any time; access continues until the end of the current billing period.</p>
<h2>5. Termination</h2><p>We may suspend or terminate accounts that violate these terms. You may delete your account at any time from account settings.</p>
<h2>6. Disclaimer</h2><p>The Service is provided "as is" without warranties of any kind to the maximum extent permitted by law.</p>
<h2>7. Contact</h2><p>Questions about these terms may be sent to <a href="mailto:legal@northvale.cloud">legal@northvale.cloud</a>.</p>
</div></main>
<footer class="site"><div class="wrap">
  <div class="foot-grid">
    <div class="foot-brand">
      <a class="brand" href="/"><svg class="logo" viewBox="0 0 32 32" fill="none"><rect width="32" height="32" rx="8" fill="#4f8cff"/><path d="M10 20.5h9a4.5 4.5 0 0 0 .6-8.96A6 6 0 0 0 8.2 13.2 4 4 0 0 0 10 20.5Z" fill="#fff"/></svg> Northvale Cloud</a>
      <p>Secure cloud storage and file sync for modern teams. Your data, encrypted and available anywhere.</p>
    </div>
    <div class="foot-col"><h4>Product</h4><a href="/features.html">Features</a><a href="/pricing.html">Pricing</a><a href="/docs.html">Docs</a><a href="/login.html">Sign in</a></div>
    <div class="foot-col"><h4>Company</h4><a href="/#about">About</a><a href="/#careers">Careers</a><a href="/#blog">Blog</a><a href="mailto:hello@northvale.cloud">Contact</a></div>
    <div class="foot-col"><h4>Legal</h4><a href="/terms.html">Terms</a><a href="/privacy.html">Privacy</a><a href="/#status">Status</a></div>
  </div>
  <div class="foot-bottom"><span>© <span class="year">2026</span> Northvale Cloud. All rights reserved.</span><span>Made for teams worldwide</span></div>
</div></footer>
<script src="/assets/v1/app.js"></script></body></html>
EOF_TERMS_HTML

}

# >>> SITE-mona BEGIN (сгенерировано tools/embed-site.py, не править руками — правьте sites/mona/)
write_html_mona() {
    mkdir -p "${WEBROOT}" "${WEBROOT}/assets/t1"
cat > "${WEBROOT}/404.html" <<'EOF_404_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Page not found — Tarnex</title>
<meta name="description" content="The page you are looking for does not exist.">
<meta name="theme-color" content="#101214">
<meta property="og:title" content="Page not found — Tarnex">
<meta property="og:description" content="The page you are looking for does not exist.">
<meta property="og:type" content="website">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/t1/style.css">
</head>
<body>
<header class="top"><div class="wrap nav">
  <a class="brand" href="/"><svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="9" fill="#ffb454"/><path d="M9 10h14M16 10v13" stroke="#1a1205" stroke-width="3.4" stroke-linecap="round"/></svg>Tarnex</a>
  <nav class="links"><a href="/">Home</a><a href="/how-it-works.html">How it works</a><a href="/pricing.html">Pricing</a><a href="/help.html">Help</a><a href="/login.html">Sign in</a></nav>
  <a class="btn pri" href="/login.html">Send a file</a>
  <button class="burger" aria-label="Menu">&#9776;</button>
</div></header>
<main><div class="wrap err">
<div class="n">404</div>
<h1 style="font-size:30px">This link is gone</h1>
<p class="lead" style="margin-bottom:26px">It may have expired, been revoked or never existed.</p>
<a class="btn pri lg" href="/">Back to home</a>
</div></main>
<footer><div class="wrap">
  <div>&copy; <span id="yr">2026</span> Tarnex. Send it once.</div>
  <div><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href="/help.html">Help</a></div>
</div></footer>
<script src="/assets/t1/app.js" defer></script>
</body>
</html>
EOF_404_HTML
base64 -d > "${WEBROOT}/apple-touch-icon.png" <<'EOF_APPLE_TOUCH_ICON_PNG'
iVBORw0KGgoAAAANSUhEUgAAALQAAAC0CAYAAAA9zQYyAAACe0lEQVR42u3TwQ2DMBQFQV9oIMfU
Ran0B6KDEIXIWsbSNvD+eIzQ27d11/WGByr4HsCAQyy4IRbcIAtskPVE2I6qDGyHVAK14ykD28GU
QO1IysB2GGVQO4gyqB1CGdQOoAxqwyuD2uDKoDa0MqgNrBRq4yoD2rDKoDaoUqiNqQxoQyqD2oBK
oTaeMqANpxRqoykD2mBKoTaWMqANpRRqIwloaUbQBlIKtXEEtDQjaMMohdooAloCWroZtEGUQm0M
AS0BLQEtAS2gJaAloCWgpQ9AG0Ip1EYQ0BLQ9/d+LfoyoIEGGmiggQYaaKCBFtBAAw000EADDTTQ
QAMNNNACGmiggQYaaKCBBhpooIEGWkADDTTQQAMNNNBAAw000EALaKCBBhpooIH2iWq4gAYaaKCB
FtBAAy2ggQYaaKCBtivQQAtooIEW0EADDTTQQAtooIE2BNBAC2iggQYaaKAFNNBAC2iggQYaaKCB
BhpoAQ000AIaaKCBBhpooIEGWkADDbSABhpooIEGGmiggRbQQAMtoIEGGmiggQYaaKAFNNBAC2ig
gQYaaKCBBhpoAQ000AIaaKCBBhpoAQ20gAYaaAENNNBAAw20gAYaaAEdAX0+QwCdwQw00EALaKCB
BhpooAW0gDaIgJaAloCWLoCGWinMQAtoCWjpT6ChVgoz0AJamhk01EphBlpASzODhlopzEArBxpq
pTADrRxoqJXCDLRyoKFWCjPUymEGWjnQUCuFGWrlMAOtHGiolcIMtXKYoVYOM9TKYYZaOcxQK4cZ
auUwQ60cZrCVgwy1kpjBVg4y1EpiBluj/hwZZLAFMtyCGG5BDDjAHvig/vwdoTM7tM97i5AAAAAA
SUVORK5CYII=
EOF_APPLE_TOUCH_ICON_PNG
cat > "${WEBROOT}/assets/t1/app.js" <<'EOF_ASSETS_T1_APP_JS'
(function(){
  var b=document.querySelector('.burger'),l=document.querySelector('.links');
  if(b&&l)b.addEventListener('click',function(){l.classList.toggle('open')});
  var y=document.getElementById('yr');if(y)y.textContent=new Date().getFullYear();
  var drop=document.getElementById('drop'),inp=document.getElementById('file'),list=document.getElementById('picked'),note=document.getElementById('note');
  if(drop&&inp){
    var size=function(n){return n<1048576?(n/1024).toFixed(0)+' KB':(n/1048576).toFixed(1)+' MB'};
    var show=function(files){
      list.innerHTML='';
      Array.prototype.slice.call(files,0,8).forEach(function(f){
        var li=document.createElement('li'),a=document.createElement('span'),s=document.createElement('span');
        a.textContent=f.name;s.textContent=size(f.size);li.appendChild(a);li.appendChild(s);list.appendChild(li);
      });
      note.textContent=files.length?'Sign in to create your private link.':'';
    };
    ['dragenter','dragover'].forEach(function(e){drop.addEventListener(e,function(ev){ev.preventDefault();drop.classList.add('over')})});
    ['dragleave','drop'].forEach(function(e){drop.addEventListener(e,function(ev){ev.preventDefault();drop.classList.remove('over')})});
    drop.addEventListener('drop',function(ev){show(ev.dataTransfer.files)});
    inp.addEventListener('change',function(){show(inp.files)});
  }
  var f=document.getElementById('login');
  if(f)f.addEventListener('submit',function(ev){ev.preventDefault();document.getElementById('msg').textContent='Incorrect email or password.'});
})();
EOF_ASSETS_T1_APP_JS
cat > "${WEBROOT}/assets/t1/style.css" <<'EOF_ASSETS_T1_STYLE_CSS'
:root{--bg:#101214;--bg2:#15181b;--card:#1b1f23;--line:#2a2f35;--tx:#e9e7e2;--mut:#9aa0a6;--acc:#ffb454;--acc2:#5ad1c4;--r:14px}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--tx);font:16px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased}
a{color:var(--acc);text-decoration:none}a:hover{text-decoration:underline}
.wrap{max-width:1040px;margin:0 auto;padding:0 22px}
header.top{position:sticky;top:0;z-index:20;background:rgba(16,18,20,.88);backdrop-filter:blur(10px);border-bottom:1px solid var(--line)}
.nav{display:flex;align-items:center;justify-content:space-between;height:64px;gap:18px}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;font-size:20px;color:var(--tx);letter-spacing:.2px}
.brand:hover{text-decoration:none}.brand svg{width:28px;height:28px}
.links{display:flex;gap:22px}.links a{color:var(--mut);font-size:15px}.links a:hover,.links a.on{color:var(--tx);text-decoration:none}
.btn{display:inline-block;border:1px solid var(--line);color:var(--tx);padding:9px 18px;border-radius:999px;font-weight:600;font-size:15px;background:transparent;cursor:pointer;font-family:inherit}
.btn:hover{border-color:#444b53;text-decoration:none}
.btn.pri{background:var(--acc);border-color:var(--acc);color:#1a1205}.btn.pri:hover{filter:brightness(1.07)}
.btn.lg{padding:13px 26px;font-size:16px}
.burger{display:none;background:none;border:0;color:var(--tx);font-size:24px;cursor:pointer}
.hero{padding:76px 0 40px;text-align:center}
.tag{display:inline-block;color:var(--acc2);border:1px solid #23413f;background:#112220;padding:4px 14px;border-radius:999px;font-size:13px;margin-bottom:22px}
h1{font-size:clamp(34px,6vw,58px);line-height:1.08;margin:0 0 18px;letter-spacing:-.8px}
h1 em{font-style:normal;color:var(--acc)}
.lead{color:var(--mut);font-size:19px;max-width:640px;margin:0 auto 34px}
.drop{max-width:640px;margin:0 auto;background:var(--card);border:1.5px dashed #3a4148;border-radius:20px;padding:42px 26px;transition:.15s}
.drop.over{border-color:var(--acc);background:#201d17}
.drop strong{display:block;font-size:20px;margin-bottom:6px}.drop p{margin:0 0 20px;color:var(--mut);font-size:15px}
.drop input{display:none}
#picked{list-style:none;padding:0;margin:18px 0 0;text-align:left;font-size:14px;color:var(--mut)}
#picked li{display:flex;justify-content:space-between;padding:8px 12px;border:1px solid var(--line);border-radius:10px;margin-top:8px;background:var(--bg2)}
#note{margin-top:16px;font-size:14px;color:var(--acc2);min-height:20px}
.opts{display:flex;gap:10px;justify-content:center;flex-wrap:wrap;margin-top:22px;color:var(--mut);font-size:13px}
.opts span{border:1px solid var(--line);padding:4px 12px;border-radius:999px}
section.blk{padding:64px 0;border-top:1px solid var(--line)}
section.blk h2{font-size:30px;margin:0 0 10px;letter-spacing:-.4px}.sub{color:var(--mut);margin:0 0 34px;max-width:620px}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}
.card{background:var(--card);border:1px solid var(--line);border-radius:var(--r);padding:24px}
.card h3{margin:0 0 8px;font-size:18px}.card p{margin:0;color:var(--mut);font-size:15px}
.ico{width:38px;height:38px;border-radius:10px;background:#2a2314;color:var(--acc);display:grid;place-items:center;font-weight:700;margin-bottom:14px}
.steps{counter-reset:s;display:grid;grid-template-columns:repeat(3,1fr);gap:18px}
.steps .card{position:relative;padding-top:46px}
.steps .card:before{counter-increment:s;content:counter(s);position:absolute;top:16px;left:22px;color:var(--acc);font-weight:700;font-size:20px}
.price{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}
.price .card.hot{border-color:var(--acc)}.price .amt{font-size:38px;font-weight:700;margin:10px 0}
.price .amt small{font-size:15px;color:var(--mut);font-weight:400}
.price ul{list-style:none;padding:0;margin:14px 0 22px;color:var(--mut);font-size:15px}.price li{padding:5px 0}.price li:before{content:"✓ ";color:var(--acc2)}
.faq details{border:1px solid var(--line);border-radius:12px;background:var(--card);padding:14px 18px;margin-bottom:10px}
.faq summary{cursor:pointer;font-weight:600}.faq p{color:var(--mut);margin:10px 0 2px}
.form{max-width:400px;margin:70px auto;background:var(--card);border:1px solid var(--line);border-radius:18px;padding:30px}
.form h1{font-size:28px;margin:0 0 6px}.form label{display:block;margin:16px 0 6px;color:var(--mut);font-size:14px}
.form input{width:100%;background:var(--bg2);border:1px solid var(--line);border-radius:10px;color:var(--tx);padding:11px 13px;font-size:15px;font-family:inherit}
.form input:focus{outline:none;border-color:var(--acc)}.form .btn{width:100%;margin-top:22px}
.msg{margin-top:14px;font-size:14px;color:#ff8f7a;min-height:20px}
.doc{max-width:760px;padding:56px 0}.doc h1{font-size:36px}.doc h2{margin-top:34px;font-size:21px}.doc p,.doc li{color:#c9c7c1}
.err{text-align:center;padding:110px 0}.err .n{font-size:96px;font-weight:800;color:var(--acc);line-height:1}
footer{border-top:1px solid var(--line);padding:30px 0;color:var(--mut);font-size:14px;margin-top:20px}
footer .wrap{display:flex;justify-content:space-between;gap:20px;flex-wrap:wrap}footer a{color:var(--mut);margin-left:18px}
@media(max-width:820px){.grid,.steps,.price{grid-template-columns:1fr}.links{display:none;position:absolute;top:64px;left:0;right:0;background:var(--bg2);flex-direction:column;padding:16px 22px;border-bottom:1px solid var(--line)}.links.open{display:flex}.burger{display:block}.nav .btn.pri{display:none}}
EOF_ASSETS_T1_STYLE_CSS
base64 -d > "${WEBROOT}/favicon.ico" <<'EOF_FAVICON_ICO'
AAABAAEAICAAAAEAIACqAAAAFgAAAIlQTkcNChoKAAAADUlIRFIAAAAgAAAAIAgGAAAAc3p69AAA
AHFJREFUeNrt17sJACAMBNA0LmDpXI7qftrZKBKi+SAnpBPuFYI5IsbprXbJkPRIA5+AtMJZCO3w
I8IqfIuwDl8QALgCvMIngnOp5CQeAP4AcGCqjxAAAAD4G3DzI94CsJDEAbiv5SGKSYhqFqKcWtfz
ASPaLNPEHsBPAAAAAElFTkSuQmCC
EOF_FAVICON_ICO
cat > "${WEBROOT}/favicon.svg" <<'EOF_FAVICON_SVG'
<svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="9" fill="#ffb454"/><path d="M9 10h14M16 10v13" stroke="#1a1205" stroke-width="3.4" stroke-linecap="round"/></svg>
EOF_FAVICON_SVG
cat > "${WEBROOT}/help.html" <<'EOF_HELP_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Help — Tarnex</title>
<meta name="description" content="Answers to common questions about links, expiry and downloads.">
<meta name="theme-color" content="#101214">
<meta property="og:title" content="Help — Tarnex">
<meta property="og:description" content="Answers to common questions about links, expiry and downloads.">
<meta property="og:type" content="website">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/t1/style.css">
</head>
<body>
<header class="top"><div class="wrap nav">
  <a class="brand" href="/"><svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="9" fill="#ffb454"/><path d="M9 10h14M16 10v13" stroke="#1a1205" stroke-width="3.4" stroke-linecap="round"/></svg>Tarnex</a>
  <nav class="links"><a href="/">Home</a><a href="/how-it-works.html">How it works</a><a href="/pricing.html">Pricing</a><a href="/help.html" class=on>Help</a><a href="/login.html">Sign in</a></nav>
  <a class="btn pri" href="/login.html">Send a file</a>
  <button class="burger" aria-label="Menu">&#9776;</button>
</div></header>
<main><div class="wrap doc faq">
<h1>Help</h1>
<p class="sub">Quick answers to the things people ask most.</p>
<details open><summary>How long does a link last?</summary><p>You choose: from one hour up to the limit of your plan. After that the link stops working and the file is deleted.</p></details>
<details><summary>Can I cancel a link before it expires?</summary><p>Yes. Sign in, open your transfers and revoke the link. The file is removed immediately.</p></details>
<details><summary>Do recipients need an account?</summary><p>No. They open the link and download. A passcode is only requested if you set one.</p></details>
<details><summary>What is the maximum file size?</summary><p>2 GB on Free and 20 GB on Pro. Larger transfers can be split into several links.</p></details>
<details><summary>A download link says it is no longer available.</summary><p>It has expired, reached its download limit or was revoked by the sender. Ask the sender for a new link.</p></details>
</div></main>
<footer><div class="wrap">
  <div>&copy; <span id="yr">2026</span> Tarnex. Send it once.</div>
  <div><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href="/help.html">Help</a></div>
</div></footer>
<script src="/assets/t1/app.js" defer></script>
</body>
</html>
EOF_HELP_HTML
cat > "${WEBROOT}/how-it-works.html" <<'EOF_HOW_IT_WORKS_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>How it works — Tarnex</title>
<meta name="description" content="Three steps: upload, set the rules, share the link.">
<meta name="theme-color" content="#101214">
<meta property="og:title" content="How it works — Tarnex">
<meta property="og:description" content="Three steps: upload, set the rules, share the link.">
<meta property="og:type" content="website">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/t1/style.css">
</head>
<body>
<header class="top"><div class="wrap nav">
  <a class="brand" href="/"><svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="9" fill="#ffb454"/><path d="M9 10h14M16 10v13" stroke="#1a1205" stroke-width="3.4" stroke-linecap="round"/></svg>Tarnex</a>
  <nav class="links"><a href="/">Home</a><a href="/how-it-works.html" class=on>How it works</a><a href="/pricing.html">Pricing</a><a href="/help.html">Help</a><a href="/login.html">Sign in</a></nav>
  <a class="btn pri" href="/login.html">Send a file</a>
  <button class="burger" aria-label="Menu">&#9776;</button>
</div></header>
<main><div class="wrap doc">
<h1>How it works</h1>
<p class="sub">Sending a file takes less time than writing the email about it.</p>
<div class="steps">
  <div class="card"><h3>Upload</h3><p>Drag files into the page or pick them from your device. Folders are zipped automatically.</p></div>
  <div class="card"><h3>Set the rules</h3><p>Choose an expiry, an optional passcode and how many times the link may be opened.</p></div>
  <div class="card"><h3>Share the link</h3><p>Send the link by any channel. You can revoke it from your dashboard at any moment.</p></div>
</div>
<h2>What happens to your files</h2>
<p>Files are encrypted in transit and at rest. When a link expires or reaches its download limit, the file is removed from storage and cannot be recovered.</p>
<h2>Recipients</h2>
<p>Anyone with the link can download without creating an account. If you set a passcode, share it separately from the link.</p>
</div></main>
<footer><div class="wrap">
  <div>&copy; <span id="yr">2026</span> Tarnex. Send it once.</div>
  <div><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href="/help.html">Help</a></div>
</div></footer>
<script src="/assets/t1/app.js" defer></script>
</body>
</html>
EOF_HOW_IT_WORKS_HTML
cat > "${WEBROOT}/index.html" <<'EOF_INDEX_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Tarnex — Send files with a link that expires</title>
<meta name="description" content="Share large files with a private link. Set an expiry, a passcode and a download limit. No account needed for recipients.">
<meta name="theme-color" content="#101214">
<meta property="og:title" content="Tarnex — Send files with a link that expires">
<meta property="og:description" content="Share large files with a private link. Set an expiry, a passcode and a download limit. No account needed for recipients.">
<meta property="og:type" content="website">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/t1/style.css">
</head>
<body>
<header class="top"><div class="wrap nav">
  <a class="brand" href="/"><svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="9" fill="#ffb454"/><path d="M9 10h14M16 10v13" stroke="#1a1205" stroke-width="3.4" stroke-linecap="round"/></svg>Tarnex</a>
  <nav class="links"><a href="/" class=on>Home</a><a href="/how-it-works.html">How it works</a><a href="/pricing.html">Pricing</a><a href="/help.html">Help</a><a href="/login.html">Sign in</a></nav>
  <a class="btn pri" href="/login.html">Send a file</a>
  <button class="burger" aria-label="Menu">&#9776;</button>
</div></header>
<main>
<section class="hero"><div class="wrap">
  <span class="tag">Files up to 20 GB · Links that expire</span>
  <h1>Send it once.<br><em>Gone when you say so.</em></h1>
  <p class="lead">Drop a file, get a private link. Choose when it expires, how many times it can be opened and whether it needs a passcode. Recipients don't need an account.</p>
  <div class="drop" id="drop">
    <strong>Drop files here</strong>
    <p>or choose them from your device</p>
    <label class="btn pri lg" for="file">Choose files</label>
    <input type="file" id="file" multiple>
    <ul id="picked"></ul>
    <div id="note"></div>
    <div class="opts"><span>Expires in 24 h</span><span>1 download</span><span>Passcode optional</span></div>
  </div>
</div></section>
<section class="blk"><div class="wrap">
  <h2>Built for the one-time hand-off</h2>
  <p class="sub">Most files only need to travel once. Tarnex is designed around that.</p>
  <div class="grid">
    <div class="card"><div class="ico">&#9201;</div><h3>Expiring links</h3><p>Pick an expiry from one hour to thirty days. When the time is up the link stops working and the file is deleted.</p></div>
    <div class="card"><div class="ico">&#128273;</div><h3>Passcode &amp; limits</h3><p>Protect a link with a passcode and cap the number of downloads, so a forwarded link doesn't travel further than you intended.</p></div>
    <div class="card"><div class="ico">&#9889;</div><h3>Fast, resumable</h3><p>Large uploads are split into chunks and resume after a dropped connection instead of starting over.</p></div>
  </div>
</div></section>
</main>
<footer><div class="wrap">
  <div>&copy; <span id="yr">2026</span> Tarnex. Send it once.</div>
  <div><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href="/help.html">Help</a></div>
</div></footer>
<script src="/assets/t1/app.js" defer></script>
</body>
</html>
EOF_INDEX_HTML
cat > "${WEBROOT}/login.html" <<'EOF_LOGIN_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Sign in — Tarnex</title>
<meta name="description" content="Sign in to manage your transfers.">
<meta name="theme-color" content="#101214">
<meta property="og:title" content="Sign in — Tarnex">
<meta property="og:description" content="Sign in to manage your transfers.">
<meta property="og:type" content="website">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/t1/style.css">
</head>
<body>
<header class="top"><div class="wrap nav">
  <a class="brand" href="/"><svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="9" fill="#ffb454"/><path d="M9 10h14M16 10v13" stroke="#1a1205" stroke-width="3.4" stroke-linecap="round"/></svg>Tarnex</a>
  <nav class="links"><a href="/">Home</a><a href="/how-it-works.html">How it works</a><a href="/pricing.html">Pricing</a><a href="/help.html">Help</a><a href="/login.html">Sign in</a></nav>
  <a class="btn pri" href="/login.html">Send a file</a>
  <button class="burger" aria-label="Menu">&#9776;</button>
</div></header>
<main><div class="wrap">
<form class="form" id="login" autocomplete="on">
  <h1>Sign in</h1>
  <p style="color:var(--mut);margin:0">Manage your links and transfers.</p>
  <label for="em">Email</label><input id="em" type="email" autocomplete="username" required>
  <label for="pw">Password</label><input id="pw" type="password" autocomplete="current-password" required>
  <button class="btn pri" type="submit">Sign in</button>
  <div class="msg" id="msg"></div>
</form>
</div></main>
<footer><div class="wrap">
  <div>&copy; <span id="yr">2026</span> Tarnex. Send it once.</div>
  <div><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href="/help.html">Help</a></div>
</div></footer>
<script src="/assets/t1/app.js" defer></script>
</body>
</html>
EOF_LOGIN_HTML
cat > "${WEBROOT}/pricing.html" <<'EOF_PRICING_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Pricing — Tarnex</title>
<meta name="description" content="Free for everyday sending. Pro and Team for larger files and longer links.">
<meta name="theme-color" content="#101214">
<meta property="og:title" content="Pricing — Tarnex">
<meta property="og:description" content="Free for everyday sending. Pro and Team for larger files and longer links.">
<meta property="og:type" content="website">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/t1/style.css">
</head>
<body>
<header class="top"><div class="wrap nav">
  <a class="brand" href="/"><svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="9" fill="#ffb454"/><path d="M9 10h14M16 10v13" stroke="#1a1205" stroke-width="3.4" stroke-linecap="round"/></svg>Tarnex</a>
  <nav class="links"><a href="/">Home</a><a href="/how-it-works.html">How it works</a><a href="/pricing.html" class=on>Pricing</a><a href="/help.html">Help</a><a href="/login.html">Sign in</a></nav>
  <a class="btn pri" href="/login.html">Send a file</a>
  <button class="burger" aria-label="Menu">&#9776;</button>
</div></header>
<main><div class="wrap doc" style="max-width:1040px">
<h1>Simple pricing</h1>
<p class="sub">Start free. Upgrade when you send bigger files or need links that last longer.</p>
<div class="price">
  <div class="card"><h3>Free</h3><div class="amt">$0</div><ul><li>Up to 2 GB per transfer</li><li>Links expire in up to 3 days</li><li>Passcode protection</li></ul><a class="btn" href="/login.html">Get started</a></div>
  <div class="card hot"><h3>Pro</h3><div class="amt">$9<small> / month</small></div><ul><li>Up to 20 GB per transfer</li><li>Links expire in up to 30 days</li><li>Download limits &amp; revoke</li><li>Transfer history</li></ul><a class="btn pri" href="/login.html">Choose Pro</a></div>
  <div class="card"><h3>Team</h3><div class="amt">$24<small> / user / month</small></div><ul><li>Shared team library</li><li>Branded download page</li><li>Admin controls</li></ul><a class="btn" href="/login.html">Contact sales</a></div>
</div>
</div></main>
<footer><div class="wrap">
  <div>&copy; <span id="yr">2026</span> Tarnex. Send it once.</div>
  <div><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href="/help.html">Help</a></div>
</div></footer>
<script src="/assets/t1/app.js" defer></script>
</body>
</html>
EOF_PRICING_HTML
cat > "${WEBROOT}/privacy.html" <<'EOF_PRIVACY_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Privacy — Tarnex</title>
<meta name="description" content="How Tarnex handles your files and data.">
<meta name="theme-color" content="#101214">
<meta property="og:title" content="Privacy — Tarnex">
<meta property="og:description" content="How Tarnex handles your files and data.">
<meta property="og:type" content="website">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/t1/style.css">
</head>
<body>
<header class="top"><div class="wrap nav">
  <a class="brand" href="/"><svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="9" fill="#ffb454"/><path d="M9 10h14M16 10v13" stroke="#1a1205" stroke-width="3.4" stroke-linecap="round"/></svg>Tarnex</a>
  <nav class="links"><a href="/">Home</a><a href="/how-it-works.html">How it works</a><a href="/pricing.html">Pricing</a><a href="/help.html">Help</a><a href="/login.html">Sign in</a></nav>
  <a class="btn pri" href="/login.html">Send a file</a>
  <button class="burger" aria-label="Menu">&#9776;</button>
</div></header>
<main><div class="wrap doc">
<h1>Privacy</h1>
<p>We keep only what is needed to deliver a transfer: the file, its expiry and download settings, and basic technical logs used to prevent abuse.</p>
<h2>Files</h2><p>Files are stored encrypted and deleted when a link expires, reaches its download limit or is revoked.</p>
<h2>Logs</h2><p>Server logs are kept for a short period for security and reliability, then removed.</p>
<h2>Cookies</h2><p>We use only the cookies required for signing in. We do not run third-party advertising trackers.</p>
<h2>Questions</h2><p>Use the Help page to find answers, or sign in and contact support from your account.</p>
</div></main>
<footer><div class="wrap">
  <div>&copy; <span id="yr">2026</span> Tarnex. Send it once.</div>
  <div><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href="/help.html">Help</a></div>
</div></footer>
<script src="/assets/t1/app.js" defer></script>
</body>
</html>
EOF_PRIVACY_HTML
cat > "${WEBROOT}/robots.txt" <<'EOF_ROBOTS_TXT'
User-agent: *
Allow: /
EOF_ROBOTS_TXT
cat > "${WEBROOT}/site.webmanifest" <<'EOF_SITE_WEBMANIFEST'
{
  "name": "Tarnex",
  "short_name": "Tarnex",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#101214",
  "theme_color": "#101214",
  "icons": [{"src": "/apple-touch-icon.png", "sizes": "180x180", "type": "image/png"}]
}
EOF_SITE_WEBMANIFEST
cat > "${WEBROOT}/terms.html" <<'EOF_TERMS_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Terms — Tarnex</title>
<meta name="description" content="Terms of use for Tarnex.">
<meta name="theme-color" content="#101214">
<meta property="og:title" content="Terms — Tarnex">
<meta property="og:description" content="Terms of use for Tarnex.">
<meta property="og:type" content="website">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/t1/style.css">
</head>
<body>
<header class="top"><div class="wrap nav">
  <a class="brand" href="/"><svg viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="32" height="32" rx="9" fill="#ffb454"/><path d="M9 10h14M16 10v13" stroke="#1a1205" stroke-width="3.4" stroke-linecap="round"/></svg>Tarnex</a>
  <nav class="links"><a href="/">Home</a><a href="/how-it-works.html">How it works</a><a href="/pricing.html">Pricing</a><a href="/help.html">Help</a><a href="/login.html">Sign in</a></nav>
  <a class="btn pri" href="/login.html">Send a file</a>
  <button class="burger" aria-label="Menu">&#9776;</button>
</div></header>
<main><div class="wrap doc">
<h1>Terms of use</h1>
<p>By using Tarnex you agree to use the service lawfully and to be responsible for the files you share.</p>
<h2>Acceptable use</h2><p>Do not upload content that is illegal, infringes the rights of others or contains malware. We may remove content and suspend accounts that break these rules.</p>
<h2>Availability</h2><p>We work to keep the service available but do not guarantee uninterrupted access. Links and files may be removed after they expire.</p>
<h2>Changes</h2><p>We may update these terms. Continued use of the service means you accept the updated terms.</p>
</div></main>
<footer><div class="wrap">
  <div>&copy; <span id="yr">2026</span> Tarnex. Send it once.</div>
  <div><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a><a href="/help.html">Help</a></div>
</div></footer>
<script src="/assets/t1/app.js" defer></script>
</body>
</html>
EOF_TERMS_HTML
}
# <<< SITE-mona END

# Выбор сайта (-z / -m). Перед записью удаляются файлы обоих встроенных сайтов, чтобы при смене сайта на ноде не оставалось страниц прежнего.
site_clean() {
    local f
    for f in assets 404.html apple-touch-icon.png docs.html favicon.ico favicon.svg features.html index.html login.html \
             pricing.html privacy.html robots.txt site.webmanifest sitemap.xml terms.html how-it-works.html help.html; do
        rm -rf "${WEBROOT:?}/${f}"
    done
}

write_html() {
    site_clean
    case "${SITE}" in
        mona) write_html_mona ;;
        *)    write_html_zro ;;
    esac
    info "Сайт: ${SITE}"
}

write_shared_nginx() {
cat > "${NGINX_DIR}/nginx.conf" <<'EOF_NGINX_SHARED'
server_names_hash_bucket_size 64;
server_tokens off;
charset utf-8;

map $http_upgrade $connection_upgrade {
    default upgrade;
    ""      close;
}

gzip on;
gzip_vary on;
gzip_comp_level 5;
gzip_min_length 256;
gzip_proxied any;
gzip_types text/plain text/css application/javascript application/json image/svg+xml application/manifest+json application/xml;

ssl_protocols TLSv1.2 TLSv1.3;
ssl_ecdh_curve X25519:prime256v1:secp384r1;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers on;
ssl_session_timeout 1d;
ssl_session_cache shared:MozSSL:10m;
ssl_session_tickets off;

# пер-доменные server-блоки (добавляются установкой, друг друга не трогают)
include /opt/nginx/sites/*.conf;

# чужой SNI на сокете → drop
server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol default_server;
    server_name _;
    ssl_reject_handshake on;
    return 444;
}
EOF_NGINX_SHARED
}

write_domain_conf() {   # $1 = domain
    local dom="$1"
    mkdir -p "${NGINX_DIR}/sites"
cat > "${NGINX_DIR}/sites/${dom}.conf" <<'EOF_SITE_TPL'
server {
    server_name __DOMAIN__;
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;

    ssl_certificate         /opt/nginx/__DOMAIN__-fullchain.pem;
    ssl_certificate_key     /opt/nginx/__DOMAIN__-privkey.key;
    ssl_trusted_certificate /opt/nginx/__DOMAIN__-fullchain.pem;

    root /opt/nginx/html;
    index index.html;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options    "nosniff" always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
    add_header X-Frame-Options           "SAMEORIGIN" always;

    error_page 404 /404.html;
    location = /404.html { internal; }

    location ~* \.(?:css|js|svg|png|jpe?g|ico|webmanifest|woff2?)$ {
        expires 7d;
        access_log off;
    }

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF_SITE_TPL
    sed -i "s/__DOMAIN__/${dom}/g" "${NGINX_DIR}/sites/${dom}.conf"
}

migrate_old_layout() {
    local conf="${NGINX_DIR}/nginx.conf"
    [[ -f "$conf" ]] || return 0
    grep -q 'include /opt/nginx/sites/' "$conf" && return 0   # уже новый формат
    local olddom
    olddom=$(grep -oP 'server_name\s+\K[^;]+' "$conf" 2>/dev/null | grep -v '^_$' | head -1 || true)
    [[ -z "$olddom" ]] && { warn "Старый nginx.conf без домена — пересоздаю в новом формате"; return 0; }
    info "Миграция старого формата: переношу ${olddom} в sites/"
    mkdir -p "${NGINX_DIR}/sites"
    if [[ -e "${NGINX_DIR}/fullchain.pem" && ! -e "${NGINX_DIR}/${olddom}-fullchain.pem" ]]; then
        cp -aL "${NGINX_DIR}/fullchain.pem" "${NGINX_DIR}/${olddom}-fullchain.pem"
        cp -aL "${NGINX_DIR}/privkey.key"   "${NGINX_DIR}/${olddom}-privkey.key"
    fi
    write_domain_conf "${olddom}"
    info "Домен ${olddom} сохранён → sites/${olddom}.conf"
}

nginx_reload() {
    if docker exec "${CONTAINER}" nginx -t >/dev/null 2>&1; then
        docker exec "${CONTAINER}" nginx -s reload >/dev/null 2>&1 && { info "nginx reloaded"; return; }
    fi
    warn "reload не прошёл — restart контейнера"
    docker compose -f "${NGINX_DIR}/docker-compose.yml" restart >/dev/null 2>&1 || true
}

# =============================================================================
#  UPDATE — обновить сайт-витрину для ВСЕХ доменов ноды
# =============================================================================
if [[ "${MODE}" == "update" ]]; then
    section "UPDATE: обновление сайта (все домены)"
    [[ -d "${NGINX_DIR}" ]] || error "ss-fast не установлен"
    write_html
    write_shared_nginx
    nginx_reload
    echo -e "\n${GREEN}Сайт обновлён для всех доменов ноды${NC}\n"
    exit 0
fi

# =============================================================================
#  INSTALL
# =============================================================================
[[ -z "${DOMAIN}" ]] && error "Usage: [CF_Token=..|CF_Key=..+CF_Email=..|REGRU_USER=..+REGRU_PASS=..] ACME_EMAIL=.. bash install.sh [-z|-m] <domain>"
[[ -z "${EMAIL}"  ]] && error "Не задан ACME_EMAIL"

REGRU_USER="${REGRU_USER:-${REGRU_API_Username:-}}"
REGRU_PASS="${REGRU_PASS:-${REGRU_API_Password:-}}"
PROVIDER="${DNS_PROVIDER:-}"
if [[ -z "${PROVIDER}" ]]; then
    if   [[ -n "${CF_Token:-}" || ( -n "${CF_Key:-}" && -n "${CF_Email:-}" ) ]]; then PROVIDER="cf"
    elif [[ -n "${REGRU_USER}" && -n "${REGRU_PASS}" ]];                          then PROVIDER="regru"
    else error "Нет кред DNS. CF_Token(+CF_Account_ID) / CF_Key+CF_Email / REGRU_USER+REGRU_PASS"; fi
fi
case "${PROVIDER}" in
    cf)
        if   [[ -n "${CF_Token:-}" ]]; then
            CF_MODE="token"
            [[ -z "${CF_Account_ID:-}" && -z "${CF_Zone_ID:-}" ]] && \
                warn "CF_Token без CF_Account_ID: сработает только если у токена Zone.Zone:Read по всем зонам"
            info "DNS: Cloudflare (API Token)"
        elif [[ -n "${CF_Key:-}" && -n "${CF_Email:-}" ]]; then
            CF_MODE="key"; info "DNS: Cloudflare (Global API Key + Email)"
        else error "cf: нужен CF_Token или CF_Key+CF_Email"; fi
        DNS_HOOK="dns_cf" ;;
    regru)
        [[ -z "${REGRU_USER}" || -z "${REGRU_PASS}" ]] && error "regru: пусты REGRU_USER/PASS"
        DNS_HOOK="dns_regru"; info "DNS: reg.ru (dns_regru)" ;;
    *) error "Неизвестный DNS_PROVIDER='${PROVIDER}'" ;;
esac

section "1. remnanode: маунты"
COMPOSE_FILE="${REMNANODE_DIR}/docker-compose.yml"
[[ ! -f "${COMPOSE_FILE}" ]] && error "Нет ${COMPOSE_FILE} — remnanode не установлен"
REMNA_RECREATE=0
for M in "/dev/shm:/dev/shm:rw" "/opt/nginx:/opt/nginx:ro"; do
    SRC="${M%%:*}"
    if grep -q "${SRC}:" "${COMPOSE_FILE}"; then info "${SRC} уже проброшен"
    else
        warn "Пробрасываю ${SRC}"
        python3 - "${COMPOSE_FILE}" "${M}" <<'PYEOF'
import re, sys
p, mnt = sys.argv[1], sys.argv[2]; c=open(p).read(); src=mnt.split(":")[0]
if re.search(r'(^|\s)-\s*'+re.escape(src)+r':', c): sys.exit(0)
out=[]; done=False
for ln in c.splitlines(keepends=True):
    out.append(ln)
    if not done and re.match(r'^(\s+)volumes:\s*$', ln):
        ind=re.match(r'^(\s+)', ln).group(1); out.append(ind+"  - "+mnt+"\n"); done=True
open(p,"w").writelines(out); print("patched" if done else "no-volumes")
PYEOF
        REMNA_RECREATE=1
    fi
done

section "2. Зависимости"
PKGS=()
for pkg in curl socat wget python3 cron openssl; do dpkg -s "$pkg" &>/dev/null || PKGS+=("$pkg"); done
if [[ ${#PKGS[@]} -gt 0 ]]; then info "Ставлю: ${PKGS[*]}"; apt-get update -qq; apt-get install -y -qq "${PKGS[@]}"; fi
if ! grep -q "tcp_congestion_control = bbr" /etc/sysctl.conf 2>/dev/null; then
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null; info "BBR включён"
fi

section "3. Проверка DNS"
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me || true)
mapfile -t DNS_IPS < <(getent hosts "${DOMAIN}" | awk '{print $1}' || true)
if [[ ${#DNS_IPS[@]} -eq 0 ]]; then warn "${DOMAIN} не резолвится (для dns-01 неважно, для SNI/Reality — важно)"
else
    info "A-записи ${DOMAIN}: ${DNS_IPS[*]}"
    printf '%s\n' "${DNS_IPS[@]}" | grep -qx "${SERVER_IP}" \
        && info "DNS указывает на этот сервер (${SERVER_IP})" \
        || warn "IP сервера (${SERVER_IP}) не среди A-записей — для Reality serverName это может быть проблемой"
fi

section "4. Сайт + конфиги (мультидомен)"
mkdir -p "${WEBROOT}" "${NGINX_DIR}/sites"
migrate_old_layout
write_html
write_shared_nginx
write_domain_conf "${DOMAIN}"
info "sites/: $(ls -1 ${NGINX_DIR}/sites/*.conf 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"

section "5. acme.sh"
if [[ ! -f "${ACME_HOME}/acme.sh" ]]; then info "Ставлю acme.sh"; curl -fsSL https://get.acme.sh | sh -s email="${EMAIL}"; fi
ACME="${ACME_HOME}/acme.sh"
[[ ! -f "${ACME}" ]] && error "acme.sh не найден"
export PATH="${ACME_HOME}:${PATH}"

section "6. Сертификат ${DOMAIN} (dns-01, ${PROVIDER})"
CERTF="${NGINX_DIR}/${DOMAIN}-fullchain.pem"
KEYF="${NGINX_DIR}/${DOMAIN}-privkey.key"
SKIP_CERT=0
if [[ -f "${CERTF}" ]]; then
    SAN=$(openssl x509 -in "${CERTF}" -noout -ext subjectAltName 2>/dev/null || true)
    if grep -Eq "DNS:${DOMAIN}(,|$| )" <<<"${SAN}"; then
        EXP=$(openssl x509 -enddate -noout -in "${CERTF}" 2>/dev/null | cut -d= -f2 || true)
        if [[ -n "$EXP" ]]; then
            DLEFT=$(( ( $(date -d "${EXP}" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
            [[ $DLEFT -gt 30 ]] && { info "Cert ${DOMAIN} валиден ещё ${DLEFT} дн — пропускаю"; SKIP_CERT=1; } \
                                || warn "Cert ${DOMAIN} истекает через ${DLEFT} дн — перевыпуск"
        fi
    else warn "Файл ${DOMAIN}-fullchain.pem не покрывает ${DOMAIN} — перевыпуск"; fi
fi
if [[ $SKIP_CERT -eq 0 ]]; then
    "${ACME}" --set-default-ca --server letsencrypt
    if [[ "${PROVIDER}" == "cf" ]]; then
        if [[ "${CF_MODE}" == "key" ]]; then export CF_Key CF_Email
        else export CF_Token; [[ -n "${CF_Email:-}" ]] && export CF_Email
             [[ -n "${CF_Account_ID:-}" ]] && export CF_Account_ID
             [[ -n "${CF_Zone_ID:-}" ]] && export CF_Zone_ID; fi
    else export REGRU_API_Username="${REGRU_USER}"; export REGRU_API_Password="${REGRU_PASS}"; fi
    "${ACME}" --issue --dns "${DNS_HOOK}" -d "${DOMAIN}" --keylength ec-256 \
        --key-file "${KEYF}" --fullchain-file "${CERTF}" --force \
        || error "Выпуск cert не удался. Проверь креды ${PROVIDER} и DNS."
    "${ACME}" --install-cert -d "${DOMAIN}" --ecc \
        --key-file "${KEYF}" --fullchain-file "${CERTF}" \
        --reloadcmd "docker exec ${CONTAINER} nginx -s reload 2>/dev/null || true" \
        || warn "install-cert reload — не критично, контейнер стартует ниже"
    info "Cert → ${CERTF}"
fi

section "7. docker-compose.yml"
cat > "${NGINX_DIR}/docker-compose.yml" <<DCEOF
services:
  ${CONTAINER}:
    image: nginx:1.28
    container_name: ${CONTAINER}
    hostname: ${CONTAINER}
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /opt/nginx:/opt/nginx:ro
      - /dev/shm:/dev/shm:rw
    command: sh -c 'rm -f /dev/shm/nginx.sock && exec nginx -g "daemon off;"'
    network_mode: host
    logging:
      driver: json-file
      options:
        max-size: 30m
        max-file: "5"
DCEOF

section "8. UFW"
ufw allow 22/tcp comment 'SSH' >/dev/null 2>&1 || true
ufw allow 443/tcp comment 'HTTPS' >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true; ufw reload >/dev/null 2>&1 || true
info "UFW: 22, 443"

section "9. Запуск nginx"
docker stop "${CONTAINER}" 2>/dev/null || true
docker rm "${CONTAINER}" 2>/dev/null || true
cd "${NGINX_DIR}"
docker compose pull -q "${CONTAINER}" || true
docker compose up -d --no-deps "${CONTAINER}"
sleep 2
[[ -S "${NGINX_SOCK}" ]] && info "Socket: ${NGINX_SOCK}" || warn "Socket ещё не появился"
docker exec "${CONTAINER}" nginx -t >/dev/null 2>&1 && info "nginx -t: OK (все домены в sites/ валидны)" || warn "nginx -t дал ошибку — docker exec ${CONTAINER} nginx -t"

section "10. remnanode: применить маунты / перечитать xray"
if [[ ${REMNA_RECREATE} -eq 1 ]]; then
    docker compose -f "${COMPOSE_FILE}" up -d --force-recreate remnanode || warn "не смог пересоздать remnanode"
    info "remnanode пересоздан с маунтами"
else
    docker compose -f "${COMPOSE_FILE}" restart remnanode >/dev/null 2>&1 || warn "не смог перезапустить remnanode"
    info "remnanode перезапущен"
fi
sleep 2
docker logs remnanode --tail=30 2>&1 | grep -qi "failed to load config\|no such file" \
    && warn "xray ругается — docker logs remnanode --tail=40" \
    || info "xray стартовал без ошибок cert"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Домен ${DOMAIN} добавлен на ноду${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo -e "  ${YELLOW}В xray (remnanode) для этого домена:${NC}"
echo -e "  ${CYAN}\"dest\": \"/dev/shm/nginx.sock\"  \"xver\": 1  \"serverNames\": [\"${DOMAIN}\"]${NC}"
echo -e "  ${GRAY}Домены ноды: $(ls -1 ${NGINX_DIR}/sites/*.conf 2>/dev/null | xargs -n1 basename | sed 's/.conf//' | tr '\n' ' ')${NC}"
echo -e "  ${GRAY}Обновить сайт (все домены): bash install.sh update${NC}"
echo ""
