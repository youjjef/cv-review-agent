/**
 * Locker-safe PDF embedded-text extractor for FlowCV / Chrome-printed CVs.
 * Handles FlateDecode streams, hex CID Tj operators, and ToUnicode CMaps.
 * No PDF.js / web workers.
 */

function decodeLatin1(bytes) {
    let s = '';
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
        const slice = bytes.subarray(i, i + chunk > bytes.length ? bytes.length - i : chunk);
        const args = [];
        for (let j = 0; j < slice.length; j++) {
            args.push(slice[j]);
        }
        s += String.fromCharCode.apply(null, args);
    }
    return s;
}

function unescapePdfString(raw) {
    if (!raw) {
        return '';
    }
    return raw
        .replace(/\\n/g, '\n')
        .replace(/\\r/g, '\r')
        .replace(/\\t/g, '\t')
        .replace(/\\\(/g, '(')
        .replace(/\\\)/g, ')')
        .replace(/\\\\/g, '\\')
        .replace(/\\([0-7]{1,3})/g, (_, oct) => String.fromCharCode(parseInt(oct, 8)));
}

async function inflateFlate(bytes) {
    if (typeof DecompressionStream === 'undefined') {
        return null;
    }
    // zlib-wrapped (standard PDF FlateDecode)
    try {
        const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate'));
        return new Uint8Array(await new Response(stream).arrayBuffer());
    } catch (e1) {
        // raw deflate: skip zlib CMF/FLG, drop trailing Adler32
    }
    if (bytes.length > 6) {
        try {
            const raw = bytes.subarray(2, bytes.length - 4);
            const stream = new Blob([raw]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
            return new Uint8Array(await new Response(stream).arrayBuffer());
        } catch (e2) {
            try {
                const stream = new Blob([bytes.subarray(2)]).stream().pipeThrough(
                    new DecompressionStream('deflate-raw')
                );
                return new Uint8Array(await new Response(stream).arrayBuffer());
            } catch (e3) {
                return null;
            }
        }
    }
    return null;
}

function indexOfBytes(haystack, needle, fromIdx) {
    outer: for (let i = fromIdx; i <= haystack.length - needle.length; i++) {
        for (let j = 0; j < needle.length; j++) {
            if (haystack[i + j] !== needle[j]) {
                continue outer;
            }
        }
        return i;
    }
    return -1;
}

const STREAM = [0x73, 0x74, 0x72, 0x65, 0x61, 0x6d];
const ENDSTREAM = [0x65, 0x6e, 0x64, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d];

function readDictWindow(bytes, streamIdx) {
    const start = Math.max(0, streamIdx - 1200);
    return decodeLatin1(bytes.subarray(start, streamIdx));
}

function parseLength(dictWindow) {
    const m = dictWindow.match(/\/Length\s+(\d+)/);
    return m ? parseInt(m[1], 10) : null;
}

function isFlate(dictWindow) {
    return /\/FlateDecode/.test(dictWindow) || /\/Filter\s*\/Fl\b/.test(dictWindow);
}

function isToUnicodeCmap(text) {
    return /beginbfchar|beginbfrange|begincmap/.test(text);
}

/**
 * Parse Adobe-Identity ToUnicode CMap into Map(cidNumber -> string)
 */
function parseToUnicode(cmapText) {
    const map = new Map();
    if (!cmapText) {
        return map;
    }

    const bfchar = /beginbfchar([\s\S]*?)endbfchar/g;
    let block;
    while ((block = bfchar.exec(cmapText)) !== null) {
        const pairRe = /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g;
        let p;
        while ((p = pairRe.exec(block[1])) !== null) {
            const cid = parseInt(p[1], 16);
            map.set(cid, hexToUnicode(p[2]));
        }
    }

    const bfrange = /beginbfrange([\s\S]*?)endbfrange/g;
    while ((block = bfrange.exec(cmapText)) !== null) {
        const rangeRe = /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g;
        let r;
        while ((r = rangeRe.exec(block[1])) !== null) {
            const start = parseInt(r[1], 16);
            const end = parseInt(r[2], 16);
            let unicode = parseInt(r[3], 16);
            for (let cid = start; cid <= end; cid++) {
                map.set(cid, String.fromCodePoint(unicode));
                unicode++;
            }
        }
        // array form: <start> <end> [<u1> <u2> ...]
        const arrRe = /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[([^\]]+)\]/g;
        while ((r = arrRe.exec(block[1])) !== null) {
            let cid = parseInt(r[1], 16);
            const end = parseInt(r[2], 16);
            const hexes = r[3].match(/<([0-9A-Fa-f]+)>/g) || [];
            for (let i = 0; i < hexes.length && cid <= end; i++, cid++) {
                const h = hexes[i].replace(/[<>]/g, '');
                map.set(cid, hexToUnicode(h));
            }
        }
    }
    return map;
}

