// Prüft, in welcher Form Flutter-Web Beschriftungen ablegt.
import { chromium } from 'playwright';

const browser = await chromium.launch();
const page = await (
  await browser.newContext({ viewport: { width: 430, height: 900 } })
).newPage();

await page.goto('http://localhost:8732/', { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(7000);
await page.mouse.click(215, 300);
await page.waitForTimeout(2000);
for (let i = 0; i < 3; i++) {
  await page.evaluate(() => {
    const b = document.querySelector('flt-semantics-placeholder');
    if (b) b.click();
  });
  await page.waitForTimeout(1500);
}

const out = await page.evaluate(() => {
  const aria = [];
  const text = [];
  for (const node of document.querySelectorAll('flt-semantics')) {
    const a = node.getAttribute('aria-label');
    if (a?.trim()) aria.push(a);
    const own = Array.from(node.childNodes)
      .filter((n) => n.nodeType === Node.TEXT_NODE)
      .map((n) => n.textContent ?? '')
      .join('')
      .trim();
    if (own) text.push(own);
  }
  return { aria, text };
});
console.log('ARIA:', JSON.stringify(out.aria).slice(0, 400));
console.log('TEXT:', JSON.stringify(out.text).slice(0, 400));
await browser.close();
