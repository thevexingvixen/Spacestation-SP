// Spacestation SP — singleplayer fork defines.
// Everything SP-specific lives under code/modules/spacestation_sp/ so it can be rebased onto upstream.

/// Blackboard key: title of the job this AI crew member was spawned as (string).
#define BB_SP_JOB_TITLE "sp_job_title"
/// Blackboard key: the /area this crew member considers "home" (their department).
#define BB_SP_HOME_AREA "sp_home_area"

/// Prefix all SP game-log lines so they are easy to grep in data/logs/*/game.log
#define log_sp(msg) log_game("SP: " + (msg))
