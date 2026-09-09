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

// Deeper botany: extraction, buying and mutation.
/// The seed extractor we are carrying produce to.
#define BB_SP_EXTRACTOR "sp_extractor"
/// Produce we intend to turn into seeds.
#define BB_SP_EXTRACT_ITEM "sp_extract_item"
/// The MegaSeed Servitor we are shopping at.
#define BB_SP_SEED_VENDOR "sp_seed_vendor"
/// A tray we are about to dose with mutagen.
#define BB_SP_MUTATE_TRAY "sp_mutate_tray"
/// Species (seed typepaths) this botanist has grown at least once.
#define BB_SP_KNOWN_SPECIES "sp_known_species"
/// Cooldowns for the slower botany errands.
#define BB_SP_EXTRACT_COOLDOWN "sp_extract_cooldown"
#define BB_SP_SHOP_COOLDOWN "sp_shop_cooldown"
#define BB_SP_MUTATE_COOLDOWN "sp_mutate_cooldown"

/// Instability at which a plant is already likely to mutate on its own; no need to add mutagen.
#define SP_MUTAGEN_INSTABILITY_TARGET 60
/// The tray the botanist has committed to as their current mutation experiment.
#define BB_SP_EXPERIMENT_TRAY "sp_experiment_tray"

// --- Conversation and standing ------------------------------------------------------------------

/// The person we are talking to.
#define BB_SP_CHAT_PARTNER "sp_chat_partner"
/// The /datum/sp_topic we are talking about.
#define BB_SP_CHAT_TOPIC "sp_chat_topic"
/// How far through the exchange we are: 0 opener, 1 reply, 2 closer.
#define BB_SP_CHAT_STAGE "sp_chat_stage"
/// Set when somebody has said something to us that we owe an answer to.
#define BB_SP_CHAT_REPLY_DUE "sp_chat_reply_due"
/// What they said, so the answer can suit it.
#define BB_SP_CHAT_HEARD "sp_chat_heard"
/// Cooldown before we start another conversation of our own.
#define BB_SP_CHAT_COOLDOWN "sp_chat_cooldown"
/// Cooldown on remarks made to the whole station over common.
#define BB_SP_YAP_COOLDOWN "sp_yap_cooldown"
/// Who we have already introduced ourselves to, so we do not greet the same person every minute.
#define BB_SP_GREETED "sp_greeted"
/// Assoc list of person -> how well we think of them.
#define BB_SP_REPUTATION "sp_reputation"

/// Standing thresholds.
#define SP_REP_FRIENDLY 4
#define SP_REP_HOSTILE -4

// --- Cargo ---------------------------------------------------------------------------------------

/// The cargo console the quartermaster works at.
#define BB_SP_CARGO_CONSOLE "sp_cargo_console"
/// A crate we are hauling, and where we are hauling it to.
#define BB_SP_CRATE "sp_crate"
#define BB_SP_CRATE_DESTINATION "sp_crate_destination"
/// Cooldowns for the quartermaster's paperwork and the shuttle run.
#define BB_SP_ORDER_COOLDOWN "sp_order_cooldown"
#define BB_SP_SHUTTLE_COOLDOWN "sp_shuttle_cooldown"
#define BB_SP_HAUL_COOLDOWN "sp_haul_cooldown"

/// Supply request states.
#define SP_REQUEST_PENDING "pending"
#define SP_REQUEST_ORDERED "ordered"
#define SP_REQUEST_DELIVERED "delivered"
/// Who to tell when we actually pick a requested crate up.
#define BB_SP_CRATE_ANNOUNCE "sp_crate_announce"
/// When the current haul is abandoned if the crate has not reached its destination.
#define BB_SP_HAUL_DEADLINE "sp_haul_deadline"
/// How long one crate may be dragged before we give up on it.
#define SP_HAUL_TIMEOUT (2 MINUTES)

// --- Kitchen ---------------------------------------------------------------------------------------

/// The kitchen table the chef works at: ingredients are piled on it and dishes are assembled beside it.
#define BB_SP_PREP_TABLE "sp_prep_table"
/// The counter finished food is left on for the crew to take.
#define BB_SP_COUNTER "sp_counter"
/// A finished dish we are carrying out to the counter.
#define BB_SP_DISH "sp_dish"
/// The /datum/sp_prep_step we are carrying out, the item it applies to, and where we have to stand.
#define BB_SP_PREP_STEP "sp_prep_step"
#define BB_SP_PREP_ITEM "sp_prep_item"
/// The rest of the load going into the same machine on the same trip.
#define BB_SP_PREP_BATCH "sp_prep_batch"
#define BB_SP_PREP_TARGET "sp_prep_target"
/// The /datum/sp_kitchen_mix we are mixing, the bowl we are mixing it in, and where we are going next.
#define BB_SP_MIX "sp_mix"
#define BB_SP_MIX_BOWL "sp_mix_bowl"
#define BB_SP_MIX_TARGET "sp_mix_target"
/// A cooking machine holding food that has finished cooking.
#define BB_SP_COOK_MACHINE "sp_cook_machine"
/// Where the next load of ingredients is coming from.
#define BB_SP_STOCK_SOURCE "sp_stock_source"
/// Cooldowns for each strand of kitchen work.
#define BB_SP_COOK_COOLDOWN "sp_cook_cooldown"
#define BB_SP_PREP_COOLDOWN "sp_prep_cooldown"
#define BB_SP_MIX_COOLDOWN "sp_mix_cooldown"
#define BB_SP_COLLECT_COOLDOWN "sp_collect_cooldown"
#define BB_SP_STOCK_COOLDOWN "sp_stock_cooldown"
#define BB_SP_SERVE_COOLDOWN "sp_serve_cooldown"
/// Cooldown on asking cargo for another food crate.
#define BB_SP_KITCHEN_SUPPLY_COOLDOWN "sp_kitchen_supply_cooldown"

