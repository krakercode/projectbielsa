-- Phase 1: full state dump for the currently-selected player/club/staff.
--
-- AUTO-GENERATED from cheat-table/fm.CT via cheat-table/parse_ct.js +
-- cheat-table/generate_dump_lua.js -- do not hand-edit the field tables below;
-- regenerate instead if fm.CT changes.
--
-- IMPORTANT LIMITATION: this only reads the *currently selected* player, club,
-- and staff member -- one record each, exactly what the base FM21-Cheat-Table
-- exposes. It does NOT walk the full squad list, full club list, or
-- competition tables -- that requires finding the squad-array pointer via a
-- live AOB scan in Cheat Engine (see PLAN.md Phase 1 / docs/phase0-feasibility.md),
-- which hasn't been done yet. Once that pointer is found, extend this file
-- with a loop over the array instead of a single dumpRecord() call per type.
--
-- UNTESTED: written without a live Cheat Engine session to verify against.
-- The pointer-chain resolution follows Cheat Engine's standard multi-level
-- offset semantics (dereference at each offset except the last), matching how
-- the base table's own entries resolve -- but this has not actually been run
-- yet. First things to check when testing live: do the "String" fields
-- (player/club names) decode correctly as ASCII/UTF-8, or do they need
-- widechar=true / a different offset (FM may store names as length-prefixed
-- or wide-char strings)? Fix readByType's "String" branch if so.
--
-- Requires the base table's "-----[==Features==]-----" script to be active
-- first (it allocates the pCurrentPlayer/pCurrentClub/pCurrentStaff globals
-- this script reads from).

local FIELDS = {}

