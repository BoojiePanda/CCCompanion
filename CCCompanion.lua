local ADDON_NAME = ...

local PREFIX = "|cff00ccffCC Companion:|r "
local SCHEMA_VERSION = 3
local activeSpecKey

-- Only these character-wide fields are shared. Unknown/new Class Codex fields
-- are deliberately ignored until their persistence semantics are understood.
local GENERAL_FIELDS = {
    activeTab = true,
    floating = true,
    floatX = true,
    floatY = true,
    minimized = true,
    panelOpen = true,
    floatEscClose = true,
}

local COLLAPSED_FIELDS = {
    stats = true,
    statTargets = true,
    talents = true,
    rotation = true,
    enchants = true,
    gems = true,
}

-- Persisted Class Codex per-spec preferences. In particular, application
-- bookkeeping such as pendingApplyBuildExport/lastAppliedBuild* is excluded.
local PER_SPEC_FIELDS = {
    heroTalent = true,
    statContext = true,
    rotationContext = true,
    trinketContext = true,
    craftingContext = true,
    statPriorityTab = true,
    bisSource = true,
    bisTab = true,
    trinketSource = true,
    trinketHiddenTiers = true,
}

local CONTEXT_FIELDS = {
    contentType = true,
    heroSpec = true,
    source = true,
}

local TALENT_PANE_FIELDS = {
    source = true,
    content = true,
    hero = true,
    difficulty = true,
    buildKey = true,
}

-- Although Class Codex stores its Compendium selector globally, these choices
-- describe the class/spec being viewed and need to follow the logged-in player
-- specialization rather than the most recently used character.
local COMPENDIUM_SPEC_FIELDS = {
    compendiumClass = true,
    compendiumSpec = true,
    compendiumHero = true,
    compendiumSource = true,
    compendiumContent = true,
}

-- This mirrors Class Codex's current spec-index mapping, but the account-wide
-- storage key below uses the numeric specialization ID, not this display slug.
local SPEC_SLUGS = {
    DEATHKNIGHT = { "blood", "frost", "unholy" },
    DEMONHUNTER = { "havoc", "vengeance", "devourer" },
    DRUID = { "balance", "feral", "guardian", "restoration" },
    EVOKER = { "devastation", "preservation", "augmentation" },
    HUNTER = { "beast-mastery", "marksmanship", "survival" },
    MAGE = { "arcane", "fire", "frost" },
    MONK = { "brewmaster", "mistweaver", "windwalker" },
    PALADIN = { "holy", "protection", "retribution" },
    PRIEST = { "discipline", "holy", "shadow" },
    ROGUE = { "assassination", "outlaw", "subtlety" },
    SHAMAN = { "elemental", "enhancement", "restoration" },
    WARLOCK = { "affliction", "demonology", "destruction" },
    WARRIOR = { "arms", "fury", "protection" },
}

local function Print(message)
    print(PREFIX .. message)
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        local keyType = type(key)
        local valueType = type(child)
        if (keyType == "string" or keyType == "number")
            and (valueType == "nil" or valueType == "boolean" or valueType == "number"
                or valueType == "string" or valueType == "table") then
            copy[DeepCopy(key, seen)] = DeepCopy(child, seen)
        end
    end
    return copy
end

local function CopyAllowed(source, allowlist)
    local result = {}
    if type(source) ~= "table" then return result end
    for key in pairs(allowlist) do
        local value = source[key]
        if value ~= nil then result[key] = DeepCopy(value) end
    end
    return result
end

local function MergeAllowed(target, source, allowlist, clearMissing)
    if type(target) ~= "table" or type(source) ~= "table" then return end
    for key in pairs(allowlist) do
        if clearMissing or source[key] ~= nil then target[key] = DeepCopy(source[key]) end
    end
end

