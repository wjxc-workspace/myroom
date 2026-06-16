// Cloud Functions entry point — exports every callable + trigger.
//
// Phase 0: lifecycle triggers (provisionUser, deleteUserData).
// Phase 1: storageCascade onDelete triggers (notes/recaps/achievements).
// Phase 2: the 7 AI callables + the remaining 4 triggers (AI_proxy.md §1).
import "./lib/admin";

// ── Lifecycle / storage triggers (Phase 0–1) ──────────────────────────────
export { provisionUser } from "./triggers/provisionUser";
export { deleteUserData } from "./triggers/deleteUserData";
export {
  storageCascadeNote,
  storageCascadeRecap,
  storageCascadeAchievement,
} from "./triggers/storageCascade";

// ── AI callables (Phase 2) ────────────────────────────────────────────────
export { chat } from "./callable/chat";
export { applyChatActions } from "./callable/applyChatActions";
export { classifyMultiInput } from "./callable/classifyMultiInput";
export { fetchRecommendations } from "./callable/fetchRecommendations";
export { generateEraInsight } from "./callable/generateEraInsight";
export { transcribe } from "./callable/transcribe";
export { exportRecap } from "./callable/exportRecap";
export { exportAchievement } from "./callable/exportAchievement";

// ── AI / denormalization triggers (Phase 2) ───────────────────────────────
export { enrichIdea } from "./triggers/enrichIdea";
export { classifyNote } from "./triggers/classifyNote";
export { findNotesForCategory } from "./triggers/findNotesForCategory";
export {
  categoryFanoutTodo,
  categoryFanoutNote,
} from "./triggers/categoryFanout";
