local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer

-- ===================== CONFIG =====================
local FarmerName = getgenv().FarmerName
local AltNames = getgenv().AltNames

if type(FarmerName) ~= "string" or type(AltNames) ~= "table" then
    warn("[Pryvex] Invalid configuration")
    return
end

local CYCLE = 9.19
local DieDelay = 2.32 -- รอหลังกด 3 ก่อนบังคับตาย
local SpawnPosition = Vector3.new(-290, 442, 234)
local RespawnDelay = 1
local ClaimCheckInterval = 0.2
local ClaimText = "CLAIM NEW EMOTE"
local NoRender = true
local FpsCap = 15
local UseTextCheck = true
local BlindInterval = 1

local RequiredCharacter = "Batter"
local MaxChangeTries = 10

local PRYVEX_ICON = "rbxassetid://127972121421541"
local EMOTE_ICON = "rbxassetid://74563956423630"

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
local UseRemoteFallback = true -- ถ้ากดผ่าน GUI ไม่สำเร็จ ให้ลองยิง Remote แทน
local GuiWaitTimeout = 3       -- รอหา GUI สูงสุดกี่วินาที

-- รอจนเจอ path (ตารางชื่อ) ภายใต้ Root
local function WaitPath(Root, Path, Timeout)
    local Deadline = os.clock() + Timeout
    repeat
        local Obj = Root
        for _, Name in ipairs(Path) do
            Obj = Obj and Obj:FindFirstChild(Name)
        end
        if Obj then
            return Obj
        end
        task.wait(0.1)
    until os.clock() >= Deadline
    return nil
end

-- กด GUI: UseMouse = false -> เรียก connection ก่อน, ถ้าไม่มีค่อยจำลองเมาส์
--                 UseMouse = true  -> จำลองเมาส์เลย
local function ClickGui(Obj, UseMouse)
    local Target = Obj
    if not Obj:IsA("GuiButton") then
        Target = Obj:FindFirstChildWhichIsA("GuiButton", true) or Obj
    end

    if not UseMouse and getconnections and Target:IsA("GuiButton") then
        -- ยิงแค่สัญญาณเดียว กันกดซ้ำจนเมนูเปิดแล้วปิด
        for _, SignalName in ipairs({ "Activated", "MouseButton1Click" }) do
            local Fired = 0
            pcall(function()
                for _, Conn in ipairs(getconnections(Target[SignalName])) do
                    Conn:Fire()
                    Fired += 1
                end
            end)
            if Fired > 0 then
                return true
            end
        end
    end

    -- จำลองเมาส์
    local Pos = Obj.AbsolutePosition
    local Size = Obj.AbsoluteSize
    local X = Pos.X + Size.X / 2
    local Y = Pos.Y + Size.Y / 2

    local Gui = Obj:FindFirstAncestorOfClass("ScreenGui")
    if Gui and not Gui.IgnoreGuiInset then
        Y += GuiService:GetGuiInset().Y
    end

    VirtualInputManager:SendMouseMoveEvent(X, Y, game)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(X, Y, 0, true, game, 0)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(X, Y, 0, false, game, 0)
    return true
end

-- เปลี่ยนตัวละครผ่านเมนูด้านบน: Characters -> Batter
local function ChangeViaGui(Want, PreferMouse)
    local PlayerGui = Player:WaitForChild("PlayerGui")

    local CharactersBtn = WaitPath(
        PlayerGui,
        { "TopbarStandard", "Holders", "Left", "Characters" },
        GuiWaitTimeout
    )
    if not CharactersBtn then
        warn("[Character] ไม่เจอปุ่ม Characters")
        return false
    end

    local WantBtn
    local Modes = PreferMouse and { true, false } or { false, true }

    for _, UseMouse in ipairs(Modes) do
        ClickGui(CharactersBtn, UseMouse)
        WantBtn = WaitPath(
            PlayerGui,
            { "TopbarStandardClipped", "ClippedContainer", "Dropdown", "DropdownScroller", Want, "IconButton" },
            2
        )
        if WantBtn then
            break
        end
    end

    if not WantBtn then
        warn("[Character] ไม่เจอปุ่ม " .. Want .. " ในเมนู")
        return false
    end

    task.wait(0.2)
    ClickGui(WantBtn, PreferMouse)
    return true
