// Spacestation SP — singleplayer fork defines.
// Everything SP-specific lives under code/modules/spacestation_sp/ so it can be rebased onto upstream.

/// Trait source for anything the SP crew controller adds to its pawn.
#define SP_CREW_TRAIT "spacestation_sp_crew"

// --- Blackboard keys -------------------------------------------------------------------------

/// Title of the job this AI crew member was spawned as (string).
#define BB_SP_JOB_TITLE "sp_job_title"
/// The /area this crew member considers "home" (their department).
#define BB_SP_HOME_AREA "sp_home_area"
/// List of /area typepaths this crew member wanders between. Null = the home area and its subtypes.
#define BB_SP_WANDER_AREAS "sp_wander_areas"
/// Turf we are currently wandering towards.
#define BB_SP_WANDER_TARGET "sp_wander_target"
/// Cooldown key between wander legs.
#define BB_SP_WANDER_COOLDOWN "sp_wander_cooldown"

/// Lazylist of recently heard speech. Each entry is an assoc list, see SP_HEARD_* below.
#define BB_SP_HEARD "sp_heard"
/// A mob who addressed us by name; the social subtree reacts to this and clears it.
#define BB_SP_ATTENTION_TARGET "sp_attention_target"
/// Cooldown key so we do not greet the same chatterbox every second.
#define BB_SP_GREET_COOLDOWN "sp_greet_cooldown"

/// Health value below which crew consider themselves hurt and head for medbay.
#define BB_SP_HURT_THRESHOLD "sp_hurt_threshold"
/// Turf in medbay we are walking to when hurt.
#define BB_SP_MEDBAY_TARGET "sp_medbay_target"
/// Cooldown key for shouting for help.
#define BB_SP_HELP_COOLDOWN "sp_help_cooldown"
/// Cooldown key between attempts to walk to medbay (so a failed path does not thrash every tick).
#define BB_SP_MEDBAY_COOLDOWN "sp_medbay_cooldown"

/// Medical: the mob we are treating.
#define BB_SP_PATIENT "sp_patient"
/// Medical: the medical item we equipped for the current patient.
#define BB_SP_MEDICAL_ITEM "sp_medical_item"

// --- Heard-entry fields ----------------------------------------------------------------------

#define SP_HEARD_SPEAKER "speaker"
#define SP_HEARD_NAME "name"
#define SP_HEARD_MESSAGE "message"
#define SP_HEARD_TIME "time"
#define SP_HEARD_RADIO "radio"
/// How many heard entries a crew member remembers.
#define SP_HEARD_MAX 12

/// Prefix all SP game-log lines so they are easy to grep in data/logs/*/game.log
#define log_sp(msg) log_game("SP: " + (msg))

// --- Threats, attacks and incident reporting -------------------------------------------------

/// A nearby mob wielding a weapon (set by sp_scan_threats, cleared when out of sight for a while).
#define BB_SP_THREAT "sp_threat"
/// world.time we last saw the threat.
#define BB_SP_THREAT_SEEN_AT "sp_threat_seen_at"
/// Cooldown key for warning an armed person.
#define BB_SP_THREAT_WARN_COOLDOWN "sp_threat_warn_cooldown"
/// Distance band (blackboard values) kept from an armed person.
#define BB_SP_THREAT_MIN_DISTANCE "sp_threat_min_distance"
#define BB_SP_THREAT_MAX_DISTANCE "sp_threat_max_distance"
/// The mob that last attacked us (cleared by sp_expire_attacker).
#define BB_SP_ATTACKER "sp_attacker"
/// world.time we were last attacked.
#define BB_SP_ATTACKED_AT "sp_attacked_at"
/// Cooldown key for reporting an attack.
#define BB_SP_REPORT_COOLDOWN "sp_report_cooldown"
/// Turf we flee towards.
#define BB_SP_FLEE_TARGET "sp_flee_target"
/// Structured record of the last incident we reported (assoc list, SP_INCIDENT_* keys). Read by security who hear us.
#define BB_SP_LAST_INCIDENT "sp_last_incident"

