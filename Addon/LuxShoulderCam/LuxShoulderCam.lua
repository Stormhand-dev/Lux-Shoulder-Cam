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
local STEP_HEIGHT = 0.11
local STEP_HORIZ  = 0.11

-- Clamp limits — values beyond these cause visual clipping or glitches
local MIN_HEIGHT = -1.0
local MAX_HEIGHT =  1.0
local MIN_HORIZ  = -2.0
local MAX_HORIZ  =  2.0

-- =============================================================================
-- DLL communication
-- =============================================================================

local function dll_ok()
    return type(LSC) == "function"
end

-- Call the DLL safely. Returns nil on error or if the DLL returned the
-- internal error sentinel (-99999), preventing error codes from being
-- mistaken for valid camera values.
local function dll(cmdCode, arg)
    if not dll_ok() then return nil end
    local ok, result = pcall(LSC, cmdCode, arg)
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFFFF4444[LuxShoulderCam]|r DLL error: " .. tostring(result))
        return nil
    end
    if result == -99999 then return nil end
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
        LSC_Settings.height = result
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

function LSC_RaiseCamera()
    LSC_SetHeight((LSC_Settings.height or 0) + STEP_HEIGHT)
end

function LSC_LowerCamera()
    LSC_SetHeight((LSC_Settings.height or 0) - STEP_HEIGHT)
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
    dll(CMD_RESET)
    LSC_UpdateDisplay()
end

-- =============================================================================
-- Update panel display
-- =============================================================================
function LSC_UpdateDisplay()
    local h = LSC_Settings.height     or 0.0
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