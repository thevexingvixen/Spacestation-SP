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

/// Patient side: the medic looking after us, and the world.time until which we hold still for them.
#define BB_SP_CARER "sp_carer"
#define BB_SP_CARE_UNTIL "sp_care_until"
/// Patient side: cooldown between trips to medbay to have a minor injury looked at.
#define BB_SP_CHECKUP_COOLDOWN "sp_checkup_cooldown"
/// Brute plus burn at which a crew member with nothing better to do goes to have it looked at.
#define SP_CHECKUP_DAMAGE 15
/// How long a patient waits in medbay to be seen before giving up on it.
#define SP_CHECKUP_PATIENCE (2 MINUTES)

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
/// Incident record: what kind of crime it was (SP_CRIME_*), and who did it, when they are a suspect to look for
/// rather than an attacker to stop.
#define SP_INCIDENT_CRIME "crime"
#define SP_INCIDENT_SUSPECT "suspect"

// --- Crime and witnesses (sp_crime.dm) -------------------------------------------------------------
/// How far away a witness can see a crime from.
#define SP_WITNESS_RANGE 7
/// The chance that a crew member who could see a crime actually notices it.
#define SP_WITNESS_NOTICE_CHANCE 70
/// How much a witness thinks less of the culprit.
#define SP_WITNESS_REPUTATION_HIT -3
/// Kinds of crime, for incident records and the tally.
#define SP_CRIME_THEFT "theft"
#define SP_CRIME_VANDALISM "vandalism"
#define SP_CRIME_TRESPASS "trespass"
/// Until when a witness who just called a crime out keeps quiet about the next one.
#define BB_SP_CRIME_CALLOUT_COOLDOWN "sp_crime_callout_cooldown"
#define SP_CRIME_CALLOUT_COOLDOWN (30 SECONDS)
/// Antagonists: the scheme this crew member is working on (/datum/sp_scheme), if any.
#define BB_SP_SCHEME "sp_scheme"
/// The atom the scheme has us heading for: the thing to steal, or the locker it is in.
#define BB_SP_SCHEME_TARGET "sp_scheme_target"
/// Cooldown between scheme steps.
#define BB_SP_SCHEME_COOLDOWN "sp_scheme_cooldown"
/// How long the theft itself takes once we are standing over the thing.
#define SP_THEFT_TIME (3 SECONDS)

// --- Malicious greytide ----------------------------------------------------------------------------
/// Rolled at spawn: only some assistants have a malicious streak. The rest keep it to harmless pranks.
#define BB_SP_TROUBLEMAKER "sp_troublemaker"
/// The chance an assistant is a troublemaker.
#define SP_TROUBLEMAKER_CHANCE 45
/// A prank with a bit of an edge: a broken light tube. Sits in the same menu as the harmless ones.
#define SP_MISCHIEF_VANDALISM "vandalism"

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