FIELDS.CurrentPlayer = {
    { path = {"_", "Dont touch", "pPlayer"}, offsets = {0x0}, vtype = "8 Bytes" },
    { path = {"_", "Dont touch", "vt"}, offsets = {0x270}, vtype = "8 Bytes" },
    { path = {"_", "Dont touch", "Row ID"}, offsets = {0x278}, vtype = "4 Bytes" },
    { path = {"_", "Dont touch", "UID"}, offsets = {0x27C}, vtype = "4 Bytes" },
    { path = {"Player Info", "Name (Read Only)", "First Name"}, offsets = {0x4, 0x0, 0x2C8}, vtype = "String" },
    { path = {"Player Info", "Name (Read Only)", "Last Name"}, offsets = {0x4, 0x0, 0x2D0}, vtype = "String" },
    { path = {"Player Info", "Name (Read Only)", "Full Name"}, offsets = {0x4, 0x2B8}, vtype = "String" },
    { path = {"Player Info", "Nationality (Read Only)", "Full Name"}, offsets = {0x4, 0xB8, 0x2E0}, vtype = "String" },
    { path = {"Player Info", "Nationality (Read Only)", "Shortname"}, offsets = {0x4, 0xC0, 0x2E0}, vtype = "String" },
    { path = {"Player Info", "Nationality (Read Only)", "3 Letter Name"}, offsets = {0x4, 0xD0, 0x2E0}, vtype = "String" },
    { path = {"Player Info", "Team Club (Read Only)", "Name"}, offsets = {0x4, 0xB8, 0x30, 0x88}, vtype = "String" },
    { path = {"Player Info", "Birth Year"}, offsets = {0x2B6}, vtype = "2 Bytes" },
    { path = {"Player Info", "Weight (kg)"}, offsets = {0xA4}, vtype = "2 Bytes" },
    { path = {"Player Info", "Height (cm)"}, offsets = {0xA6}, vtype = "2 Bytes" },
    { path = {"Player Info", "Value (£)"}, offsets = {0x128}, vtype = "4 Bytes" },
    { path = {"Contract", "Wage Per Week (£)"}, offsets = {0x18, 0x338}, vtype = "4 Bytes" },
    { path = {"Contract", "Started Year"}, offsets = {0x3E, 0x338}, vtype = "2 Bytes" },
    { path = {"Contract", "Expires Year"}, offsets = {0x42, 0x338}, vtype = "2 Bytes" },
    { path = {"Contract", "Join Year"}, offsets = {0x46, 0x338}, vtype = "2 Bytes" },
    { path = {"Other", "Fitness"}, offsets = {0x1F0}, vtype = "2 Bytes" },
    { path = {"Other", "Condition"}, offsets = {0x1F4}, vtype = "2 Bytes" },
    { path = {"Other", "Jadedness"}, offsets = {0x1F2}, vtype = "2 Bytes" },
    { path = {"Other", "Home Rep"}, offsets = {0x1F6}, vtype = "2 Bytes" },
    { path = {"Other", "Current Rep"}, offsets = {0x1F8}, vtype = "2 Bytes" },
    { path = {"Other", "World Rep"}, offsets = {0x1FA}, vtype = "2 Bytes" },
    { path = {"Personality", "Adaptability"}, offsets = {0x2E8}, vtype = "Byte" },
    { path = {"Personality", "Ambition"}, offsets = {0x2E9}, vtype = "Byte" },
    { path = {"Personality", "Loyalty"}, offsets = {0x2EA}, vtype = "Byte" },
    { path = {"Personality", "Pressure"}, offsets = {0x2EB}, vtype = "Byte" },
    { path = {"Personality", "Professionalism"}, offsets = {0x2EC}, vtype = "Byte" },
    { path = {"Personality", "Sportsmanship"}, offsets = {0x2ED}, vtype = "Byte" },
    { path = {"Personality", "Temperament"}, offsets = {0x2EE}, vtype = "Byte" },
    { path = {"Personality", "Controversy"}, offsets = {0x2EF}, vtype = "Byte" },
    { path = {"Positions", "GK"}, offsets = {0x204}, vtype = "Byte" },
    { path = {"Positions", "SW"}, offsets = {0x205}, vtype = "Byte" },
    { path = {"Positions", "DL"}, offsets = {0x206}, vtype = "Byte" },
    { path = {"Positions", "DC"}, offsets = {0x207}, vtype = "Byte" },
    { path = {"Positions", "DR"}, offsets = {0x208}, vtype = "Byte" },
    { path = {"Positions", "WBL"}, offsets = {0x211}, vtype = "Byte" },
    { path = {"Positions", "WBR"}, offsets = {0x212}, vtype = "Byte" },
    { path = {"Positions", "DM"}, offsets = {0x209}, vtype = "Byte" },
    { path = {"Positions", "ML"}, offsets = {0x20A}, vtype = "Byte" },
    { path = {"Positions", "MC"}, offsets = {0x20B}, vtype = "Byte" },
    { path = {"Positions", "MR"}, offsets = {0x20C}, vtype = "Byte" },
    { path = {"Positions", "AML"}, offsets = {0x20D}, vtype = "Byte" },
    { path = {"Positions", "AMC"}, offsets = {0x20E}, vtype = "Byte" },
    { path = {"Positions", "AMR"}, offsets = {0x20F}, vtype = "Byte" },
    { path = {"Positions", "ST"}, offsets = {0x210}, vtype = "Byte" },
    { path = {"Attributes", "CA"}, offsets = {0x1FC}, vtype = "2 Bytes" },
    { path = {"Attributes", "PA"}, offsets = {0x1FE}, vtype = "2 Bytes" },
    { path = {"Attributes", "Left Foot"}, offsets = {0x22B}, vtype = "Byte" },
    { path = {"Attributes", "Right Foot"}, offsets = {0x22C}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Aerial Reach"}, offsets = {0x21F}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Command Of Area"}, offsets = {0x220}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Communication"}, offsets = {0x221}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Eccentricity"}, offsets = {0x232}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "First Touch"}, offsets = {0x229}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Handling"}, offsets = {0x21E}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Kicking"}, offsets = {0x222}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "One On Ones"}, offsets = {0x226}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Passing"}, offsets = {0x21A}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Punching"}, offsets = {0x234}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Reflexes"}, offsets = {0x228}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Rushing Out"}, offsets = {0x233}, vtype = "Byte" },
    { path = {"Attributes", "Goalkeeping", "Throwing"}, offsets = {0x223}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Corners"}, offsets = {0x22E}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Crossing"}, offsets = {0x213}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Dribbling"}, offsets = {0x214}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Finishing"}, offsets = {0x215}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "First Touch"}, offsets = {0x229}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Free Kick Taking"}, offsets = {0x236}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Heading"}, offsets = {0x216}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Long Shots"}, offsets = {0x217}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Long Throws"}, offsets = {0x231}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Marking"}, offsets = {0x218}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Passing"}, offsets = {0x21A}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Penalty Taking"}, offsets = {0x21B}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Tackling"}, offsets = {0x21C}, vtype = "Byte" },
    { path = {"Attributes", "Technical", "Technique"}, offsets = {0x22A}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Aggression"}, offsets = {0x240}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Anticipation"}, offsets = {0x224}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Bravery"}, offsets = {0x23E}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Composure"}, offsets = {0x247}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Concentration"}, offsets = {0x248}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Decisions"}, offsets = {0x225}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Determination"}, offsets = {0x246}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Flair"}, offsets = {0x22D}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Leadership"}, offsets = {0x23B}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Off The Ball"}, offsets = {0x219}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Positioning"}, offsets = {0x227}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Teamwork"}, offsets = {0x22F}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Vision"}, offsets = {0x21D}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Work Rate"}, offsets = {0x230}, vtype = "Byte" },
    { path = {"Attributes", "Physical", "Acceleration"}, offsets = {0x235}, vtype = "Byte" },
    { path = {"Attributes", "Physical", "Agility"}, offsets = {0x241}, vtype = "Byte" },
    { path = {"Attributes", "Physical", "Balance"}, offsets = {0x23D}, vtype = "Byte" },
    { path = {"Attributes", "Physical", "Jumping Reach"}, offsets = {0x23A}, vtype = "Byte" },
    { path = {"Attributes", "Physical", "Natural Fitness"}, offsets = {0x245}, vtype = "Byte" },
    { path = {"Attributes", "Physical", "Pace"}, offsets = {0x239}, vtype = "Byte" },
    { path = {"Attributes", "Physical", "Stamina"}, offsets = {0x238}, vtype = "Byte" },
    { path = {"Attributes", "Physical", "Strength"}, offsets = {0x237}, vtype = "Byte" },
    { path = {"Attributes", "Hidden", "Dirtiness"}, offsets = {0x23C}, vtype = "Byte" },
    { path = {"Attributes", "Hidden", "Consistency"}, offsets = {0x23F}, vtype = "Byte" },
    { path = {"Attributes", "Hidden", "Imp. Matches"}, offsets = {0x242}, vtype = "Byte" },
    { path = {"Attributes", "Hidden", "Injury Proneness"}, offsets = {0x243}, vtype = "Byte" },
    { path = {"Attributes", "Hidden", "Versatility"}, offsets = {0x244}, vtype = "Byte" },
}

