local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer

-- ===================== CONFIG =====================
local FarmerName = getgenv().FarmerName
local AltNames = getgenv().AltNames

if type(FarmerName) ~= "string" or type(AltNames) ~= "table" then
    warn("[Pryvex] Invalid configuration")
    return
end

local CYCLE = 9.19
local DieDelay = 0.55
local SpawnPosition = Vector3.new(-290, 442, 234)
local RespawnDelay = 1
local ClaimCheckInterval = 0.2
local ClaimText = "CLAIM NEW EMOTE"
local NoRender = true
local FpsCap = 15
local UseTextCheck = true
local BlindInterval = 1

local RequiredCharacter = "Ninja"
local MaxChangeTries = 10

-- ===================== ROLES =====================
local Roles = {
    [FarmerName] = {
        Name = "Farmer",
        Offset = 3.39,
        PressKey = Enum.KeyCode.Three,
        ShowCounter = true,
        RequireCharacter = RequiredCharacter,
    },
}

for _, AltName in ipairs(AltNames) do
    Roles[AltName] = {
        Name = "AltHelper",
        Offset = 0
    }
end

local Config = Roles[Player.Name]

if not Config then
    warn("Player not registered")
    return
end

-- ===================== HELPERS =====================
local function GetHumanoid()
    local Character = Player.Character
    return Character and Character:FindFirstChildOfClass("Humanoid")
end

local function IsAlive()
    local Humanoid = GetHumanoid()
    return Humanoid ~= nil and Humanoid.Health > 0
end

local function ForceDie()
    local Humanoid = GetHumanoid()
    if Humanoid and Humanoid.Health > 0 then
        Humanoid.Health = 0
    end
end

local function PressKey(KeyCode)
    VirtualInputManager:SendKeyEvent(true, KeyCode, false, game)
    VirtualInputManager:SendKeyEvent(false, KeyCode, false, game)
end

local function SetSpawn(Character)
    local Root = Character:WaitForChild("HumanoidRootPart", 10)
    if Root then
        Character:PivotTo(CFrame.new(SpawnPosition))
    end
end

-- ===================== RESPAWN =====================
Player.CharacterAdded:Connect(function(Character)
    task.wait(RespawnDelay)
    SetSpawn(Character)
end)

if Player.Character then
    task.spawn(SetSpawn, Player.Character)
end

-- ===================== CHARACTER CHANGE =====================
local function FireChangeCharacter(Want)
    local args = {
        {
            Goal = "Change Character",
            Character = Want
        }
    }

    local Sent = false

    if getnilinstances then
        for _, v in next, getnilinstances() do
            local Remote

            if v.ClassName == "RemoteEvent" and v.Name == "Communicate" then
                Remote = v
            elseif v:IsA("Model") then
                Remote = v:FindFirstChild("Communicate")
            end

            if Remote and Remote:IsA("RemoteEvent") then
                pcall(Remote.FireServer, Remote, unpack(args))
                Sent = true
            end
        end
    end

    if not Sent then
        local Character = Player.Character
        local Remote = Character and Character:FindFirstChild("Communicate")

        if Remote then
            pcall(Remote.FireServer, Remote, unpack(args))
        end
    end
end

local function EnsureCharacter(Want)
    if not Player.Character then
        Player.CharacterAdded:Wait()
    end

    task.wait(1)

    for Try = 1, MaxChangeTries do
        if Player:GetAttribute("Character") == Want then
            return true
        end

        print(
            "[Character] ตอนนี้เป็น:",
            tostring(Player:GetAttribute("Character")),
            "-> เปลี่ยนเป็น",
            Want,
            "(ครั้งที่",
            Try .. ")"
        )

        FireChangeCharacter(Want)

        local Start = os.clock()

        while os.clock() - Start < 5 do
            if Player:GetAttribute("Character") == Want then
                task.wait(RespawnDelay + 1)
                return true
            end

            task.wait(0.2)
        end
    end

    return false
end