end

-- ยิง Remote (ตัวสำรอง)
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

-- บังคับตายแล้วรอตัวละครใหม่เกิด
local function KillAndWaitRespawn(Timeout)
    local Old = Player.Character
    ForceDie()

    local Start = os.clock()
    while os.clock() - Start < Timeout do
        local Char = Player.Character
        if Char and Char ~= Old and Char:FindFirstChildOfClass("Humanoid") then
            task.wait(RespawnDelay + 1)
            return true
        end
        task.wait(0.2)
    end
    return false
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

        -- 1) บังคับตาย
        KillAndWaitRespawn(10)

        -- 2) กดเมนู Characters -> Want (สลับใช้เมาส์ทุกครั้งที่เป็นเลขคู่)
        local Ok = ChangeViaGui(Want, Try % 2 == 0)

        -- 3) กดไม่สำเร็จ ลองยิง Remote แทน
        if not Ok and UseRemoteFallback then
            FireChangeCharacter(Want)
        end

        -- 4) รอให้ Attribute เปลี่ยน
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

-- ไม่เปลี่ยนตัวละครให้อัตโนมัติ: รอให้ผู้เล่นเปลี่ยนเอง (ดู WaitUntilReady ด้านล่าง)
local function IsCharacterReady()
    if not Config.RequireCharacter then
        return true
    end
    return Player:GetAttribute("Character") == Config.RequireCharacter
end

local function WaitUntilReady()
    while not IsCharacterReady() do
        task.wait(0.5)
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

-- ===================== STATUS UI (Farmer only) =====================
local EmoteCount = 0
local CountLabel
local TimeLabel
local StartTime = os.clock()

local Purple = Color3.fromRGB(150, 80, 255)

local function FormatNumber(n)
    local s = tostring(math.floor(n))
    local k
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end

local function UpdateCounter()
    if CountLabel then
        CountLabel.Text = FormatNumber(EmoteCount)
    end
end

local function New(Class, Props, Parent)
    local Obj = Instance.new(Class)
    for k, v in pairs(Props) do
        Obj[k] = v
    end
    Obj.Parent = Parent
    return Obj
end

local function Round(Obj, Radius)
    New("UICorner", { CornerRadius = Radius }, Obj)
end