FIELDS.CurrentClub = {
    { path = {"_", "Dont touch", "pClub"}, offsets = {0x0}, vtype = "8 Bytes" },
    { path = {"_", "Dont touch", "Row ID"}, offsets = {0x8}, vtype = "4 Bytes" },
    { path = {"_", "Dont touch", "UID"}, offsets = {0xC}, vtype = "4 Bytes" },
    { path = {"Club Info", "Full Name"}, offsets = {0x4, 0xB8}, vtype = "String" },
    { path = {"Club Info", "Short Name"}, offsets = {0x4, 0xC0}, vtype = "String" },
    { path = {"Club Info", "Nickname"}, offsets = {0x4, 0x90, 0xB0}, vtype = "String" },
    { path = {"Facilities", "Stadium", "Name"}, offsets = {0x4, 0x40, 0x78, 0x0, 0x18}, vtype = "String" },
    { path = {"Facilities", "Stadium", "Year Built"}, offsets = {0x22, 0x78, 0x0, 0x18}, vtype = "2 Bytes" },
    { path = {"Facilities", "Stadium", "Capacity"}, offsets = {0x6C, 0x78, 0x0, 0x18}, vtype = "4 Bytes" },
    { path = {"Facilities", "Stadium", "Capacity (seated)"}, offsets = {0x70, 0x78, 0x0, 0x18}, vtype = "4 Bytes" },
    { path = {"Facilities", "Stadium", "Avg. Attendance"}, offsets = {0x68, 0xB0}, vtype = "4 Bytes" },
    { path = {"Facilities", "Stadium", "Min. Attendance"}, offsets = {0x6C, 0xB0}, vtype = "4 Bytes" },
    { path = {"Facilities", "Stadium", "Max. Attendance"}, offsets = {0x70, 0xB0}, vtype = "4 Bytes" },
    { path = {"Facilities", "Corporate Facilities"}, offsets = {0x88D, 0x148}, vtype = "Byte" },
    { path = {"Facilities", "Training Facilities"}, offsets = {0xE8, 0xF8}, vtype = "Byte" },
    { path = {"Facilities", "Youth Facilities"}, offsets = {0xF3, 0xF8}, vtype = "Byte" },
    { path = {"Facilities", "Youth Importance"}, offsets = {0xE1, 0xF8}, vtype = "Byte" },
    { path = {"Facilities", "Junior Coaching"}, offsets = {0xF4, 0xF8}, vtype = "Byte" },
    { path = {"Facilities", "Youth Recruitment"}, offsets = {0xF5, 0xF8}, vtype = "Byte" },
    { path = {"Finances", "Balance (£)"}, offsets = {0x14, 0x148}, vtype = "4 Bytes" },
    { path = {"Finances", "Transfer Budget (£)"}, offsets = {0x7A4, 0x148}, vtype = "4 Bytes" },
    { path = {"Finances", "Income % Available"}, offsets = {0x7B0, 0x148}, vtype = "4 Bytes" },
    { path = {"Finances", "Weekly Wage Budget (£)"}, offsets = {0x7E8, 0x148}, vtype = "4 Bytes" },
    { path = {"Finances", "Wage Budget Used (£)"}, offsets = {0x7F4, 0x148}, vtype = "4 Bytes" },
    { path = {"Finances", "Avg. Match Ticker Price (£)"}, offsets = {0x18, 0x148}, vtype = "Float" },
    { path = {"Finances", "Avg. Season Ticker Price (£)"}, offsets = {0x1C, 0x148}, vtype = "Float" },
    { path = {"Finances", "Match Ticket Price Ratio (£)"}, offsets = {0x20, 0x148}, vtype = "Float" },
    { path = {"Finances", "Season Ticket Price Ratio (£)"}, offsets = {0x24, 0x148}, vtype = "Float" },
    { path = {"Finances", "Season Ticket Change Ratio (£)"}, offsets = {0x28, 0x148}, vtype = "Float" },
    { path = {"Finances", "Sugar Daddy"}, offsets = {0x3C, 0x148}, vtype = "Byte" },
}

