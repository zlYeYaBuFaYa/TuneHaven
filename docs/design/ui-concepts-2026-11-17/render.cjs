// Self-contained concept artwork and reproducible Chromium exports.
// NODE_PATH=<bundled node_modules> node render.cjs
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');
const root = __dirname;
fs.mkdirSync(path.join(root, 'assets'), { recursive: true });
fs.mkdirSync(path.join(root, 'screens'), { recursive: true });
const grain = `<filter id="grain"><feTurbulence type="fractalNoise" baseFrequency=".72" numOctaves="3" stitchTiles="stitch"/><feColorMatrix type="saturate" values="0"/><feComponentTransfer><feFuncA type="linear" slope=".12"/></feComponentTransfer><feBlend in="SourceGraphic" mode="soft-light"/></filter>`;
const wrap = (defs, art) => `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600" viewBox="0 0 600 600"><defs>${grain}${defs}</defs>${art}<rect width="600" height="600" filter="url(#grain)" opacity=".22" style="mix-blend-mode:soft-light"/></svg>`;
const artwork = {
  dusk: wrap(`<linearGradient id="sky" x2="0" y2="1"><stop stop-color="#d9d3e8"/><stop offset=".54" stop-color="#f0c2b9"/><stop offset="1" stop-color="#c2cbdc"/></linearGradient><linearGradient id="sea" x2="0" y2="1"><stop stop-color="#708ba5"/><stop offset="1" stop-color="#a4b8cd"/></linearGradient><radialGradient id="glow"><stop stop-color="#ffe0ba" stop-opacity=".7"/><stop offset="1" stop-color="#ffe0ba" stop-opacity="0"/></radialGradient>`,
  `<rect width="600" height="600" fill="url(#sky)"/><circle cx="394" cy="275" r="175" fill="url(#glow)"/><circle cx="394" cy="275" r="57" fill="#ffe1b7"/><path d="M0 361Q110 315 207 352T390 350T600 333V600H0Z" fill="#8f9eaf" opacity=".45"/><path d="M0 385Q160 359 300 378T600 373V600H0Z" fill="url(#sea)"/><g stroke="#dfd4cd" opacity=".4" fill="none"><path d="M0 403q160-15 300 0t300 2M0 432q180-12 340 0t260-2M20 475q160-10 300 0t280 0M0 525q110-13 320 0t280 1M0 563q140-8 290 0t310 1"/><path d="M341 390h108m-130 9h145m-111 14h78m-92 9h120m-92 15h79m-50 15h39"/></g><path d="M0 526q62-32 140-5t71 79H0Z" fill="#6b7c93"/><path d="M0 547q70-15 111 10t39 43H0Z" fill="#4d607b"/><text x="44" y="71" fill="#4b5066" font-family="Helvetica Neue,Arial" font-size="12" letter-spacing="5">ISLAND LETTERS</text><text x="41" y="141" fill="#44485c" font-family="Georgia" font-size="57" letter-spacing="-2">before sunset.</text><text x="44" y="172" fill="#62647b" font-family="Arial" font-size="10" letter-spacing="3">A LITTLE SLOWER, A LITTLE CLOSER.</text><text x="558" y="557" text-anchor="end" fill="#e2e6ed" font-family="Arial" font-size="11" letter-spacing="3">VOL. 01</text>`),
  coast: wrap(`<linearGradient id="sky" x2="0" y2="1"><stop stop-color="#e2e9d7"/><stop offset=".47" stop-color="#e9dfc2"/><stop offset="1" stop-color="#b9d6cc"/></linearGradient><linearGradient id="sea" x2="0" y2="1"><stop stop-color="#91bfb5"/><stop offset="1" stop-color="#2f7a77"/></linearGradient>`,
  `<rect width="600" height="600" fill="url(#sky)"/><circle cx="420" cy="215" r="61" fill="#fff2ca"/><path d="M0 330 600 300V600H0Z" fill="url(#sea)"/><path d="M600 293Q436 328 412 396T225 600H600Z" fill="#e9d9b7"/><path d="M600 312Q438 346 427 406T251 600" stroke="#fff7dd" stroke-width="9" fill="none" opacity=".8"/><path d="M600 327Q452 348 441 418T281 600" stroke="#abc7bc" stroke-width="2" fill="none"/><path d="M600 389Q552 397 540 464T433 600H600Z" fill="#849c7d"/><path d="M600 438Q555 428 560 498T480 600H600Z" fill="#4d7763"/><g fill="none" stroke="#d5e3d0" opacity=".45"><path d="M0 363q160-15 280-8M0 403q130-9 312-12M0 475q110-5 241-17M0 536q80 3 130-8"/></g><text x="42" y="70" font-family="Arial" fill="#42665d" font-size="11" letter-spacing="4">DAYLIGHT WANDERERS</text><text x="42" y="142" font-family="Georgia" fill="#355f56" font-size="61" letter-spacing="-2">coast to coast</text><text x="44" y="176" font-family="Arial" fill="#5a7768" font-size="10" letter-spacing="3">WHERE THE DAYS UNFOLD SLOWLY</text>`),
  moon: wrap(`<linearGradient id="sky" x2="0" y2="1"><stop stop-color="#343e6a"/><stop offset=".6" stop-color="#8e9ec1"/><stop offset="1" stop-color="#d4bad4"/></linearGradient><linearGradient id="hill" x2="0" y2="1"><stop stop-color="#657ba3"/><stop offset="1" stop-color="#283953"/></linearGradient><radialGradient id="halo"><stop stop-color="#e2d7ec" stop-opacity=".4"/><stop offset="1" stop-color="#d0c9e4" stop-opacity="0"/></radialGradient>`,
  `<rect width="600" height="600" fill="url(#sky)"/><circle cx="425" cy="191" r="130" fill="url(#halo)"/><circle cx="425" cy="191" r="37" fill="#ebe4df"/><g fill="#e4dfed" opacity=".6"><circle cx="93" cy="208" r="1"/><circle cx="223" cy="168" r="1.2"/><circle cx="512" cy="98" r="1.1"/><circle cx="311" cy="232" r=".8"/><circle cx="133" cy="289" r="1.2"/></g><path d="M0 407 140 297 233 374 343 283 455 366 600 287V600H0Z" fill="#8495b6"/><path d="M0 454 115 379 237 463 366 346 464 415 600 388V600H0Z" fill="#5b7098"/><path d="M0 505Q90 414 228 499T600 453V600H0Z" fill="url(#hill)"/><text x="42" y="67" fill="#e5e2f0" font-family="Arial" font-size="11" letter-spacing="5">THIRTY DEGREES NORTH</text><text x="38" y="139" fill="#f1e9ef" font-family="Georgia" font-size="66" letter-spacing="-2">blue hour</text><text x="44" y="550" fill="#d5d6e4" font-family="Arial" font-size="10" letter-spacing="3">STAY A LITTLE LONGER.</text>`),
  field: wrap(`<linearGradient id="sky" x2="0" y2="1"><stop stop-color="#ecebd6"/><stop offset="1" stop-color="#c2d3c6"/></linearGradient><linearGradient id="hill" x2="0" y2="1"><stop stop-color="#849e7b"/><stop offset="1" stop-color="#4b7764"/></linearGradient>`,
  `<rect width="600" height="600" fill="url(#sky)"/><circle cx="400" cy="255" r="83" fill="#f7d798"/><path d="M0 362Q149 244 334 381T600 320V600H0Z" fill="#aabca0"/><path d="M0 465Q186 314 367 445T600 411V600H0Z" fill="url(#hill)"/><path d="M260 600Q370 485 260 426T332 368" fill="none" stroke="#e5d7ad" stroke-width="19"/><g fill="none" stroke="#edf0cc" stroke-width="1" opacity=".18"><path d="M0 508Q170 356 355 477T600 440M0 531Q170 379 355 500T600 463M0 554Q170 402 355 523T600 486M0 577Q170 425 355 546T600 509"/></g><text x="42" y="69" font-family="Arial" fill="#536a5b" font-size="11" letter-spacing="5">LUNA FIELD</text><text x="38" y="143" font-family="Georgia" fill="#365c4d" font-size="62" letter-spacing="-2">soft landing</text><text x="44" y="177" font-family="Arial" fill="#647865" font-size="10" letter-spacing="3">SMALL MOMENTS, WIDE OPEN SPACES.</text>`)
};
artwork['coast-disc']=artwork.coast.replace(/<text\b[^>]*>[\s\S]*?<\/text>/g,'');
for (const [name, svg] of Object.entries(artwork)) fs.writeFileSync(path.join(root, 'assets', name + '.svg'), svg);
// Generated entry shares the same layout, content and interactions as daylight.
fs.writeFileSync(path.join(root,'dark.html'),fs.readFileSync(path.join(root,'index.html'),'utf8').replace('<body>','<body class="dark">').replace('<title>TuneHaven · 三种柔光设计提案</title>','<title>TuneHaven · 三款黑夜模式</title>'));
(async () => {
  const browser = await chromium.launch({headless:true,channel:'chrome'});
  const page = await browser.newPage({viewport:{width:1600,height:1140},deviceScaleFactor:2});
  const errors=[];page.on('pageerror',error=>errors.push(error.message));
  const dark=process.argv.includes('--dark');
  const prefix=dark?'dark-':'';
  const report={appearance:dark?'dark':'light'};
  for (const variant of ['a','b','c']) {
    await page.goto('file://' + path.join(root,dark?'dark.html':'index.html') + '?concept=' + variant);
    await page.evaluate(()=>document.fonts.ready);
    await page.locator('.board.visible img').evaluateAll(imgs=>Promise.all(imgs.map(i=>i.decode())));
    await page.screenshot({path:path.join(root,prefix+variant+'-board.png')});
    const phones=page.locator('.board.visible .screen');
    for(let i=0;i<2;i++) await phones.nth(i).screenshot({path:path.join(root,'screens',prefix+variant+'-'+(i+1)+'.png')});
    report[variant]=await page.locator('.board.visible').evaluate(el=>({images:[...el.querySelectorAll('img')].every(i=>i.complete&&i.naturalWidth>0), screens:[...el.querySelectorAll('.screen')].map(s=>({width:s.clientWidth,height:s.clientHeight, horizontalOverflow:s.scrollWidth>s.clientWidth})),textClipping:[...el.querySelectorAll('h1,h2,h3,.song-text strong,.detail,.page-label')].filter(x=>x.scrollWidth>x.clientWidth+1).map(x=>x.textContent)}));
    if(dark){
      report[variant].contrast=await page.locator('.board.visible').evaluate(el=>{
        const style=getComputedStyle(el);
        const token=name=>style.getPropertyValue('--'+name).trim();
        const luminance=hex=>{const c=hex.replace('#','').match(/../g).map(s=>parseInt(s,16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return c[0]*.2126+c[1]*.7152+c[2]*.0722};
        const ratio=(a,b)=>{const [low,high]=[luminance(a),luminance(b)].sort((x,y)=>x-y);return (high+.05)/(low+.05)};
        const bg=['paper','a','b','c','surface'].map(token);
        return {method:'Minimum WCAG contrast of foreground tokens against all five opaque palette stops; rendered alpha mixtures checked visually.',primaryMinimum:+Math.min(...bg.map(b=>ratio(token('ink'),b))).toFixed(2),secondaryMinimum:+Math.min(...bg.map(b=>ratio(token('muted'),b))).toFixed(2),primaryAction:+ratio(token('action'),token('on-action')).toFixed(2)};
      });
    }
  }
  // Verify the small interactions supplied in the concept gallery.
  await page.locator('.board.visible [data-heart]').click();
  report.favorite=await page.locator('.board.visible [data-heart]').getAttribute('aria-pressed');
  await page.locator('.board.visible .main-play').click();
  report.playback=await page.locator('.board.visible .main-play').getAttribute('aria-label');
  await page.locator('.board.visible input').fill('blue');
  report.searchResults=await page.locator('.board.visible .song-row:visible').count();
  report.errors=errors;
  fs.writeFileSync(path.join(root,prefix+'verification.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
  await browser.close();
})().catch(error=>{console.error(error);process.exit(1)});