/// Botany: a plant another department asked us for, and the area it goes to (medbay asking for aloe).
#define BB_SP_PLANT_REQUEST "sp_plant_request"
#define BB_SP_PLANT_REQUEST_AREA "sp_plant_request_area"
/// Who asked for it, so whatever is delivered can be left for them in particular. The mob itself: the blackboard
/// tracks deletion on its own and treats a weakref as a bug.
#define BB_SP_PLANT_REQUESTER "sp_plant_requester"
/// Set while a load is going to whoever asked rather than the kitchen, so unloading it settles the request wherever it had to be left.
#define BB_SP_REQUEST_DROP "sp_request_drop"
/// The microwave requested produce is being taken to, and the tile to stand on beside it.
#define BB_SP_MICROWAVE "sp_microwave"
#define BB_SP_MICROWAVE_SPOT "sp_microwave_spot"
/// Cooldown between tries at microwaving requested produce, so a broken or unreachable microwave does not hold the delivery up.
#define BB_SP_COOK_COOLDOWN "sp_cook_cooldown"
/// Things somebody left for this crew member in particular: an assoc list of thing -> when to stop looking for it.
#define BB_SP_LEFT_FOR_ME "sp_left_for_me"
/// How long a crew member remembers something was left for them.
#define SP_LEFT_FOR_TIME (20 MINUTES)
/// How long to wait on a microwave before deciding the cook is not going to finish.
#define SP_MICROWAVE_WAIT (30 SECONDS)
/// Until when a patient let go inside medbay may route through its doors on the way back out (sp_see_out()).
#define BB_SP_SHOWN_OUT_UNTIL "sp_shown_out_until"
/// How long that lasts: plenty to walk out of the furthest operating room.
#define SP_SHOWN_OUT_TIME (3 MINUTES)
/// Trays the botanist picked recently, tray -> until when to pass them over, so one they cannot reach does not pin them.
#define BB_SP_TRAY_IGNORE "sp_tray_ignore"
/// Until when a tray job that could not get its tool in hand stays quiet about it.
#define BB_SP_EQUIP_WARNED "sp_equip_warned"

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
/// Who a crate on its way over is for, kept until it is set down so they can be told where it was left.
#define BB_SP_CRATE_FOR "sp_crate_for"
/// How many tiles back from the first door they cannot open a courier looks for somewhere out of the way to leave a delivery.
#define SP_DROP_STEP_BACK 4

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
/// Curiosity: something lying on the floor we fancy, and the ones we have already had our look at.
#define BB_SP_LOOT_TARGET "sp_loot_target"
#define BB_SP_LOOT_IGNORE "sp_loot_ignore"
/// How long we leave a thing on the floor alone once we have decided about it.
#define SP_LOOT_IGNORE_TIME (10 MINUTES)

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

// --- Medbay ----------------------------------------------------------------------------------

/// Medical: what the medic decided after looking the patient over (SP_TRIAGE_*).
#define BB_SP_TREATMENT "sp_treatment"
/// Medical: the cryo tube the current patient is going into.
#define BB_SP_CRYO_CELL "sp_cryo_cell"
/// Medical: assoc list of patient => world.time we last ran a health analyzer over them.
#define BB_SP_SCANNED "sp_scanned"
/// Medical: assoc list of patient => world.time until which we leave them be.
#define BB_SP_PATIENT_IGNORE "sp_patient_ignore"
/// Medical: the patient we have been trying to see to, and since when.
#define BB_SP_PATIENT_ATTEMPT "sp_patient_attempt"
#define BB_SP_PATIENT_ATTEMPT_AT "sp_patient_attempt_at"
/// Medical: the next cryo setup job, and what it is done to.
#define BB_SP_CRYO_TASK "sp_cryo_task"
#define BB_SP_CRYO_TARGET "sp_cryo_target"
/// Medical: the setup target we have been working towards, and since when.
#define BB_SP_CRYO_ATTEMPT "sp_cryo_attempt"
#define BB_SP_CRYO_ATTEMPT_AT "sp_cryo_attempt_at"
/// Medical: world.time before which cryo setup is not looked at again.
#define BB_SP_CRYO_SETUP_RETRY "sp_cryo_setup_retry"

/// What triage decides to do with a patient.
#define SP_TRIAGE_NONE "none"
#define SP_TRIAGE_TREAT "treat"
#define SP_TRIAGE_CRYO "cryo"

/// Cryo setup jobs, in the order they need doing.
#define SP_CRYO_TASK_GET_WRENCH "fetch a wrench"
#define SP_CRYO_TASK_CONNECT_GAS "connect the gas"
#define SP_CRYO_TASK_FREEZER "set the freezer"
#define SP_CRYO_TASK_GET_BEAKER "fetch a cryoxadone beaker"
#define SP_CRYO_TASK_LOAD_BEAKER "load a beaker"