// Security response
/// The suspect security is going after.
#define BB_SP_INCIDENT_TARGET "sp_incident_target"
/// Where the incident was reported from.
#define BB_SP_INCIDENT_LOCATION "sp_incident_location"
/// Cooldown key for acknowledging reports over the radio.
#define BB_SP_ACK_COOLDOWN "sp_ack_cooldown"
/// Security: equipped weapon / restraints.
#define BB_SP_WEAPON "sp_weapon"
#define BB_SP_CUFFS "sp_cuffs"

#define SP_INCIDENT_ATTACKER "attacker"
#define SP_INCIDENT_VICTIM "victim"
#define SP_INCIDENT_TURF "turf"
#define SP_INCIDENT_TIME "time"

// --- Engineering -----------------------------------------------------------------------------

/// Turf in the engine room the engineer walks to.
#define BB_SP_ENGINE_TARGET "sp_engine_target"
/// Cooldown key between engine checks.
#define BB_SP_ENGINE_COOLDOWN "sp_engine_cooldown"

// --- Hull breaches ----------------------------------------------------------------------------

/// The space turf we are on our way to patch.
#define BB_SP_BREACH_TARGET "sp_breach_target"
/// The safe floor turf we stand on while patching it.
#define BB_SP_BREACH_STANDPOINT "sp_breach_standpoint"
/// Cooldown between breach repair attempts.
#define BB_SP_BREACH_COOLDOWN "sp_breach_cooldown"
/// Cooldown for announcing a breach over the radio.
#define BB_SP_BREACH_ANNOUNCE_COOLDOWN "sp_breach_announce_cooldown"
/// The RCD we equipped for repairs.
#define BB_SP_RCD "sp_rcd"
/// Assoc list of breach turf -> world.time after which we will try it again.
#define BB_SP_BREACH_IGNORE "sp_breach_ignore"
/// The breach we are currently walking to, and when we started walking.
#define BB_SP_BREACH_ATTEMPT "sp_breach_attempt"
#define BB_SP_BREACH_ATTEMPT_AT "sp_breach_attempt_at"
/// How long an engineer keeps trying to reach one breach before writing it off.
#define SP_BREACH_ATTEMPT_TIMEOUT (90 SECONDS)
/// How long a written-off breach stays ignored.
#define SP_BREACH_IGNORE_TIME (5 MINUTES)

// --- Botany -----------------------------------------------------------------------------------

/// The hydroponics tray we are walking to.
#define BB_SP_TRAY "sp_tray"
/// What we intend to do with it: one of the SP_TRAY_JOB_* values below.
#define BB_SP_TRAY_JOB "sp_tray_job"
/// The tool or seed we equipped for that job.
#define BB_SP_BOTANY_TOOL "sp_botany_tool"
/// Produce lying on the floor that we are about to pick up.
#define BB_SP_PRODUCE "sp_produce"
/// The kitchen table we deliver produce to.
#define BB_SP_DELIVERY_TARGET "sp_delivery_target"
/// The hydroponics table we leave sample produce on.
#define BB_SP_SAMPLE_TABLE "sp_sample_table"
/// A water source we are walking to in order to refill the watering can.
#define BB_SP_WATER_SOURCE "sp_water_source"
/// Cooldowns.
#define BB_SP_BOTANY_COOLDOWN "sp_botany_cooldown"
#define BB_SP_DELIVERY_COOLDOWN "sp_delivery_cooldown"
#define BB_SP_SAMPLE_COOLDOWN "sp_sample_cooldown"

/// Tray jobs, in the order the botanist prefers them.
#define SP_TRAY_JOB_HARVEST "harvest"
#define SP_TRAY_JOB_CLEAR "clear"
#define SP_TRAY_JOB_WEED "weed"
#define SP_TRAY_JOB_WATER "water"
#define SP_TRAY_JOB_PLANT "plant"

/// How much produce a botanist gathers before walking a delivery to the kitchen.
#define SP_PRODUCE_DELIVERY_BATCH 5
