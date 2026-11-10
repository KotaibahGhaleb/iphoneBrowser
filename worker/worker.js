// مرآة موقع عبر Cloudflare Worker — مجاني 100% (الخطة المجانية لا تحتاج بطاقة)
// 1) انشر هذا الملف على workers.dev
// 2) حط رابط الـ Worker كـ "الصفحة الرئيسية" في التطبيق وخلي الوضع "بدون بروكسي"
//
// آلية العمل:
//   https://your.workers.dev/path        -> https://TARGET/path
//   https://your.workers.dev/u/<abs-url> -> أي رابط خارجي يمر عبر المرآة (CDN، فيديو...)

const TARGET = "https://viralxxxporn.com"; // غيّره لأي موقع آخر لو حبيت
const PREFIX = "/u/";

export default {
  async fetch(request) {
    try {
      return await handle(request);
    } catch (err) {
      return new Response("Mirror error: " + err.message, { status: 502 });
    }
  },
};

function upstreamURL(request) {
  const url = new URL(request.url);
  if (url.pathname.startsWith(PREFIX)) {
    return new URL(url.pathname.slice(PREFIX.length) + url.search);
  }
  return new URL(TARGET + url.pathname + url.search);
}

function wrap(value, base, origin) {
  if (!value) return value;
  const v = value.trim();
  if (!v || /^(data:|javascript:|mailto:|tel:|blob:|about:|#)/i.test(v)) return value;
  try {
    const abs = new URL(v, base).href;
    if (abs.startsWith(origin)) return abs;
    return origin + PREFIX + abs;
  } catch {
    return value;
  }
}

async function handle(request) {
  const url = new URL(request.url);
  const upstream = upstreamURL(request);
  const selfOrigin = url.origin;

  const headers = new Headers(request.headers);
  headers.set("host", upstream.host);
  headers.set("referer", upstream.origin + "/");
  headers.set("origin", upstream.origin);
  headers.delete("accept-encoding"); // نحتاج رداً غير مضغوط لنعدّل المحتوى النصي
  for (const h of ["cf-connecting-ip", "cf-ipcountry", "cf-ray", "x-forwarded-for",
                   "x-forwarded-proto", "cf-visitor", "cdn-loop", "true-client-ip"]) {
    headers.delete(h);
  }

  const resp = await fetch(upstream.href, {
    method: request.method,
    headers,
    body: ["GET", "HEAD"].includes(request.method) ? undefined : request.body,
    redirect: "manual",
  });

  const rh = new Headers(resp.headers);
  const location = rh.get("location");
  if (location) rh.set("location", wrap(location, upstream.href, selfOrigin));

  for (const h of ["content-security-policy", "content-security-policy-report-only",
                   "x-frame-options", "content-encoding", "content-length",
                   "access-control-allow-origin"]) {
    rh.delete(h);
  }

  // إعادة كتابة نطاق الكوكيز ليطابق نطاق المرآة
  const cookies = rh.getSetCookie();
  if (cookies.length) {
    rh.delete("set-cookie");
    for (const c of cookies) {
      rh.append("set-cookie", c.replace(/;\s*domain=[^;]+/i, ""));
    }
  }

  const type = (rh.get("content-type") || "").toLowerCase();

  if (type.includes("text/html")) {
    return rewriteHTML(resp, rh, upstream.href, selfOrigin);
  }
  if (type.includes("mpegurl") || upstream.pathname.endsWith(".m3u8")) {
    const text = await resp.text();
    return new Response(rewriteManifest(text, upstream.href, selfOrigin),
      { status: resp.status, headers: rh });
  }
  if (type.includes("css")) {
    const text = await resp.text();
    return new Response(rewriteCSS(text, upstream.href, selfOrigin),
      { status: resp.status, headers: rh });
  }
  if (type.includes("javascript") || type.includes("json")) {
    const text = await resp.text();
    return new Response(rewriteJS(text, selfOrigin),
      { status: resp.status, headers: rh });
  }
  // فيديو/صور/ملفات ثنائية تمر كما هي (مع دعم Range)
  return new Response(resp.body, { status: resp.status, headers: rh });
}

// ---------- إعادة كتابة HTML ----------

function rewriteHTML(resp, headers, base, origin) {
  const rewritten = new HTMLRewriter()
    .on("[src]", attr("src", base, origin))
    .on("[href]", attr("href", base, origin))
    .on("[action]", attr("action", base, origin))
    .on("[poster]", attr("poster", base, origin))
    .on("[data-src]", attr("data-src", base, origin))
    .on("[srcset]", srcset(base, origin))
    .on('meta[http-equiv="refresh"]', metaRefresh(base, origin))
    .on("head", inject(origin))
    .transform(resp);
  return new Response(rewritten.body, { status: resp.status, headers });
}

function attr(name, base, origin) {
  return {
    element(el) {
      const v = el.getAttribute(name);
      if (v) el.setAttribute(name, wrap(v, base, origin));
    },
  };
}

function srcset(base, origin) {
  return {
    element(el) {
      const v = el.getAttribute("srcset");
      if (!v) return;
      const out = v.split(",").map((part) => {
        const [u, ...desc] = part.trim().split(/\s+/);
        return [wrap(u, base, origin), ...desc].join(" ");
      });
      el.setAttribute("srcset", out.join(", "));
    },
  };
}

function metaRefresh(base, origin) {
  return {
    element(el) {
      const v = el.getAttribute("content");
      if (!v) return;
      el.setAttribute("content",
        v.replace(/url=\s*(.+)$/i, (m, u) => "url=" + wrap(u, base, origin)));
    },
  };
}

function inject(origin) {
  return {
    element(el) {
      el.prepend("<script>" + CLIENT_JS + "</script>", { html: true });
    },
  };
}

// ---------- إعادة كتابة المحتوى النصي ----------

function rewriteManifest(text, base, origin) {
  return text.split("\n").map((line) => {
    if (line.startsWith("#")) {
      return line.replace(/URI="([^"]+)"/g, (m, u) => `URI="${wrap(u, base, origin)}"`);
    }
    const t = line.trim();
    return t ? wrap(t, base, origin) : line;
  }).join("\n");
}

function rewriteCSS(text, base, origin) {
  return text.replace(/url\(\s*(['"]?)([^'")]+)\1\s*\)/g,
    (m, q, u) => `url(${q}${wrap(u, base, origin)}${q})`);
}

// يعيد كتابة الروابط المطلقة داخل نصوص JS/JSON (إعدادات المشغّل وغيرها)
function rewriteJS(text, origin) {
  return text.replace(/(["'`])(https?:\/\/)/g, (m, q, s) => q + origin + PREFIX + s);
}

// ---------- سكربت يُحقن في الصفحة ----------
// يعترض الروابط اللي يولّدها جافاسكربت الموقع وقت التشغيل (fetch/XHR/src ديناميكي)

const CLIENT_JS = `(function(){
  var O = location.origin, P = "/u/";
  function rw(u){
    try {
      if (!u || typeof u !== "string") return u;
      if (u.indexOf(O + P) === 0) return u;
      if (/^\\/\\//.test(u)) u = location.protocol + u;
      if (/^https?:\\/\\//i.test(u)) return O + P + u;
      return u;
    } catch(e) { return u; }
  }
  var of = window.fetch;
  if (of) window.fetch = function(i, o){
    try {
      if (typeof i === "string") i = rw(i);
      else if (i && i.url) i = new Request(rw(i.url), i);
    } catch(e) {}
    return of.call(this, i, o);
  };
  var oo = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(){
    if (arguments.length > 1) arguments[1] = rw(arguments[1]);
    return oo.apply(this, arguments);
  };
  var sa = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function(n, v){
    if (/^(src|href|action|poster|data-src)$/i.test(n)) v = rw(v);
    return sa.call(this, n, v);
  };
  [["HTMLMediaElement","src"],["HTMLSourceElement","src"],["HTMLImageElement","src"],
   ["HTMLScriptElement","src"],["HTMLIFrameElement","src"],["HTMLEmbedElement","src"],
   ["HTMLAnchorElement","href"],["HTMLLinkElement","href"],["HTMLFormElement","action"],
   ["HTMLVideoElement","poster"]].forEach(function(pair){
    var proto = window[pair[0]] && window[pair[0]].prototype;
    if (!proto) return;
    var d = Object.getOwnPropertyDescriptor(proto, pair[1]);
    if (d && d.set) Object.defineProperty(proto, pair[1], {
      set: function(v){ d.set.call(this, rw(v)); },
      get: d.get
    });
  });
  var oWin = window.open;
  window.open = function(u){ return oWin.call(this, rw(u)); };
  var sb = navigator.sendBeacon && navigator.sendBeacon.bind(navigator);
  if (sb) navigator.sendBeacon = function(u, d){ return sb(rw(u), d); };
})();`;
