/* Общий переключатель языка для страниц Verified.Ninja.
   Страница объявляет window.render(T) и вставляет <select class="lang" id="lang">. */

const VN_LANGS = {
  en: 'English',
  de: 'Deutsch',
  es: 'Español',
  fr: 'Français',
  ru: 'Русский'
};

function vnPick(){
  try{
    const saved = localStorage.getItem('vn_lang');
    if(saved && VN_LANGS[saved]) return saved;
  }catch(e){}
  const n = (navigator.language || 'en').slice(0,2).toLowerCase();
  return VN_LANGS[n] ? n : 'en';
}

async function vnSetLang(code){
  let T;
  try{
    const r = await fetch(`lang/${code}.json`);
    if(!r.ok) throw new Error(r.status);
    T = await r.json();
  }catch(e){
    if(code !== 'en') return vnSetLang('en');
    return;
  }
  try{ localStorage.setItem('vn_lang', code); }catch(e){}
  document.documentElement.lang = code;
  document.documentElement.dir = T.dir || 'ltr';
  const sel = document.getElementById('lang');
  if(sel) sel.value = code;
  window.render(T);
}

function vnInit(){
  const sel = document.getElementById('lang');
  if(sel){
    sel.innerHTML = Object.entries(VN_LANGS)
      .map(([c,n]) => `<option value="${c}">${n}</option>`).join('');
    sel.addEventListener('change', e => vnSetLang(e.target.value));
  }
  vnSetLang(vnPick());
}

document.addEventListener('DOMContentLoaded', vnInit);