local function CurrentSpec()
    if not UnitClass or not GetSpecialization or not GetSpecializationInfo then return nil end
    local _, classToken = UnitClass("player")
    local specIndex = GetSpecialization()
    local slugs = classToken and SPEC_SLUGS[classToken]
    local slug = slugs and specIndex and slugs[specIndex]
    local specID = specIndex and GetSpecializationInfo(specIndex)
    -- During early login GetSpecializationInfo can temporarily return 0. Never
    -- persist that incomplete identity: all unresolved specs of a class would
    -- otherwise collide under CLASS:0.
    if not classToken or not slug or type(specID) ~= "number" or specID <= 0 then return nil end
    return classToken .. ":" .. specID, classToken .. "-" .. slug, specID, classToken, slug
end

local function EnsureDatabase()
    if type(CCCompanionDB) ~= "table" then CCCompanionDB = {} end
    local db = CCCompanionDB
    if type(db.general) ~= "table" then db.general = {} end
    if type(db.specs) ~= "table" then db.specs = {} end
    -- Version 1 could create CLASS:0 entries while specialization APIs were not
    -- ready. They are ambiguous by definition and must never be restored.
    for key in pairs(db.specs) do
        if type(key) == "string" and key:match(":0$") then db.specs[key] = nil end
    end
    db.version = SCHEMA_VERSION
    return db
end

local function Capture()
    if type(ClassCodexCharDB) ~= "table" then return false end
    local db = EnsureDatabase()
    db.general = CopyAllowed(ClassCodexCharDB, GENERAL_FIELDS)
    db.general.collapsed = CopyAllowed(ClassCodexCharDB.collapsed, COLLAPSED_FIELDS)

    local stableKey, legacyKey, specID = CurrentSpec()
    if not stableKey then return true end
    local saved = {}
    local perSpec = type(ClassCodexCharDB.perSpec) == "table" and ClassCodexCharDB.perSpec[legacyKey]
    saved.perSpec = CopyAllowed(perSpec, PER_SPEC_FIELDS)
    saved.perSpec.ctx = CopyAllowed(type(perSpec) == "table" and perSpec.ctx, CONTEXT_FIELDS)

    local paneStates = ClassCodexCharDB.talentPaneState
    saved.talentPaneState = CopyAllowed(type(paneStates) == "table" and paneStates[legacyKey], TALENT_PANE_FIELDS)
    saved.talentPaneOpen = DeepCopy(ClassCodexCharDB.talentPaneOpen)
    saved.talentPaneBuild = DeepCopy(ClassCodexCharDB.talentPaneBuild)

    local source = type(ClassCodexCharDB.uggSource) == "table" and ClassCodexCharDB.uggSource[specID]
    local context = type(ClassCodexCharDB.uggContext) == "table" and ClassCodexCharDB.uggContext[specID]
    local hero = type(ClassCodexCharDB.uggHero) == "table" and ClassCodexCharDB.uggHero[specID]
    if source ~= nil then saved.uggSource = DeepCopy(source) end
    if context ~= nil then saved.uggContext = DeepCopy(context) end
    if hero ~= nil then saved.uggHero = DeepCopy(hero) end
    saved.compendium = CopyAllowed(ClassCodexDB, COMPENDIUM_SPEC_FIELDS)

    db.specs[stableKey] = saved
    db.hasSharedData = true
    db.lastCapture = time and time() or nil
    return true
end

