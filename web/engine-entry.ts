// What web/big-business.html takes from the server: the rules engine, both
// bot policies and the tutorial seed. build.mjs bundles it as the global BB.
export { COMPANIES, applyAction, autoAction, botAction, createGame, playerView } from '../server/src/engine';
export { TUTORIAL_SEED } from '../server/src/match/protocol';
