import assert from 'node:assert/strict'
import test from 'node:test'
import { JSDOM } from 'jsdom'
import { getOpenCCConverter, convertChineseDocument } from '../src/chinese-converter.js'

test('GIVEN s2t mode, WHEN converting polysemous words (一简多繁), THEN accurately disambiguates without errors', () => {
  const s2t = getOpenCCConverter('s2t')
  assert.ok(s2t)

  // 头发 vs 发展
  assert.equal(s2t('她的头发很黑'), '她的頭髮很黑')
  assert.equal(s2t('经济快速发展'), '經濟快速發展')

  // 皇后 vs 前后
  assert.equal(s2t('她是尊贵的皇后'), '她是尊貴的皇后')
  assert.equal(s2t('走在队伍前后'), '走在隊伍前後')

  // 干燥 vs 干活 vs 干涉
  assert.equal(s2t('气候非常干燥'), '氣候非常乾燥')
  assert.equal(s2t('大家一起干活'), '大家一起幹活')
  assert.equal(s2t('请不要干涉内政'), '請不要干涉內政')

  // 只有 vs 一只鸟
  assert.equal(s2t('只有努力才能成功'), '只有努力才能成功')
  assert.equal(s2t('树上有一只小鸟'), '樹上有一隻小鳥')
})

test('GIVEN s2tw mode, WHEN converting modern text, THEN uses Taiwan standard characters', () => {
  const s2tw = getOpenCCConverter('s2tw')
  assert.ok(s2tw)

  assert.equal(s2tw('今天中午去吃面'), '今天中午去吃麵')
  assert.equal(s2tw('水立方物体的表面'), '水立方物體的表面')
})

test('GIVEN t2s mode, WHEN converting traditional text, THEN accurately converts to simplified', () => {
  const t2s = getOpenCCConverter('t2s')
  assert.ok(t2s)

  assert.equal(t2s('她的頭髮很黑，經濟快速發展'), '她的头发很黑，经济快速发展')
  assert.equal(t2s('今天中午去吃麵，氣候非常乾燥'), '今天中午去吃面，气候非常干燥')
})

test('GIVEN HTML document, WHEN convertChineseDocument is called, THEN updates text and html lang attribute safely', () => {
  const dom = new JSDOM(`<!doctype html><html lang="zh-CN"><body><p>她的头发很长，走在队伍前后。</p><script>var x = "头发";</script></body></html>`)
  globalThis.NodeFilter = dom.window.NodeFilter

  convertChineseDocument('s2t', dom.window.document)

  assert.equal(dom.window.document.documentElement.lang, 'zh-Hant')
  assert.equal(dom.window.document.querySelector('p').textContent, '她的頭髮很長，走在隊伍前後。')
  // Script content must not be mutated
  assert.equal(dom.window.document.querySelector('script').textContent, 'var x = "头发";')
})