/// Brute or burn a patient needs before a medic bothers with the medkit.
#define SP_TREAT_DAMAGE 10
/// Brute plus burn at which a patient goes in the cryo tube instead.
#define SP_CRYO_DAMAGE 50
/// Toxin plus suffocation damage that sends a patient to cryo: no medkit touches either.
#define SP_CRYO_INTERNAL_DAMAGE 30
/// How far a medic out and about notices somebody hurt.
#define SP_MEDIC_SIGHT 7
/// How long a scan stays current before a player who walks into medbay is looked over again.
#define SP_RESCAN_TIME (10 MINUTES)
/// How long a patient we could not get to, or could not help, is left alone.
#define SP_PATIENT_IGNORE_TIME (3 MINUTES)
/// How long we keep trying to see to one patient before giving up on them.
#define SP_PATIENT_ATTEMPT_TIMEOUT (90 SECONDS)
/// Most rounds of treatment one visit gets: every limb twice over, and some.
#define SP_TREAT_MAX_ROUNDS 14
/// Gas a cryo loop needs before it is worth putting anyone in. The tube itself gives up below 5 mol.
#define SP_CRYO_MIN_MOLES 10
/// Cryoxadone left in a beaker before it counts as spent.
#define SP_CRYO_MIN_REAGENT 5
/// How long cryo setup waits after a job went wrong, or when there was nothing to do.
#define SP_CRYO_SETUP_RETRY_TIME (2 MINUTES)
#define SP_CRYO_SETUP_IDLE_TIME (20 SECONDS)
/// How long we keep working towards one setup job before giving up on it.
#define SP_CRYO_ATTEMPT_TIMEOUT (60 SECONDS)
/// How long an AI patient is asked to stay in the tube. A working tube keeps them regardless.
#define SP_CRYO_STAY (10 MINUTES)

/// Surgery: a surgeon puts the patient on the operating table.
#define SP_TRIAGE_SURGERY "surgery"
/// Medical: the operating table the current patient is going on, and the tray we are fetching tools from.
#define BB_SP_OPTABLE "sp_optable"
#define BB_SP_SURGERY_TRAY "sp_surgery_tray"
/// Medical: the tile to stand on to reach that tray (sp_reach_spot).
#define BB_SP_SURGERY_TRAY_SPOT "sp_surgery_tray_spot"
/// Medical: cooldown between trips to the theatre for surgical tools.
#define BB_SP_SURGICAL_KIT_COOLDOWN "sp_surgical_kit_cooldown"
/// Most operations one visit to the table gets before the surgeon closes up and lets the patient go.
#define SP_SURGERY_MAX_STEPS 12
/// Medical restock: the locker or crate being emptied, the ones already looked in, and the waits between
/// a trip, an ask to cargo and an ask to botany.
#define BB_SP_RESTOCK_TARGET "sp_restock_target"
#define BB_SP_RESTOCK_IGNORE "sp_restock_ignore"
#define BB_SP_RESTOCK_COOLDOWN "sp_restock_cooldown"
#define BB_SP_CARGO_ASK_COOLDOWN "sp_cargo_ask_cooldown"
#define BB_SP_BOTANY_ASK_COOLDOWN "sp_botany_ask_cooldown"
/// Uses of treatment (stack charges plus patches) a medic wants on them before they go looking for more.
#define SP_MEDIC_LOW_SUPPLIES 8
/// How much a medic takes out of one locker.
#define SP_RESTOCK_TAKE_LIMIT 4
/// How long a looked-in locker is left alone, and how long between asking cargo or botany for more.
#define SP_RESTOCK_IGNORE_TIME (5 MINUTES)
#define SP_CARGO_ASK_TIME (10 MINUTES)
#define SP_BOTANY_ASK_TIME (10 MINUTES)

/// How long a surgeon leaves a patient waiting while they go and fetch the tools for the job.
#define SP_FETCH_TOOLS_TIME (45 SECONDS)

// --- Chemistry -------------------------------------------------------------------------------

/// Chemist: what they are making next, and in what form (SP_CHEM_FORM_*).
#define BB_SP_CHEM_PRODUCT "sp_chem_product"
#define BB_SP_CHEM_FORM "sp_chem_form"
/// Chemist: the tile to brew from, and the three machines within reach of it.
#define BB_SP_CHEM_BENCH "sp_chem_bench"
#define BB_SP_CHEM_DISPENSER "sp_chem_dispenser"
#define BB_SP_CHEM_HEATER "sp_chem_heater"
#define BB_SP_CHEM_MASTER "sp_chem_master"
/// Chemist: where finished medicine is going.
#define BB_SP_CHEM_DROP "sp_chem_drop"
/// Chemist: world.time before which the order board is not looked at again.
#define BB_SP_CHEM_IDLE_UNTIL "sp_chem_idle_until"

