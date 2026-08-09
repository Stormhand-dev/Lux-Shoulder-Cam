-- =============================================================================
-- LuxShoulderCam.lua
-- Real-time camera height and horizontal offset addon for WoW 3.3.5a (build 12340).
-- Requires LuxShoulderCam.dll injected into WoW.exe (loaded automatically by Lexara).
--
-- Usage:
--   /lsc            open/close the panel
--   /lsc reload     re-apply saved values (useful if the panel shows 0.00 after login)
--   /lsc status     print DLL status to chat
--   /lsc reset      reset camera to default
--
-- LSC() uses numeric command codes — lua_tostring proved unstable in zones
-- with heavy addon activity; lua_tonumber is consistently reliable.
-- =============================================================================

LSC_Settings = nil  -- SavedVariable

-- Command codes — must match enum LSC_Cmd in dllmain.cpp
local CMD_PING         = 1
local CMD_PATCH_STATUS = 2
local CMD_GET_F        = 3
local CMD_GET_FACING   = 4
local CMD_GET_HEIGHT   = 10
local CMD_SET_HEIGHT   = 11
local CMD_GET_HORIZ    = 12
local CMD_SET_HORIZ    = 13
local CMD_RESET        = 14

-- Step size per button click or keybinding press
local STEP_HEIGHT = 0.10
local STEP_HORIZ  = 0.10

-- Clamp limits — values beyond these cause visual clipping or glitches
local MIN_HEIGHT = -1.0
local MAX_HEIGHT =  1.0
local MIN_HORIZ  = -1.0
local MAX_HORIZ  =  1.0

-- =============================================================================
-- DLL communication
-- =============================================================================

local function dll_ok()
    return type(LSC) == "function"
end

-- Call the DLL safely. Returns nil on error, on the internal error sentinel
-- (-99999), or on the first-person lock sentinel (-88888) returned when an
-- offset change is rejected because the camera is at max zoom-in.
local function dll(cmdCode, arg)
    if not dll_ok() then return nil end
    local ok, result = pcall(LSC, cmdCode, arg)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFFFF4444[LuxShoulderCam]|r DLL error: " .. tostring(result))
        return nil
    end
    if result == -99999 then return nil end
    if result == -88888 then return nil end   -- locked (first-person)
    return result
end

local function dll_status_msg()
    if dll_ok() then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[LuxShoulderCam]|r DLL detected. Type |cFFFFFF00/lsc|r to open the panel.")
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFFFFAA00[LuxShoulderCam]|r DLL not detected. Inject |cFFFFFF00LuxShoulderCam.dll|r into WoW.exe.")
    end
end

-- =============================================================================
-- Apply saved settings to the DLL
-- =============================================================================
local function apply_saved()
    if not dll_ok() then return end
    dll(CMD_SET_HEIGHT, LSC_Settings.height)
    dll(CMD_SET_HORIZ,  LSC_Settings.horizontal)
    LSC_UpdateDisplay()
end

-- =============================================================================
-- Adjustment functions (called by buttons and keybindings)
-- =============================================================================

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function LSC_SetHeight(v)
    v = clamp(v, MIN_HEIGHT, MAX_HEIGHT)
    local result = dll(CMD_SET_HEIGHT, v)
    if result then
        -- Save to the current form's slot. Form 0 (humanoid) uses the main
        -- height; shapeshift forms each keep their own calibrated offset.
        local form = 0
        if type(GetShapeshiftForm) == "function" then
            form = GetShapeshiftForm() or 0
        end
        if form == 0 then
            LSC_Settings.height = result
        else
            LSC_Settings.formHeight = LSC_Settings.formHeight or {}
            LSC_Settings.formHeight[form] = result
        end
        LSC_UpdateDisplay()
    end
end

function LSC_SetHorizontal(v)
    v = clamp(v, MIN_HORIZ, MAX_HORIZ)
    local result = dll(CMD_SET_HORIZ, v)
    if result then
        LSC_Settings.horizontal = result
        LSC_UpdateDisplay()
    end
end

-- Returns the currently-active vertical offset for the form the player is in.
function LSC_CurrentFormHeight()
    local form = 0
    if type(GetShapeshiftForm) == "function" then
        form = GetShapeshiftForm() or 0
    end
    if form == 0 then
        return LSC_Settings.height or 0.0
    end
    LSC_Settings.formHeight = LSC_Settings.formHeight or {}
    local h = LSC_Settings.formHeight[form]
    if h == nil then h = LSC_Settings.height or 0.0 end
    return h
end

function LSC_RaiseCamera()
    LSC_SetHeight(LSC_CurrentFormHeight() + STEP_HEIGHT)
end

function LSC_LowerCamera()
    LSC_SetHeight(LSC_CurrentFormHeight() - STEP_HEIGHT)
end

function LSC_MoveRight()
    LSC_SetHorizontal((LSC_Settings.horizontal or 0) + STEP_HORIZ)
end

function LSC_MoveLeft()
    LSC_SetHorizontal((LSC_Settings.horizontal or 0) - STEP_HORIZ)
end

function LSC_ResetCamera()
    LSC_Settings.height     = 0.0
    LSC_Settings.horizontal = 0.0
    LSC_Settings.formHeight = {}
    dll(CMD_RESET)
    LSC_UpdateDisplay()
end

