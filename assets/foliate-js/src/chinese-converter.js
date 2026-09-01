import * as OpenCC from './vendor/opencc.js';

const openccConverters = new Map();

export const getOpenCCConverter = (mode) => {
  if (!mode || mode === 'none') return null;
  if (openccConverters.has(mode)) {
    return openccConverters.get(mode);
  }
  let converter;
  switch (mode) {
    case 's2t':
      converter = OpenCC.Converter({ from: 'cn', to: 't' });
      break;
    case 't2s':
      converter = OpenCC.Converter({ from: 't', to: 'cn' });
      break;
    case 's2tw':
      converter = OpenCC.Converter({ from: 'cn', to: 'tw' });
      break;
    case 'tw2s':
      converter = OpenCC.Converter({ from: 'tw', to: 'cn' });
      break;
    case 's2hk':
      converter = OpenCC.Converter({ from: 'cn', to: 'hk' });
      break;
    case 'hk2s':
      converter = OpenCC.Converter({ from: 'hk', to: 'cn' });
      break;
    default:
      return null;
  }
  openccConverters.set(mode, converter);
  return converter;
};

export const langMap = {
  s2t: 'zh-Hant',
  t2s: 'zh-Hans',
  s2tw: 'zh-TW',
  s2hk: 'zh-HK',
  tw2s: 'zh-CN',
  hk2s: 'zh-CN',
};

export const convertChineseDocument = (mode, doc) => {
  if (!mode || mode === 'none' || !doc?.body) return;
  const converter = getOpenCCConverter(mode);
  if (!converter) return;

  // 1. Update lang attribute on html/documentElement for OpenType native glyph selection
  if (langMap[mode] && doc.documentElement) {
    doc.documentElement.lang = langMap[mode];
  }

  // 2. High-performance TreeWalker traversing text nodes only, ignoring scripts/styles/code/pre
  const showTextFilter = doc.defaultView?.NodeFilter?.SHOW_TEXT ?? (typeof NodeFilter !== 'undefined' ? NodeFilter.SHOW_TEXT : 4);
  const filterAccept = doc.defaultView?.NodeFilter?.FILTER_ACCEPT ?? (typeof NodeFilter !== 'undefined' ? NodeFilter.FILTER_ACCEPT : 1);
  const filterReject = doc.defaultView?.NodeFilter?.FILTER_REJECT ?? (typeof NodeFilter !== 'undefined' ? NodeFilter.FILTER_REJECT : 2);

  const walker = doc.createTreeWalker(
    doc.body,
    showTextFilter,
    {
      acceptNode: (node) => {
        const parentTag = node.parentNode?.nodeName?.toUpperCase();
        if (['SCRIPT', 'STYLE', 'NOSCRIPT', 'CODE', 'PRE'].includes(parentTag)) {
          return filterReject;
        }
        return node.nodeValue && node.nodeValue.trim().length > 0
          ? filterAccept
          : filterReject;
      }
    }
  );

  let textNode;
  while ((textNode = walker.nextNode())) {
    const original = textNode.nodeValue;
    const converted = converter(original);
    if (original !== converted) {
      textNode.nodeValue = converted;
    }
  }
};