function hexToUnicode(hex) {
    const clean = hex.replace(/\s+/g, '');
    if (clean.length === 0) {
        return '';
    }
    // PDF ToUnicode values are big-endian UTF-16 code units (often 4 hex digits = 1 BMP char)
    let out = '';
    for (let i = 0; i + 3 < clean.length; i += 4) {
        const unit = parseInt(clean.substring(i, i + 4), 16);
        if (!unit) {
            continue;
        }
        out += String.fromCharCode(unit);
    }
    if (!out && clean.length >= 2) {
        // odd-length fallback: treat as single codepoint hex
        out = String.fromCodePoint(parseInt(clean, 16));
    }
    return out;
}

function mergeMaps(target, source) {
    source.forEach((v, k) => {
        if (!target.has(k)) {
            target.set(k, v);
        }
    });
}

function mapCidHex(hex, toUnicode) {
    const clean = hex.replace(/\s+/g, '');
    let out = '';
    // CIDs are typically 2-byte (4 hex digits) for Identity-H
    const width = clean.length % 4 === 0 ? 4 : 2;
    for (let i = 0; i + width - 1 < clean.length; i += width) {
        const cid = parseInt(clean.substring(i, i + width), 16);
        if (toUnicode.has(cid)) {
            out += toUnicode.get(cid);
        } else if (cid >= 32 && cid < 127) {
            out += String.fromCharCode(cid);
        } else {
            // keep placeholder only if no map; skip unknowns
        }
    }
    return out;
}

function extractTextFromContent(content, toUnicode) {
    if (!content) {
        return '';
    }
    const parts = [];

    // Hex CID strings: <003C> Tj   or   <003C0052> Tj
    const hexTj = /<([0-9A-Fa-f\s]+)>\s*(?:Tj|'|")/g;
    let m;
    while ((m = hexTj.exec(content)) !== null) {
        parts.push(mapCidHex(m[1], toUnicode));
    }

    // Hex array TJ: [ <003C> <0052> ] TJ  or mixed
    const hexTJ = /\[([\s\S]*?)\]\s*TJ/g;
    while ((m = hexTJ.exec(content)) !== null) {
        const inner = m[1];
        const hexes = inner.match(/<([0-9A-Fa-f\s]+)>/g) || [];
        for (let i = 0; i < hexes.length; i++) {
            parts.push(mapCidHex(hexes[i].replace(/[<>]/g, ''), toUnicode));
        }
        const lits = inner.match(/\((?:\\.|[^\\)])*\)/g) || [];
        for (let i = 0; i < lits.length; i++) {
            parts.push(unescapePdfString(lits[i].substring(1, lits[i].length - 1)));
        }
    }

    // Literal strings (simple PDFs)
    const litTj = /\((?:\\.|[^\\)])*\)\s*(?:Tj|'|")/g;
    while ((m = litTj.exec(content)) !== null) {
        const full = m[0];
        const open = full.indexOf('(');
        const close = full.lastIndexOf(')');
        if (open >= 0 && close > open) {
            parts.push(unescapePdfString(full.substring(open + 1, close)));
        }
    }

    return parts.join('');
}

/**
 * @param {ArrayBuffer|Uint8Array} input
 * @returns {Promise<string>}
 */
export async function extractPdfEmbeddedText(input) {
    const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
    if (bytes.length < 8) {
        return '';
    }
    if (!(bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46)) {
        return '';
    }

    const toUnicode = new Map();
    const contentChunks = [];
    let pos = 0;

    while (pos < bytes.length) {
        const streamIdx = indexOfBytes(bytes, STREAM, pos);
        if (streamIdx < 0) {
            break;
        }
        const before = streamIdx === 0 ? 32 : bytes[streamIdx - 1];
        if ((before >= 65 && before <= 90) || (before >= 97 && before <= 122)) {
            pos = streamIdx + 6;
            continue;
        }

        const dictWindow = readDictWindow(bytes, streamIdx);
        let dataStart = streamIdx + 6;
        if (bytes[dataStart] === 0x0d) {
            dataStart++;
        }
        if (bytes[dataStart] === 0x0a) {
            dataStart++;
        }

        const declaredLength = parseLength(dictWindow);
        let dataEnd;
        if (declaredLength != null && dataStart + declaredLength <= bytes.length) {
            dataEnd = dataStart + declaredLength;
        } else {
            const endIdx = indexOfBytes(bytes, ENDSTREAM, dataStart);
            if (endIdx < 0) {
                break;
            }
            dataEnd = endIdx;
            while (dataEnd > dataStart && (bytes[dataEnd - 1] === 0x0a || bytes[dataEnd - 1] === 0x0d)) {
                dataEnd--;
            }
        }

        const payload = bytes.subarray(dataStart, dataEnd);
        let contentBytes = payload;
        if (isFlate(dictWindow)) {
            const inflated = await inflateFlate(payload);
            if (!inflated) {
                pos = Math.max(dataEnd, streamIdx + 6);
                continue;
            }
            contentBytes = inflated;
        }

        const text = decodeLatin1(contentBytes);
        if (isToUnicodeCmap(text)) {
            mergeMaps(toUnicode, parseToUnicode(text));
        } else if (/Tj\b|TJ\b|\bBT\b/.test(text)) {
            contentChunks.push(text);
        }

        pos = Math.max(dataEnd, streamIdx + 6);
    }

    // Second pass: map content with collected ToUnicode
    const pieces = [];
    for (let i = 0; i < contentChunks.length; i++) {
        const extracted = extractTextFromContent(contentChunks[i], toUnicode);
        if (extracted && extracted.trim()) {
            pieces.push(extracted.trim());
        }
    }

    // If ToUnicode arrived after content in file order, contentChunks already held;
    // remapping above uses full map. If empty, try whole-file fallback on inflated contents only.
    let joined = pieces.join('\n');
    if (!joined.trim() && contentChunks.length) {
        // Retry without map (won't help CIDs) — attempt combining all cmap+content again
        joined = contentChunks.map((c) => extractTextFromContent(c, toUnicode)).join('\n');
    }

    return normalizeExtractedText(joined);
}