local function Restore()
    if type(ClassCodexCharDB) ~= "table" then return false end
    local db = EnsureDatabase()

    -- Class Codex can retain references to its SavedVariables table. Mutate that
    -- existing table in place; never assign a replacement to ClassCodexCharDB.
    if db.hasSharedData == true then
        MergeAllowed(ClassCodexCharDB, db.general, GENERAL_FIELDS, true)
        if type(ClassCodexCharDB.collapsed) ~= "table" then ClassCodexCharDB.collapsed = {} end
        MergeAllowed(ClassCodexCharDB.collapsed, db.general.collapsed, COLLAPSED_FIELDS, true)
    end

    local stableKey, legacyKey, specID, classToken, specSlug = CurrentSpec()
    local saved = stableKey and db.specs[stableKey]
    if type(saved) ~= "table" then
        -- A new character/spec must not inherit another character's last viewed
        -- class and specialization from Class Codex's account-wide database.
        if type(ClassCodexDB) == "table" and classToken and specSlug then
            ClassCodexDB.compendiumClass = classToken
            ClassCodexDB.compendiumSpec = specSlug
            ClassCodexDB.compendiumHero = nil
            ClassCodexDB.compendiumSource = nil
            ClassCodexDB.compendiumContent = nil
        end
        return true
    end

    if type(ClassCodexDB) == "table" then
        if type(saved.compendium) == "table"
            and saved.compendium.compendiumClass
            and saved.compendium.compendiumSpec then
            MergeAllowed(ClassCodexDB, saved.compendium, COMPENDIUM_SPEC_FIELDS, true)
        elseif classToken and specSlug then
            -- Existing version-1/2 profiles have no Compendium snapshot. Seed
            -- them from the current player instead of the previous character.
            ClassCodexDB.compendiumClass = classToken
            ClassCodexDB.compendiumSpec = specSlug
            ClassCodexDB.compendiumHero = nil
            ClassCodexDB.compendiumSource = nil
            ClassCodexDB.compendiumContent = nil
        end
    end

    if type(ClassCodexCharDB.perSpec) ~= "table" then ClassCodexCharDB.perSpec = {} end
    if type(ClassCodexCharDB.perSpec[legacyKey]) ~= "table" then ClassCodexCharDB.perSpec[legacyKey] = {} end
    local perSpec = ClassCodexCharDB.perSpec[legacyKey]
    MergeAllowed(perSpec, saved.perSpec, PER_SPEC_FIELDS, true)
    if type(perSpec.ctx) ~= "table" then perSpec.ctx = {} end
    MergeAllowed(perSpec.ctx, type(saved.perSpec) == "table" and saved.perSpec.ctx, CONTEXT_FIELDS, true)

    if type(ClassCodexCharDB.talentPaneState) ~= "table" then ClassCodexCharDB.talentPaneState = {} end
    if type(ClassCodexCharDB.talentPaneState[legacyKey]) ~= "table" then
        ClassCodexCharDB.talentPaneState[legacyKey] = {}
    end
    MergeAllowed(ClassCodexCharDB.talentPaneState[legacyKey], saved.talentPaneState, TALENT_PANE_FIELDS, true)
    ClassCodexCharDB.talentPaneOpen = DeepCopy(saved.talentPaneOpen)
    ClassCodexCharDB.talentPaneBuild = DeepCopy(saved.talentPaneBuild)

    for _, field in ipairs({ "uggSource", "uggContext", "uggHero" }) do
        if type(ClassCodexCharDB[field]) ~= "table" then ClassCodexCharDB[field] = {} end
        ClassCodexCharDB[field][specID] = DeepCopy(saved[field])
    end
    return true
end

local function ProtectedCall(label, operation)
    local ok, result = pcall(operation)
    if not ok then
        Print(label .. " failed: " .. tostring(result))
        return false
    end
    return result
end

local function ActivateCurrentSpec(label)
    local stableKey = CurrentSpec()
    if not stableKey then return false end
    if not ProtectedCall(label, Restore) then return false end
    activeSpecKey = stableKey
    return true
end

local function CaptureActiveSpec(label)
    local stableKey = CurrentSpec()
    if not stableKey then return false end
    if stableKey ~= activeSpecKey then return ActivateCurrentSpec("specialization restore") end
    return ProtectedCall(label, Capture)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        EnsureDatabase()
        -- RequiredDeps guarantees Class Codex has initialized its DB. This is the
        -- earliest companion-owned point, after Class Codex's own ADDON_LOADED
        -- handler but before its Compendium is normally opened.
        ActivateCurrentSpec("initial restore")
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(2, function()
                CaptureActiveSpec("background capture")
            end)
        end
    elseif event == "PLAYER_LOGOUT" then
        ProtectedCall("logout capture", Capture)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 and arg1 ~= "player" then return end
        ActivateCurrentSpec("specialization restore")
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        ActivateCurrentSpec("talent-group restore")
    elseif event == "TRAIT_CONFIG_UPDATED" then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() CaptureActiveSpec("talent update capture") end)
        end
    end
end)