/// What a chemist order comes out as.
#define SP_CHEM_FORM_PATCH "patch"
#define SP_CHEM_FORM_BEAKER "beaker"
/// Buffer, drawn into the bench's heater for the brews after it.
#define SP_CHEM_FORM_HEATER "heater"

/// How deep the planner follows a recipe made of other recipes.
#define SP_BREW_MAX_DEPTH 4
/// A reaction making less than this, in units a second, at room temperature gets the heater.
#define SP_BREW_SLOW_RATE 2
/// The longest one stage of a brew is waited on.
#define SP_BREW_STAGE_TIMEOUT (60 SECONDS)
/// Patches of each kind kept in the chemistry fridge.
#define SP_CHEM_PATCH_STOCK 4
/// Units of medicine in each printed patch.
#define SP_CHEM_PATCH_UNITS 9
/// Cryoxadone for the tubes, in units, below which the chemist makes more.
#define SP_CRYOXADONE_LOW 40
/// Units of either buffer in the bench's heater below which the chemist brews more before anything else. A
/// batch of libital takes seven, and a brew that runs short of buffer mid-reaction comes out a third pure.
#define SP_CHEM_BUFFER_LOW 12
/// How long the chemist leaves the order board alone when there is nothing to make.
#define SP_CHEM_IDLE_TIME (1 MINUTES)
/// A short wait after a delivery run that did not work out, so an unreachable fridge is not walked at every tick.
#define BB_SP_CHEM_DELIVER_COOLDOWN "sp_chem_deliver_cooldown"

// --- Greytide: assistants and their mischief ---------------------------------------------------

/// Assistant: world.time before which they will not think about another prank.
#define BB_SP_MISCHIEF_NEXT "sp_mischief_next"
/// Assistant: the prank planned (SP_MISCHIEF_*), what it is done to, and the tile to do it from.
#define BB_SP_MISCHIEF "sp_mischief"
#define BB_SP_MISCHIEF_TARGET "sp_mischief_target"
#define BB_SP_MISCHIEF_SPOT "sp_mischief_spot"
/// Assistant: set only while a prank is under way, so a chat does not interrupt it halfway.
#define BB_SP_PRANKING "sp_pranking"
/// Assistant: TRUE once they have their gloves and a tool from tool storage, or have given up on it.
#define BB_SP_GEARED_UP "sp_geared_up"
/// Assistant: the item being fetched from tool storage, the tile to reach it from, and trips made so far.
#define BB_SP_GEAR_TARGET "sp_gear_target"
#define BB_SP_GEAR_SPOT "sp_gear_spot"
#define BB_SP_GEAR_TRIPS "sp_gear_trips"

/// The pranks. The tally counts each one as tide.<name>.
#define SP_MISCHIEF_GRAFFITI "graffiti"
#define SP_MISCHIEF_LIGHTS "lights"
#define SP_MISCHIEF_KNOCK "knock"
#define SP_MISCHIEF_BELL "bell"
#define SP_MISCHIEF_HONK "honk"

/// How long an assistant goes between pranks, and how soon they look again when there was nothing to do.
#define SP_MISCHIEF_INTERVAL_MIN (3 MINUTES)
#define SP_MISCHIEF_INTERVAL_MAX (6 MINUTES)
#define SP_MISCHIEF_RETRY_TIME (1 MINUTES)
/// Chance an assistant who could pull a prank actually bothers, each time one comes round.
#define SP_MISCHIEF_MOOD_CHANCE 60
/// How far an assistant looks for somewhere to pull a prank.
#define SP_MISCHIEF_RANGE 9
/// How long the lights stay off before "just kidding".
#define SP_MISCHIEF_DARK_TIME (6 SECONDS)
/// Things an assistant takes from one locker, which they then leave hanging open.
#define SP_GREYTIDE_TAKE_LIMIT 3
/// Trips to tool storage before an assistant stops bothering: gloves, a tool, and one spare.
#define SP_GEAR_MAX_TRIPS 3
