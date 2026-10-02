/** The match loop's "your turn" step: decides once per turn whether to push. */
import { PUSH_MAX_FAILURES, shouldPush } from './push';
import { sendYourTurn } from './push_sender';
import { readRemoteConfig } from './rpc_config';
import type { MatchState } from './state';

/**
 * Called every tick; acts only when a new turn starts. Storage and HTTP
 * are touched only when the turn belongs to a person who is away.
 */
export function pushTurnIfAway(s: MatchState, ctx: nkruntime.Context, nk: nkruntime.Nakama, logger: nkruntime.Logger, nowMs: number): void {
  const g = s.game;
  if (!g || g.phase === 'ended' || s.playStartsAt > 0 || s.pushFailures >= PUSH_MAX_FAILURES) return;
  const key = g.turn + ':' + g.active;
  if (key === s.pushTurnKey) return;
  s.pushTurnKey = key;
  const seat = g.seats[g.active];
  if (!seat || seat.isBot || seat.id.startsWith('bot:')) return;
  const connected = seat.connected && s.presences[seat.id] !== undefined;
  if (connected || s.forfeited[seat.id] || s.params.tutorial) return;
  const cfg = readRemoteConfig(nk);
  if (!cfg.pushEnabled) return;
  const due = shouldPush({
    human: true,
    connected,
    forfeited: false,
    tutorial: false,
    stepSeconds: s.params.stepSeconds,
    lastSentAt: s.pushSentAt[seat.id] || 0,
    nowMs,
    cooldownMs: cfg.pushCooldownMinutes * 60_000,
    failures: s.pushFailures,
  });
  if (!due) return;
  const outcome = sendYourTurn(nk, logger, ctx.env, seat.id, ctx.matchId || '', s.params.stepSeconds);
  if (outcome === 'sent') s.pushSentAt[seat.id] = nowMs;
  if (outcome === 'failed') s.pushFailures++;
  // WHY 'unconfigured' also stops the match trying: without FCM settings no
  // later turn can succeed either, so skip the config read from now on.
  if (outcome === 'unconfigured') s.pushFailures = PUSH_MAX_FAILURES;
}