local function Stroke(Obj, Color, Thickness)
    New("UIStroke", { Color = Color, Thickness = Thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, Obj)
end

local function Text(Parent, Props)
    local Base = {
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextWrapped = false,
    }
    for k, v in pairs(Props) do
        Base[k] = v
    end
    return New("TextLabel", Base, Parent)
end

if Config.ShowCounter then
    local Gui = New("ScreenGui", {
        Name = "PryvexStatus",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999,
    })

    local Card = New("Frame", {
        Size = UDim2.new(0, 440, 0, 290),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        BackgroundColor3 = Color3.fromRGB(8, 8, 10),
        BorderSizePixel = 0,
        Active = true,
    }, Gui)
    Round(Card, UDim.new(0, 16))
    Stroke(Card, Color3.fromRGB(55, 55, 60), 1.5)

    -- Header: logo + title
    New("ImageLabel", {
        Size = UDim2.new(0, 44, 0, 44),
        Position = UDim2.new(0, 20, 0, 14),
        BackgroundTransparency = 1,
        Image = PRYVEX_ICON,
        ScaleType = Enum.ScaleType.Fit,
    }, Card)

    Text(Card, {
        Size = UDim2.new(0, 220, 0, 44),
        Position = UDim2.new(0, 72, 0, 14),
        Text = "Pryvex Hub",
        TextSize = 28,
    })

    -- Session time (top right)
    TimeLabel = Text(Card, {
        Size = UDim2.new(0, 110, 0, 24),
        Position = UDim2.new(1, -130, 0, 14),
        Text = "00:00:00",
        TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Right,
    })

    Text(Card, {
        Size = UDim2.new(0, 110, 0, 16),
        Position = UDim2.new(1, -130, 0, 38),
        Text = "SESSION TIME",
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        TextColor3 = Color3.fromRGB(150, 150, 155),
        TextXAlignment = Enum.TextXAlignment.Right,
    })

    -- clock icon (drawn)
    local Clock = New("Frame", {
        Size = UDim2.new(0, 24, 0, 24),
        Position = UDim2.new(1, -162, 0, 17),
        BackgroundTransparency = 1,
    }, Card)
    Round(Clock, UDim.new(1, 0))
    Stroke(Clock, Purple, 2)
    New("Frame", { -- minute hand
        Size = UDim2.new(0, 2, 0, 8),
        Position = UDim2.new(0.5, -1, 0.5, -8),
        BackgroundColor3 = Purple,
        BorderSizePixel = 0,
    }, Clock)
    New("Frame", { -- hour hand
        Size = UDim2.new(0, 6, 0, 2),
        Position = UDim2.new(0.5, -1, 0.5, -1),
        BackgroundColor3 = Purple,
        BorderSizePixel = 0,
    }, Clock)

    -- Divider
    New("Frame", {
        Size = UDim2.new(1, -32, 0, 1),
        Position = UDim2.new(0, 16, 0, 68),
        BackgroundColor3 = Color3.fromRGB(45, 45, 50),
        BorderSizePixel = 0,
    }, Card)

    -- Main panel
    local Panel = New("Frame", {
        Size = UDim2.new(1, -40, 0, 140),
        Position = UDim2.new(0, 20, 0, 84),
        BackgroundColor3 = Color3.fromRGB(14, 14, 16),
        BorderSizePixel = 0,
    }, Card)
    Round(Panel, UDim.new(0, 14))
    Stroke(Panel, Color3.fromRGB(50, 50, 55), 1.5)

    New("ImageLabel", { -- masks icon
        Size = UDim2.new(0, 116, 0, 116),
        Position = UDim2.new(0, 8, 0, 12),
        BackgroundTransparency = 1,
        Image = EMOTE_ICON,
        ScaleType = Enum.ScaleType.Fit,
    }, Panel)

    CountLabel = Text(Panel, {
        Size = UDim2.new(1, -136, 0, 76),
        Position = UDim2.new(0, 128, 0, 10),
        Text = "0",
        TextSize = 56,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    Text(Panel, {
        Size = UDim2.new(1, -136, 0, 24),
        Position = UDim2.new(0, 128, 0, 90),
        Text = "EMOTES",
        TextSize = 20,
        TextColor3 = Purple,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local Line = New("Frame", {
        Size = UDim2.new(0, 190, 0, 2),
        Position = UDim2.new(0, 166, 0, 118),
        BackgroundColor3 = Purple,
        BorderSizePixel = 0,
    }, Panel)
    New("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, Line)

    -- Footer: user (bottom right)
    local User = New("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -20, 0, 242),
        Size = UDim2.new(0, 0, 0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
    }, Card)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, User)

    local Avatar = New("Frame", {
        Size = UDim2.new(0, 26, 0, 26),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
    }, User)
    Round(Avatar, UDim.new(1, 0))
    Stroke(Avatar, Purple, 2)
    local Head = New("Frame", {
        Size = UDim2.new(0, 8, 0, 8),
        Position = UDim2.new(0.5, -4, 0, 5),
        BackgroundTransparency = 1,
    }, Avatar)
    Round(Head, UDim.new(1, 0))
    Stroke(Head, Purple, 1.5)
    local Body = New("Frame", {
        Size = UDim2.new(0, 12, 0, 5),
        Position = UDim2.new(0.5, -6, 0, 15),
        BackgroundTransparency = 1,
    }, Avatar)
    Round(Body, UDim.new(0.5, 0))
    Stroke(Body, Purple, 1.5)

    Text(User, {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "@" .. Player.Name,
        TextSize = 16,
        Font = Enum.Font.GothamMedium,
        LayoutOrder = 2,
    })

    -- Alt status (footer left)
    local AltBox = New("Frame", {
        Position = UDim2.new(0, 20, 0, 242),
        Size = UDim2.new(0, 0, 0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
    }, Card)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, AltBox)

    local AltDot = New("Frame", {
        Size = UDim2.new(0, 10, 0, 10),
        BorderSizePixel = 0,
        LayoutOrder = 1,
    }, AltBox)
    Round(AltDot, UDim.new(1, 0))

    local AltText = Text(AltBox, {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 15,
        Font = Enum.Font.GothamMedium,
        LayoutOrder = 2,
    })

    local Green = Color3.fromRGB(80, 220, 120)
    local Red = Color3.fromRGB(230, 80, 80)

    local function RefreshAlts()
        local Online = 0
        for _, Name in ipairs(AltNames) do
            if Players:FindFirstChild(Name) then
                Online += 1
            end
        end

        if Online > 0 then
            AltDot.BackgroundColor3 = Green
            AltText.TextColor3 = Green
            AltText.Text = string.format("Alt online : %d/%d", Online, #AltNames)
        else
            AltDot.BackgroundColor3 = Red
            AltText.TextColor3 = Red
            AltText.Text = "Alert : No alt is online"
        end
    end

    RefreshAlts()
    Players.PlayerAdded:Connect(RefreshAlts)
    Players.PlayerRemoving:Connect(function()
        task.defer(RefreshAlts)
    end)
    task.spawn(function()
        while true do
            task.wait(2)
            RefreshAlts()
        end
    end)

    -- Warning banner: แสดงเมื่อยังไม่ได้ใช้ตัวละครที่กำหนด
    local Warn = New("Frame", {
        Size = UDim2.new(1, -40, 0, 140),
        Position = UDim2.new(0, 20, 0, 84),
        BackgroundColor3 = Color3.fromRGB(40, 12, 12),
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 10,
    }, Card)
    Round(Warn, UDim.new(0, 14))
    Stroke(Warn, Color3.fromRGB(230, 80, 80), 1.5)

    Text(Warn, {
        Size = UDim2.new(1, -24, 0, 60),
        Position = UDim2.new(0, 12, 0, 22),
        Text = "กรุณาเปลี่ยนเป็นตัวละคร Brutal Demon",
        TextSize = 22,
        TextColor3 = Color3.fromRGB(255, 120, 120),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextWrapped = true,
        ZIndex = 11,
    })

    Text(Warn, {
        Size = UDim2.new(1, -24, 0, 50),
        Position = UDim2.new(0, 12, 0, 82),
        Text = "Please switch to Brutal Demon.\nThe script will start once you switch.",
        TextSize = 14,
        Font = Enum.Font.GothamMedium,
        TextColor3 = Color3.fromRGB(200, 200, 205),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextWrapped = true,
        ZIndex = 11,
    })

    local function RefreshWarning()
        Warn.Visible = not IsCharacterReady()
    end

    RefreshWarning()
    Player:GetAttributeChangedSignal("Character"):Connect(RefreshWarning)
    task.spawn(function()
        while true do
            task.wait(0.5)
            RefreshWarning()
        end
    end)

    -- free drag (เมาส์ + ทัช)
    do
        local Dragging, DragStart, StartPos, DragInput

        Card.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1
                or Input.UserInputType == Enum.UserInputType.Touch then
                Dragging = true
                DragStart = Input.Position
                StartPos = Card.Position

                Input.Changed:Connect(function()
                    if Input.UserInputState == Enum.UserInputState.End then
                        Dragging = false
                    end
                end)
            end
        end)

        Card.InputChanged:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseMovement
                or Input.UserInputType == Enum.UserInputType.Touch then
                DragInput = Input
            end
        end)

        UserInputService.InputChanged:Connect(function(Input)
            if Dragging and Input == DragInput then
                local Delta = Input.Position - DragStart
                Card.Position = UDim2.new(
                    StartPos.X.Scale, StartPos.X.Offset + Delta.X,
                    StartPos.Y.Scale, StartPos.Y.Offset + Delta.Y
                )
            end
        end)
    end

    Gui.Parent = (gethui and gethui()) or Player:WaitForChild("PlayerGui")
    UpdateCounter()

    -- session timer
    task.spawn(function()
        while true do
            local t = math.floor(os.clock() - StartTime)
            TimeLabel.Text = string.format("%02d:%02d:%02d", t // 3600, (t % 3600) // 60, t % 60)
            task.wait(1)
        end
    end)
end

-- ===================== FARM =====================
local function DoAction()
    -- Do not run the farming action unless the Character attribute is Batter.
    if not IsCharacterReady() then
        return
    end

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
        WaitUntilReady()
        WaitForNextSlot()
        DoAction()
    end
end)

-- ===================== CLAIM LOOP =====================
task.spawn(function()
    while true do
        WaitUntilReady()
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
