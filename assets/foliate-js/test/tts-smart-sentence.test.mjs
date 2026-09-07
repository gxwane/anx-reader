import assert from 'node:assert/strict'
import test from 'node:test'
import { JSDOM } from 'jsdom'
import { getBlocks } from '../src/tts.js'

const createDocument = (html) => {
  const dom = new JSDOM(`<!doctype html><html><body>${html}</body></html>`)
  globalThis.document = dom.window.document
  globalThis.NodeFilter = dom.window.NodeFilter
  globalThis.Range = dom.window.Range
  return dom.window.document
}

const getSentences = (html) => {
  const doc = createDocument(html)
  return Array.from(getBlocks(doc)).map(r => r.toString())
}

test('GIVEN dialogue with exclamation followed by attribution, THEN merges into single sentence', () => {
  const sentences = getSentences('<p>“我去！”他震惊地喊道。</p>')
  assert.deepEqual(sentences, ['“我去！”他震惊地喊道。'])
})

test('GIVEN dialogue with question followed by attribution, THEN merges into single sentence', () => {
  const sentences = getSentences('<p>“真的吗？”老人疑惑地问。</p>')
  assert.deepEqual(sentences, ['“真的吗？”老人疑惑地问。'])
})

test('GIVEN dialogue with period followed by attribution, THEN merges into single sentence', () => {
  const sentences = getSentences('<p>“好的。”他说。</p>')
  assert.deepEqual(sentences, ['“好的。”他说。'])
})

test('GIVEN multiple sentences inside quotes followed by attribution, THEN only merges last clause with attribution', () => {
  const sentences = getSentences('<p>“天哪！太神奇了！”他惊呼道。</p>')
  assert.deepEqual(sentences, ['“天哪！', '太神奇了！”他惊呼道。'])
})

test('GIVEN consecutive quotes without attribution, THEN does NOT merge', () => {
  const sentences = getSentences('<p>“我知道了。”“那你还不快去？”</p>')
  assert.deepEqual(sentences, ['“我知道了。”', '“那你还不快去？”'])
})

test('GIVEN quote followed by non-attribution narrative, THEN does NOT merge', () => {
  const sentences = getSentences('<p>“真相就是这样。”随后大地剧烈震颤，敌军发起了总攻。</p>')
  assert.deepEqual(sentences, ['“真相就是这样。”', '随后大地剧烈震颤，敌军发起了总攻。'])
})

test('GIVEN dialogue and attribution spanning across multiple HTML tags, THEN merges correctly', () => {
  const sentences = getSentences('<p><span>“我去！”</span><span>他震惊地喊道。</span></p>')
  assert.deepEqual(sentences, ['“我去！”他震惊地喊道。'])
})

test('GIVEN corner quotes (Japanese/Traditional Chinese), THEN merges attribution', () => {
  const sentences = getSentences('<p>「等等！」少女急忙喊道。</p>')
  assert.deepEqual(sentences, ['「等等！」少女急忙喊道。'])
})

test('GIVEN English dialogue followed by attribution, THEN merges into single sentence', () => {
  const sentences = getSentences('<p>"No!" she cried.</p>')
  assert.deepEqual(sentences, ['"No!" she cried.'])
})
