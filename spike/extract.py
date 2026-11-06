
import re, pathlib, sys
SRC = pathlib.Path('/Users/ryan/Downloads/index.html')
OUT = pathlib.Path(__file__).parent / 'web' / 'panel.html'
s = SRC.read_text(encoding='utf-8')
css = re.findall(r'<style>(.*?)</style>', s, re.S)[0]
start = s.index('<aside class="popover"')
end = s.index('</aside>', start) + len('</aside>')
pop = s[start:end]

OVERRIDE = """
/* ---- native shell overrides（spike）---- */
html, body { background: transparent !important; overflow: visible !important;
  height: auto !important; min-height: 0 !important; margin: 0 !important; padding: 0 !important; }
body { padding-top: var(--arrow-h, 10px) !important; box-sizing: border-box; }
.popover { position: relative !important; top: auto !important; left: auto !important;
  width: 392px !important; max-height: none !important; margin: 0 !important;
  animation: none !important; transform: none !important;
  box-shadow: none !important;             /* 投影交给 NSWindow.hasShadow */
  background: transparent;                 /* 底色由原生 tint 层压（这样箭头和面板同一个色）；body.opaque 时用原型 95% 底色 */
  -webkit-backdrop-filter: none; backdrop-filter: none;  /* body.bf 时打开（问题 D） */
}
body.opaque .popover { background: var(--panel); }
body.bf .popover { -webkit-backdrop-filter: blur(36px) saturate(1.55); backdrop-filter: blur(36px) saturate(1.55); }
.popover::before { display: none; }        /* 箭头由原生 mask 绘制（问题 B） */
.popover, .popover * { animation-duration: 0ms !important; transition-duration: 0ms !important; }
"""

JS = """
const q = new URLSearchParams(location.search);
const post = o => window.webkit && window.webkit.messageHandlers.spike.postMessage(o);
document.documentElement.dataset.theme = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
if (q.get('opaque')) document.body.classList.add('opaque');
if (q.get('bf')) document.body.classList.add('bf');
const arrowH = parseFloat(q.get('arrow') || '10');
document.documentElement.style.setProperty('--arrow-h', arrowH + 'px');
window.__keys = [];
addEventListener('keydown', e => { window.__keys.push(e.key); post({key: e.key}); }, true);
const measure = () => {
  const r = document.getElementById('popover').getBoundingClientRect();
  post({h: Math.ceil(r.height + arrowH), w: Math.ceil(r.width)});
};
setTimeout(measure, 60);   // 离屏 WKWebView 会节流 rAF，用 setTimeout
"""

html = ('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">'
        '<meta name="color-scheme" content="light dark">'
        f'<style>{css}</style><style>{OVERRIDE}</style></head><body>{pop}'
        f'<script>{JS}</script></body></html>')
OUT.write_text(html, encoding='utf-8')
print('wrote', OUT, len(html), 'bytes')
