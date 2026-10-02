/**
 * Automated picture scan for the Designer unlock: Google Cloud Vision
 * SafeSearch on every new upload (designer.ts `scanVerdict` reads the answer).
 *
 * Config (Nakama runtime env, docs/deploy.md): GOOGLE_VISION_API_KEY. Without
 * it nothing is scanned and every new picture waits for a person in the
 * moderation queue, so custom art only appears once someone approved it.
 */
import { scanVerdict, type ArtStatus } from './designer';

const VISION_URL = 'https://vision.googleapis.com/v1/images:annotate?key=';
const HTTP_TIMEOUT_MS = 5000;

export function visionKey(env: { [key: string]: string } | undefined): string {
  return env && typeof env['GOOGLE_VISION_API_KEY'] === 'string' ? env['GOOGLE_VISION_API_KEY'].trim() : '';
}

/**
 * The verdict for one base64 image, and whether a scanner gave it.
 * Never throws: a scanner that cannot be reached leaves the picture pending.
 */
export function scanArt(nk: nkruntime.Nakama, logger: nkruntime.Logger, env: { [key: string]: string } | undefined, imageBase64: string): { status: ArtStatus; scanned: boolean } {
  const key = visionKey(env);
  if (!key) return { status: 'pending', scanned: false };
  const body = JSON.stringify({ requests: [{ image: { content: imageBase64 }, features: [{ type: 'SAFE_SEARCH_DETECTION' }] }] });
  try {
    const res = nk.httpRequest(VISION_URL + encodeURIComponent(key), 'post', { 'Content-Type': 'application/json' }, body, HTTP_TIMEOUT_MS);
    if (res.code !== 200) {
      logger.warn('vision answered %d', res.code);
      return { status: 'pending', scanned: false };
    }
    return { status: scanVerdict(JSON.parse(res.body)), scanned: true };
  } catch (e) {
    logger.warn('vision scan failed: %s', String(e));
    return { status: 'pending', scanned: false };
  }
}