/// What a prep step does to its ingredient.
/// Use a held tool on it while it sits on the prep table (knife, rolling pin).
#define SP_PREP_TOOL "tool"
/// Lay it on the griddle and switch the griddle on.
#define SP_PREP_GRILL "grill"
/// Open the oven, put it on the tray, close the oven.
#define SP_PREP_BAKE "bake"
/// Feed it to the food processor and run it.
#define SP_PREP_PROCESS "process"

/// Verbose kitchen tracing, enabled by SP_KITCHEN_DEBUG in code/_compile_options.dm.
#ifdef SP_KITCHEN_DEBUG
#define log_kitchen(msg) log_sp("kitchen: " + (msg))
#else
#define log_kitchen(msg)
#endif

/// How many finished dishes may sit on the counter before the chef stops cooking.
#define SP_COUNTER_LIMIT 8
/// How much the chef gathers before walking it back to the prep table.
#define SP_STOCK_ARMFUL 6
/// How many items the chef keeps piled on the prep table.
#define SP_PANTRY_TARGET 14
/// The chef waits at least this long between food crates.
#define SP_KITCHEN_SUPPLY_INTERVAL (6 MINUTES)

// --- Curiosity: roaming, rummaging and trying doors -------------------------------------------------

/// Item typepaths this particular crew member would pocket if they found one. Rolled at spawn.
#define BB_SP_INTERESTS "sp_interests"
/// A locker, crate or box we are on our way to look inside.
#define BB_SP_RUMMAGE_TARGET "sp_rummage_target"
/// Assoc list of container -> world.time after which it is worth another look.
#define BB_SP_RUMMAGE_IGNORE "sp_rummage_ignore"
/// A door we are about to try, and the assoc list of ones we have already found locked.
#define BB_SP_DOOR_TARGET "sp_door_target"
#define BB_SP_DOOR_IGNORE "sp_door_ignore"
/// Somewhere on the station we have wandered off to.
#define BB_SP_ROAM_TARGET "sp_roam_target"
/// Cooldowns for each. All long: this is idle behaviour, not a job.
#define BB_SP_ROAM_COOLDOWN "sp_roam_cooldown"
#define BB_SP_RUMMAGE_COOLDOWN "sp_rummage_cooldown"
#define BB_SP_DOOR_COOLDOWN "sp_door_cooldown"
/// Cooldown on remarking about any of it out loud.
#define BB_SP_NOSY_SPEAK_COOLDOWN "sp_nosy_speak_cooldown"

/// How far a crew member notices something worth a look.
#define SP_CURIOSITY_RANGE 7
/// How long a searched container, or a door found locked, is left alone.
#define SP_RUMMAGE_IGNORE_TIME (10 MINUTES)
#define SP_DOOR_IGNORE_TIME (15 MINUTES)
/// How many things somebody will pocket out of one container.
#define SP_RUMMAGE_TAKE_LIMIT 2
/// How many interests each character rolls.
#define SP_INTEREST_COUNT 4

// --- Bar ---------------------------------------------------------------------------------------------

/// The /datum/sp_cocktail we are making, and the glass we are making it in.
#define BB_SP_DRINK "sp_drink"
#define BB_SP_GLASS "sp_glass"
/// The dispenser holding the next thing that has to go in the glass.
#define BB_SP_DISPENSER "sp_dispenser"
/// The bar counter finished drinks go out on.
#define BB_SP_BAR_COUNTER "sp_bar_counter"
/// Cooldowns for pouring, serving, and fetching more glassware.
#define BB_SP_POUR_COOLDOWN "sp_pour_cooldown"
#define BB_SP_BAR_SERVE_COOLDOWN "sp_bar_serve_cooldown"
#define BB_SP_GLASSWARE_COOLDOWN "sp_glassware_cooldown"

/// How many drinks may stand on the counter untouched before the bartender stops pouring.
#define SP_BAR_COUNTER_LIMIT 5

/// How often the round prints what the AI crew have actually managed to do.
#define SP_TALLY_INTERVAL (2 MINUTES)

/// How many units each part of a house-menu ratio is worth. A drinking glass holds fifty.
#define SP_DRINK_MEASURE 8
/// How many units of a drink a made-to-order glass aims for.
#define SP_DRINK_SERVING 30
/// How deep the bartender will chase a recipe made of other drinks.
#define SP_DRINK_MAX_DEPTH 3
/// The temperature the bar's taps pour at, which gates the reactions that will fire in the glass.
#define SP_DRINK_POUR_TEMP 274.5
/// A drink somebody has asked for by name, and who asked.
#define BB_SP_DRINK_ORDER "sp_drink_order"
#define BB_SP_ORDER_FOR "sp_order_for"
/// Cooldown on a patron asking for something.
#define BB_SP_ORDER_COOLDOWN_PATRON "sp_order_cooldown_patron"

/// Where in our own department we are heading when we are somewhere else.
#define BB_SP_COMMUTE_TARGET "sp_commute_target"
#define BB_SP_COMMUTE_COOLDOWN "sp_commute_cooldown"