FIELDS.CurrentStaff = {
    { path = {"_", "Dont touch", "pStaff"}, offsets = {0x0}, vtype = "8 Bytes" },
    { path = {"_", "Dont touch", "Row ID"}, offsets = {0xF0}, vtype = "4 Bytes" },
    { path = {"_", "Dont touch", "UID"}, offsets = {0xF4}, vtype = "4 Bytes" },
    { path = {"Info", "First Name"}, offsets = {0x4, 0x0, 0x140}, vtype = "String" },
    { path = {"Info", "Last Name"}, offsets = {0x4, 0x0, 0x148}, vtype = "String" },
    { path = {"Info", "Nationality"}, offsets = {0x4, 0xB8, 0x158}, vtype = "String" },
    { path = {"Info", "Place Of Birth"}, offsets = {0x4, 0x18, 0x170}, vtype = "String" },
    { path = {"Personality", "Adaptability"}, offsets = {0x160}, vtype = "Byte" },
    { path = {"Personality", "Ambition"}, offsets = {0x161}, vtype = "Byte" },
    { path = {"Personality", "Loyalty"}, offsets = {0x162}, vtype = "Byte" },
    { path = {"Personality", "Pressure"}, offsets = {0x163}, vtype = "Byte" },
    { path = {"Personality", "Professionalism"}, offsets = {0x164}, vtype = "Byte" },
    { path = {"Personality", "Sportsmanship"}, offsets = {0x165}, vtype = "Byte" },
    { path = {"Personality", "Temperament"}, offsets = {0x166}, vtype = "Byte" },
    { path = {"Personality", "Controversy"}, offsets = {0x167}, vtype = "Byte" },
    { path = {"Job Attributes", "Director Of Football"}, offsets = {0x8, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Technical Director"}, offsets = {0xD, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Manager"}, offsets = {0x0, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Assistant Manager"}, offsets = {0x1, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Coach"}, offsets = {0x2, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Fitness Coach"}, offsets = {0x6, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "GK Coach"}, offsets = {0x5, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Head of Youth Development"}, offsets = {0x9, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Scout"}, offsets = {0x4, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Analyst"}, offsets = {0xB, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Loan Manager"}, offsets = {0xA, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Physio"}, offsets = {0x3, 0x1E8}, vtype = "Byte" },
    { path = {"Job Attributes", "Sports Scientist"}, offsets = {0xC, 0x1E8}, vtype = "Byte" },
    { path = {"Attributes", "CA"}, offsets = {0xD2}, vtype = "2 Bytes" },
    { path = {"Attributes", "PA"}, offsets = {0xD4}, vtype = "2 Bytes" },
    { path = {"Attributes", "Analysis", "Analysing Data"}, offsets = {0x44}, vtype = "Byte" },
    { path = {"Attributes", "Analysis", "Judging Team Data (?)"}, offsets = {0x45}, vtype = "Byte" },
    { path = {"Attributes", "Analysis", "Presenting Data (?)"}, offsets = {0x46}, vtype = "Byte" },
    { path = {"Attributes", "Chairman", "Business"}, offsets = {0x19}, vtype = "Byte" },
    { path = {"Attributes", "Chairman", "Interference"}, offsets = {0x1E}, vtype = "Byte" },
    { path = {"Attributes", "Chairman", "Patience"}, offsets = {0x21}, vtype = "Byte" },
    { path = {"Attributes", "Chairman", "Resources"}, offsets = {0x23}, vtype = "Byte" },
    { path = {"Attributes", "NonTactical", "Buying Players"}, offsets = {0x26}, vtype = "Byte" },
    { path = {"Attributes", "NonTactical", "Mind Games"}, offsets = {0x27}, vtype = "Byte" },
    { path = {"Attributes", "NonTactical", "Hardness of training"}, offsets = {0x2E}, vtype = "Byte" },
    { path = {"Attributes", "NonTactical", "Squad Rotation"}, offsets = {0x2F}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Attacking"}, offsets = {0x18}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Directness"}, offsets = {0x1B}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Free Roles"}, offsets = {0x1D}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Marking"}, offsets = {0x1F}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Offside"}, offsets = {0x20}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Pressing"}, offsets = {0x22}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Sitting Back"}, offsets = {0x28}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Use Of Playmaker"}, offsets = {0x29}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Use Of Subs"}, offsets = {0x2A}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Depth"}, offsets = {0x2B}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Flamboyancy"}, offsets = {0x2C}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Flexibility"}, offsets = {0x2D}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Tempo"}, offsets = {0x30}, vtype = "Byte" },
    { path = {"Attributes", "Tactical", "Width"}, offsets = {0x31}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Attacking"}, offsets = {0x3A}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Defending"}, offsets = {0x3B}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Fitness"}, offsets = {0x3C}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Mental"}, offsets = {0x3D}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Technical"}, offsets = {0x3E}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Tactical"}, offsets = {0x3F}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Dirtiness Allowance"}, offsets = {0x40}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Versatility"}, offsets = {0x43}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Working with Youngsters"}, offsets = {0x24}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "GK Shot Stopping"}, offsets = {0x33}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "GK Handling"}, offsets = {0x41}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "GK Distribution"}, offsets = {0x42}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Players"}, offsets = {0x32}, vtype = "Byte" },
    { path = {"Attributes", "Coaching", "Man Management"}, offsets = {0x36}, vtype = "Byte" },
    { path = {"Attributes", "Medical", "Physiotherapy"}, offsets = {0x38}, vtype = "Byte" },
    { path = {"Attributes", "Medical", "Sport Science"}, offsets = {0x47}, vtype = "Byte" },
    { path = {"Attributes", "Knowledge", "Judging Player Ability"}, offsets = {0x34}, vtype = "Byte" },
    { path = {"Attributes", "Knowledge", "Judging Player Potential"}, offsets = {0x35}, vtype = "Byte" },
    { path = {"Attributes", "Knowledge", "Judging Staff Ability"}, offsets = {0x4A}, vtype = "Byte" },
    { path = {"Attributes", "Knowledge", "Tactical Knowledge"}, offsets = {0x39}, vtype = "Byte" },
    { path = {"Attributes", "Knowledge", "Negotiating"}, offsets = {0x49}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Level of Discipline"}, offsets = {0x1C}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Determination"}, offsets = {0x25}, vtype = "Byte" },
    { path = {"Attributes", "Mental", "Motivating"}, offsets = {0x37}, vtype = "Byte" },
    { path = {"Contract", "Wage Per Week (£)"}, offsets = {0x18, 0x1B0}, vtype = "4 Bytes" },
    { path = {"Contract", "Started Year"}, offsets = {0x3E, 0x1B0}, vtype = "2 Bytes" },
    { path = {"Contract", "Expires Year"}, offsets = {0x42, 0x1B0}, vtype = "2 Bytes" },
    { path = {"Contract", "Join Year"}, offsets = {0x46, 0x1B0}, vtype = "2 Bytes" },
}