if Config.RequireCharacter then
    if not EnsureCharacter(Config.RequireCharacter) then
        warn("[Character] เปลี่ยนตัวละครไม่สำเร็จ")
        return
    end
end

-- ===================== ANTI AFK =====================
Player.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

task.spawn(function()
    while true do
        task.wait(60)

        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end
end)

-- ===================== NO RENDER =====================
if NoRender then
    pcall(function()
        RunService:Set3dRenderingEnabled(false)
    end)

    if setfpscap then
        pcall(setfpscap, FpsCap)
    end
end

-- ===================== COUNTER UI =====================
local EmoteCount = 0
local CounterLabel

local function UpdateCounter()
    if CounterLabel then
        CounterLabel.Text = "ฟาร์มอีโมทไปแล้ว: " .. EmoteCount .. " อีโมท"
    end
end

if Config.ShowCounter then
    local Gui = Instance.new("ScreenGui")
    Gui.Name = "EmoteCounter"
    Gui.ResetOnSpawn = false
    Gui.IgnoreGuiInset = true
    Gui.DisplayOrder = 999

    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(0, 300, 0, 60)
    Frame.Position = UDim2.new(0.5, -150, 0, 10)
    Frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    Frame.BackgroundTransparency = 0.2
    Frame.BorderSizePixel = 0
    Frame.Parent = Gui

    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 10)

    CounterLabel = Instance.new("TextLabel")
    CounterLabel.Size = UDim2.new(1, 0, 1, 0)
    CounterLabel.BackgroundTransparency = 1
    CounterLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    CounterLabel.Font = Enum.Font.GothamBold
    CounterLabel.TextScaled = true
    CounterLabel.Parent = Frame

    Gui.Parent = (gethui and gethui()) or Player:WaitForChild("PlayerGui")

    UpdateCounter()
end

-- ===================== FARM =====================
local function DoAction()
    if not IsAlive() then
        return
    end

    if Config.PressKey then
        PressKey(Config.PressKey)
        task.wait(DieDelay)
    end

    ForceDie()
end

local function WaitForNextSlot()
    local Now = workspace:GetServerTimeNow()
    local Phase = (Now - Config.Offset) % CYCLE

    task.wait(CYCLE - Phase)
end

-- ===================== AUTO CLAIM =====================
local function GetSpinButton()
    local PlayerGui = Player:FindFirstChild("PlayerGui")
    local Emotes = PlayerGui and PlayerGui:FindFirstChild("Emotes")
    local Image = Emotes and Emotes:FindFirstChild("ImageLabel")

    return Image and Image:FindFirstChild("Spin")
end

local function CanClaim()
    local Button = GetSpinButton()

    if not Button then
        return false
    end

    local ok, text = pcall(function()
        return Button.Text
    end)

    if not ok or type(text) ~= "string" then
        return false
    end

    text = text:upper()

    return string.find(text, ClaimText, 1, true) ~= nil
        and string.find(text, "ROBUX", 1, true) == nil
end

local function FireClaim()
    local Character = Player.Character
    local Remote = Character and Character:FindFirstChild("Communicate")

    if not Remote then
        return false
    end

    return pcall(function()
        Remote:FireServer({
            Goal = "Emote Spin"
        })
    end)
end

-- ===================== MAIN LOOP =====================
task.spawn(function()
    while true do
        WaitForNextSlot()
        DoAction()
    end
end)

-- ===================== CLAIM LOOP =====================
task.spawn(function()
    while true do
        if UseTextCheck then
            if CanClaim() and FireClaim() then
                local Start = os.clock()
                local Claimed = false

                while os.clock() - Start < 3 do
                    task.wait(0.1)

                    if not CanClaim() then
                        Claimed = true
                        break
                    end
                end

                if Claimed then
                    EmoteCount += 1
                    UpdateCounter()
                end

                task.wait(0.5)
            end

            task.wait(ClaimCheckInterval)
        else
            FireClaim()
            task.wait(BlindInterval)
        end
    end
end)