-- =============================================================================
-- Update panel display
-- =============================================================================
function LSC_UpdateDisplay()
    local h = LSC_CurrentFormHeight()
    local x = LSC_Settings.horizontal or 0.0

    if LSC_Val_Height then
        LSC_Val_Height:SetText(string.format("%.2f", h))
    end
    if LSC_Val_Horizontal then
        LSC_Val_Horizontal:SetText(string.format("%.2f", x))
    end
    if LSC_Status then
        if dll_ok() then
            LSC_Status:SetText("|cFF00FF00Active|r")
        else
            LSC_Status:SetText("|cFFFF4444DLL not found|r")
        end
    end
end

-- =============================================================================
-- Panel toggle
-- =============================================================================
function LSC_Toggle()
    if lscFrame:IsShown() then
        lscFrame:Hide()
    else
        LSC_UpdateDisplay()
        lscFrame:Show()
    end
end

-- =============================================================================
-- Frame events
-- =============================================================================
function LSC_OnLoad()
    lscFrame:RegisterEvent("ADDON_LOADED")
    lscFrame:RegisterEvent("PLAYER_LOGIN")
    lscFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Shapeshift compensation via per-frame polling. Events proved unreliable
    -- in WoW 3.3.5 (UPDATE_SHAPESHIFT_FORM and UNIT_AURA do not fire on shift),
    -- and GetShapeshiftForm() reads correctly, so we poll it every frame.
    --
    -- Each form has its own saved vertical offset (LSC_Settings.formHeight[form]).
    -- When the form changes, we apply that form's offset. Form 0 = humanoid
    -- uses the normal LSC_Settings.height. This lets the user calibrate a
    -- different camera height per form (e.g. lower offset in Bear to counter
    -- the model being shorter) with /lsc setform.
    local shiftPoll = CreateFrame("Frame")
    LSC_lastForm    = -1
    LSC_pendingForm = nil   -- form we're waiting to settle before applying
    LSC_settleTime  = 0     -- seconds accumulated since the change was seen

    -- Delay before applying a new form's height. WoW repositions the camera
    -- for a couple of frames right after a shapeshift; applying instantly
    -- lands on a transitional position and then snaps. Waiting a short beat
    -- lets the model settle so the offset applies once, cleanly.
    local SETTLE_DELAY = 0.10   -- seconds (~6 frames at 60fps)

    shiftPoll:SetScript("OnUpdate", function(self, dt)
        if not dll_ok() then return end
        local form = GetShapeshiftForm()

        -- Detect a change and start (or restart) the settle timer.
        if form ~= LSC_lastForm then
            LSC_lastForm    = form
            LSC_pendingForm = form
            LSC_settleTime  = 0
            return
        end

        -- Waiting for the model to settle after a detected change.
        if LSC_pendingForm ~= nil then
            LSC_settleTime = LSC_settleTime + dt
            if LSC_settleTime >= SETTLE_DELAY then
                LSC_ApplyFormHeight(LSC_pendingForm)
                LSC_pendingForm = nil
            end
        end
    end)
end

-- Applies the vertical offset appropriate for the given shapeshift form.
-- Horizontal is unchanged (tracks player rotation regardless of form).
function LSC_ApplyFormHeight(form)
    if not dll_ok() then return end
    local h
    if form == 0 then
        h = LSC_Settings.height or 0.0
    else
        LSC_Settings.formHeight = LSC_Settings.formHeight or {}
        -- Default: same as humanoid height if this form was never calibrated
        h = LSC_Settings.formHeight[form]
        if h == nil then h = LSC_Settings.height or 0.0 end
    end
    dll(CMD_SET_HEIGHT, h)
    LSC_UpdateDisplay()
end

function LSC_OnEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "LuxShoulderCam" then
        if not LSC_Settings then LSC_Settings = {} end
        LSC_Settings.height     = LSC_Settings.height     or 0.0
        LSC_Settings.horizontal = LSC_Settings.horizontal or 0.0
        return
    end

    if event == "PLAYER_LOGIN" then
        SLASH_LSC1 = "/lsc"
        SLASH_LSC2 = "/luxshouldercamp"
        SlashCmdList["LSC"] = function(msg)
            if msg == "reload" then
                if dll_ok() then
                    apply_saved()
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cFF00FF00[LuxShoulderCam]|r Values re-applied.")
                else
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cFFFF4444[LuxShoulderCam]|r DLL not found.")
                end
            elseif msg == "status" then
                dll_status_msg()
            elseif msg == "reset" then
                LSC_ResetCamera()
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cFF00FF00[LuxShoulderCam]|r Camera reset.")
            else
                LSC_Toggle()
            end
        end

        -- Start polling for DLL readiness. PLAYER_LOGIN fires before the DLL
        -- finishes initializing (~3s Sleep + stability frames), so apply_saved()
        -- would silently fail here. We use PLAYER_ENTERING_WORLD as a second
        -- attempt, and also set up a repeating ticker as a fallback.
        LSC_appliedOnLogin = false
        if dll_ok() then
            apply_saved()
            LSC_appliedOnLogin = true
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        -- lscFrame is hidden by default and won't receive OnUpdate events.
        -- Use a separate always-visible frame for the DLL readiness poll.
        local pollFrame = CreateFrame("Frame")
        local elapsed   = 0
        local done      = false

        pollFrame:SetScript("OnUpdate", function(self, dt)
            if done then
                self:SetScript("OnUpdate", nil)
                self:Hide()
                return
            end

            elapsed = elapsed + dt

            if dll_ok() then
                apply_saved()
                done = true
                self:SetScript("OnUpdate", nil)
                self:Hide()
                return
            end

            -- Give up after 30 seconds
            if elapsed >= 30.0 then
                done = true
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end)
        return
    end
end