local function resolvePointerChain(symbolName, offsets)
  local ok, sym = pcall(getAddress, symbolName)
  if not ok or sym == nil or sym == 0 then return nil end
  local ok2, addr = pcall(readQword, sym)
  if not ok2 or addr == nil or addr == 0 then return nil end
  for i, off in ipairs(offsets) do
    if i == 1 then
      addr = addr + off
    else
      local okp, ptr = pcall(readQword, addr)
      if not okp or ptr == nil or ptr == 0 then return nil end
      addr = ptr + off
    end
  end
  return addr
end

local function readByType(address, vtype)
  if address == nil then return nil end
  local ok, value = pcall(function()
    if vtype == "Byte" then
      local b = readBytes(address, 1, true)
      return b and b[1] or nil
    elseif vtype == "2 Bytes" then
      return readSmallInteger(address)
    elseif vtype == "4 Bytes" then
      return readInteger(address)
    elseif vtype == "8 Bytes" then
      return readQword(address)
    elseif vtype == "Float" then
      return readFloat(address)
    elseif vtype == "String" then
      return readString(address, 128, false)
    end
    return nil
  end)
  if ok then return value end
  return nil
end

local function setPath(tbl, fieldPath, value)
  local node = tbl
  for i = 1, #fieldPath - 1 do
    local key = fieldPath[i]
    node[key] = node[key] or {}
    node = node[key]
  end
  node[fieldPath[#fieldPath]] = value
end

local function dumpRecord(symbolName, fieldList)
  local ok, sym = pcall(getAddress, symbolName)
  if not ok or sym == nil or sym == 0 then return nil end
  local ok2, base = pcall(readQword, sym)
  if not ok2 or base == nil or base == 0 then return nil end -- nothing currently selected

  local out = {}
  for _, f in ipairs(fieldList) do
    local addr = resolvePointerChain(symbolName, f.offsets)
    local value = readByType(addr, f.vtype)
    setPath(out, f.path, value)
  end
  return out
end

function dump_current_player()
  return dumpRecord("pCurrentPlayer", FIELDS.CurrentPlayer)
end

function dump_current_club()
  return dumpRecord("pCurrentClub", FIELDS.CurrentClub)
end

function dump_current_staff()
  return dumpRecord("pCurrentStaff", FIELDS.CurrentStaff)
end

-- Minimal JSON encoder (Cheat Engine's Lua has no guaranteed JSON library).
local function jsonEscape(s)
  s = tostring(s)
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  s = s:gsub('\t', '\\t')
  return s
end

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return false, 0 end
  for i = 1, n do
    if t[i] == nil then return false, n end
  end
  return true, n
end

function jsonEncode(v)
  local t = type(v)
  if v == nil then
    return "null"
  elseif t == "boolean" then
    return v and "true" or "false"
  elseif t == "number" then
    return tostring(v)
  elseif t == "string" then
    return '"' .. jsonEscape(v) .. '"'
  elseif t == "table" then
    local arr, n = isArray(v)
    local parts = {}
    if arr then
      for i = 1, n do parts[#parts + 1] = jsonEncode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for k, val in pairs(v) do
        parts[#parts + 1] = '"' .. jsonEscape(k) .. '":' .. jsonEncode(val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

-- mode: "full" (implemented) or "restricted" (Phase 5 human-mode masking --
-- not implemented yet; currently falls back to full data with a warning).
function dump_state(mode)
  mode = mode or "full"
  if mode == "restricted" then
    print("[dump_state] WARNING: 'restricted' (human) mode masking not implemented yet (Phase 5) -- returning full data")
  end
  return {
    mode = mode,
    current_player = dump_current_player(),
    current_club = dump_current_club(),
    current_staff = dump_current_staff(),
  }
end

function dump_state_json(mode)
  return jsonEncode(dump_state(mode))
end

-- Writes the JSON snapshot to disk, e.g. dump_state_to_file([[C:\\...\\data\\snapshots\\snap1.json]])
function dump_state_to_file(filepath, mode)
  local json = dump_state_json(mode)
  local f = io.open(filepath, "w")
  if not f then
    print("[dump_state_to_file] ERROR: could not open " .. filepath .. " for writing")
    return false
  end
  f:write(json)
  f:close()
  return true
end