/**
 * FlowCV text is often one run-on string. Insert line breaks before headers,
 * bullets, dates, and a glued email so the Apex parser can see sections.
 */
function normalizeExtractedText(text) {
    if (!text) {
        return '';
    }
    let t = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    // Split NameEmail@domain (Mohamedyousseffj78@gmail.com)
    t = t.replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, (full, offset, whole) => {
        const at = full.indexOf('@');
        const local = full.slice(0, at);
        const domain = full.slice(at);
        const before = String(whole).slice(0, offset).trim();
        const words = before.split(/\s+/).filter(Boolean);
        const hint = words.length ? words[words.length - 1].toLowerCase() : '';
        let best = null;
        let bestScore = -1;
        for (let lowerLen = 2; lowerLen <= 20; lowerLen++) {
            if (1 + lowerLen >= local.length) {
                continue;
            }
            const namePart = local.slice(0, 1 + lowerLen);
            const emailLocal = local.slice(1 + lowerLen);
            if (!/^[A-Z][a-z]+$/.test(namePart) || !/^[a-z][a-z0-9._%+-]*\d[a-z0-9._%+-]*$/.test(emailLocal)) {
                continue;
            }
            const digitAt = emailLocal.search(/\d/);
            if (digitAt < 5) {
                continue;
            }
            let score = lowerLen;
            if (hint.length >= 4 && emailLocal.toLowerCase().startsWith(hint.slice(0, 4))) {
                score += 1000;
            }
            if (score > bestScore) {
                bestScore = score;
                best = `${namePart}\n${emailLocal}${domain}`;
            }
        }
        return best || full;
    });
    // Multi-word headers even when glued to the next word (no word boundary).
    t = t.replace(
        /(professional experience|work experience|technical skills|core competencies)/gi,
        '\n$1\n'
    );
    // Only when glued to the next word (EXPERIENCESalesforce), not inside PROFESSIONAL EXPERIENCE
    t = t.replace(
        /(CERTIFICATIONS|EMPLOYMENT|EDUCATION|EXPERIENCE|SKILLS|SUMMARY|PROFILE|PROJECTS|LANGUAGES|ACADEMIC)(?=[A-Z])/g,
        '\n$1\n'
    );
    // "LWC.Cloud Engineer, Huawei" -> role on its own line
    t = t.replace(/([.a-z])([A-Z][A-Za-z]+(?: [A-Z][A-Za-z]+)*, [A-Z])/g, '$1\n$2');
    t = t.replace(
        /\s+[–—-]\s+(\d{1,2}\/\d{2,4}|\d{4})\s+[–—-]\s+(Present|Current|\d{1,2}\/\d{2,4}|\d{4})(?!\d)/gi,
        '\n$1 - $2\n'
    );
    t = t.replace(
        /(\d{1,2}\/\d{2,4})\s*[–—-]\s*(Present|Current|\d{1,2}\/\d{2,4}|\d{4})/gi,
        '\n$1 - $2\n'
    );
    t = t.replace(/([A-Za-z)\]])(\d{1,2}\/\d{2,4})/g, '$1\n$2');
    t = t.replace(/•/g, '\n• ');
    t = t.replace(/\s+(LinkedIn|GitHub)\b/gi, '\n$1');
    t = t.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').replace(/[^\S\n]{2,}/g, ' ');
    return t.trim();
}
