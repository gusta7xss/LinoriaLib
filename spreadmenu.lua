local repo = 'https://raw.githubusercontent.com/gusta7xss/LinoriaLib/main/'

local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

-- Adonis bypass
local getinfo = getinfo or debug.getinfo
local DEBUG = false
local Hooked = {}

local Detected, Kill

setthreadidentity(2)

for i, v in getgc(true) do
    if typeof(v) == 'table' then
        local DetectFunc = rawget(v, 'Detected')
        local KillFunc = rawget(v, 'Kill')

        if typeof(DetectFunc) == 'function' and not Detected then
            Detected = DetectFunc

            local Old; Old = hookfunction(Detected, function(Action, Info, NoCrash)
                if Action ~= '_' then
                    if DEBUG then
                        warn(`Adonis AntiCheat flagged\nMethod: {Action}\nInfo: {Info}`)
                    end
                end

                return true
            end)

            table.insert(Hooked, Detected)
        end

        if rawget(v, 'Variables') and rawget(v, 'Process') and typeof(KillFunc) == 'function' and not Kill then
            Kill = KillFunc
            local Old; Old = hookfunction(Kill, function(Info)
                if DEBUG then
                    warn(`Adonis AntiCheat tried to kill (fallback): {Info}`)
                end
            end)

            table.insert(Hooked, Kill)
        end
    end
end

local Old; Old = hookfunction(getrenv().debug.info, newcclosure(function(...)
    local LevelOrFunc, Info = ...

    if Detected and LevelOrFunc == Detected then
        if DEBUG then
            warn(`Adonis AntiCheat sanity check detected and broken`)
        end

        return coroutine.yield(coroutine.running())
    end

    return Old(...)
end))

setthreadidentity(7)

-- Services
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local Workspace = game:GetService('Workspace')
local GuiService = game:GetService('GuiService')
local Stats = game:GetService('Stats')
local Lighting = game:GetService('Lighting')

local player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = player:GetMouse()

-- ============================================================
-- MOOZE SILENT AIM (núcleo) — controlado pela UI do Linoria
-- ============================================================
local MOOZE = {
    Lock = false,
    ShowFOV = false,
    FOV = 120,
    Prediction = 0,
    Smoothness = 0.025,
    HitChance = 100,
    VisibleCheck = false,
    TeamCheck = false,
    KOCheck = false,
    Method = 'Raycast',
}
getgenv().MOOZE = MOOZE

-- parte "virtual" que guarda o ponto de mira
local CachedAimPart = Instance.new('Part')
CachedAimPart.Name = 'mooze_aim'
CachedAimPart.Size = Vector3.new(1, 1, 1)
CachedAimPart.Transparency = 1
CachedAimPart.CanCollide = false
CachedAimPart.Anchored = true
CachedAimPart.CanQuery = false
CachedAimPart.CanTouch = false
CachedAimPart.Parent = Workspace
MOOZE.CachedAimPart = CachedAimPart

local FOVCircle
pcall(function()
    FOVCircle = Drawing.new('Circle')
    FOVCircle.Thickness = 1
    FOVCircle.NumSides = 60
    FOVCircle.Filled = false
    FOVCircle.Color = Color3.fromRGB(231, 84, 128)
    FOVCircle.Visible = false
end)

local rawCast = false
local function visRaycast(origin, dir, params)
    rawCast = true
    local ok, res = pcall(Workspace.Raycast, Workspace, origin, dir, params)
    rawCast = false
    if ok then return res end
    return nil
end

-- helpers
local function isKO(plr)
    local c = plr.Character
    if not c then return true end
    local be = c:FindFirstChild('BodyEffects')
    local ko = be and be:FindFirstChild('K.O')
    return ko ~= nil and ko.Value == true
end

local function isVisible(part, char)
    if not part then return false end
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character, cam, CachedAimPart }
    local hit = visRaycast(origin, part.Position - origin, params)
    return hit == nil or hit.Instance:IsDescendantOf(char)
end

local function passChance()
    if MOOZE.HitChance >= 100 then return true end
    return math.random() * 100 <= MOOZE.HitChance
end

-- escolhe o alvo mais próximo do centro da tela dentro do FOV
function MOOZE.getTarget()
    if not MOOZE.Lock or not passChance() then return nil end

    local char = player.Character
    if not char then return nil end

    local cam = Workspace.CurrentCamera
    local center = Vector2.new(Mouse.X, Mouse.Y + GuiService:GetGuiInset().Y)
    local radius = MOOZE.FOV
    local closest, closestDist = nil, math.huge

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local head = p.Character:FindFirstChild('Head')
            local hrp = p.Character:FindFirstChild('HumanoidRootPart')
            local hum = p.Character:FindFirstChildOfClass('Humanoid')

            if head and hrp and hum and hum.Health > 0 then
                local skip = false

                if MOOZE.TeamCheck and p.Team and p.Team == player.Team then
                    skip = true
                end
                if not skip and MOOZE.KOCheck and isKO(p) then
                    skip = true
                end
                if not skip and MOOZE.VisibleCheck and not isVisible(head, p.Character) then
                    skip = true
                end

                if not skip then
                    local pos, onScreen = cam:WorldToViewportPoint(head.Position)

                    -- ✅ CORREÇÃO: só considera se está na frente da câmera
                    if onScreen and pos.Z > 0 then
                        local d = (Vector2.new(pos.X, pos.Y) - center).Magnitude
                            if d <= radius and d < closestDist then
                                closestDist = d
                                closest = head
                            end
                        end
                    end
                end
            end
        end

    return closest
end

-- hook do raycast: redireciona o cast para o CachedAimPart
local mt = getrawmetatable(game)
local oldNamecall = mt.__namecall
setreadonly(mt, false)

mt.__namecall = newcclosure(function(Self, ...)
    local Method = getnamecallmethod()
    local Arguments = { ... }

        if not rawCast and MOOZE.Lock and MOOZE.HasTarget and MOOZE.Method == 'Raycast' and Self == Workspace and Method:find('cast') then
        local aimPos = CachedAimPart.Position
        if Method == 'Raycast' then
            Arguments[2] = (aimPos - Arguments[1]).Unit * 10000
        elseif Method == 'Shapecast' then
            Arguments[2] = (aimPos - Arguments[1].Position).Unit * 10000
        elseif Method == 'Spherecast' then
            Arguments[3] = (aimPos - Arguments[1]).Unit * 10000
        elseif Method == 'Blockcast' then
            Arguments[3] = (aimPos - Arguments[1].Position).Unit * 10000
        end
        return oldNamecall(Self, unpack(Arguments))
    end

    return oldNamecall(Self, ...)
end)

setreadonly(mt, true)

-- atualiza alvo e a parte virtual a cada frame
RunService.RenderStepped:Connect(function()
    -- FOV
    if FOVCircle then
        local inset = GuiService:GetGuiInset()
        FOVCircle.Position = Vector2.new(Mouse.X, Mouse.Y + inset.Y)
        FOVCircle.Radius = MOOZE.FOV
        FOVCircle.Visible = MOOZE.Lock and MOOZE.ShowFOV
    end

    if not MOOZE.Lock then return end

    local target = MOOZE.getTarget()
    MOOZE.HasTarget = target ~= nil
    if target then
        CachedAimPart.CFrame = CFrame.new(target.Position + target.AssemblyLinearVelocity * MOOZE.Prediction)
    end
end)

-- ESP (Drawing based, self contained). Tudo começa desligado.
local ESP = {
    Enabled = false,
    Box = false,
    BoxColor = Color3.fromRGB(216, 126, 157),
    Name = false,
    NamePos = 'Top',
    NameColor = Color3.fromRGB(255, 255, 255),
    Tracer = false,
    TracerColor = Color3.fromRGB(255, 255, 255),
    Health = false,
    Chams = false,
    ChamsColor = Color3.fromRGB(216, 126, 157),
    ChamsMaterial = 'Highlight',
    MaxDistance = 2000,
    TeamCheck = false,
    VisibleCheck = false,
}
getgenv().ESP = ESP

local ESPObjects = {}
local Highlights = {}
local PartCache = {}
local ESPConnections = {}

local ChamsMaterials = { 'Highlight', 'ForceField', 'Neon', 'Glass', 'Plastic' }

local function newDrawing(class, props)
    local ok, d = pcall(Drawing.new, class)
    if not ok or not d then return nil end
    for k, v in pairs(props) do
        d[k] = v
    end
    return d
end

local function createESP(plr)
    if plr == player or ESPObjects[plr] then return end
    ESPObjects[plr] = {
        BoxOutline = newDrawing('Square', { Thickness = 3, Filled = false, Color = Color3.new(0, 0, 0), Visible = false }),
        Box = newDrawing('Square', { Thickness = 1, Filled = false, Color = ESP.BoxColor, Visible = false }),
                Name = newDrawing('Text', { Size = 13, Center = true, Outline = true, Color = ESP.NameColor, Visible = false }),
        Tracer = newDrawing('Line', { Thickness = 1, Color = ESP.TracerColor, Visible = false }),
        HealthBg = newDrawing('Line', { Thickness = 4, Color = Color3.new(0, 0, 0), Visible = false }),
        HealthFg = newDrawing('Line', { Thickness = 2, Color = Color3.fromRGB(131, 245, 78), Visible = false }),
    }
end

local function destroyHighlight(plr)
    local h = Highlights[plr]
    if h then
        pcall(function() h:Destroy() end)
        Highlights[plr] = nil
    end
end

-- devolve material e cor originais das partes que foram trocadas pelo chams
local function restoreParts(plr)
    local cache = PartCache[plr]
    if not cache then return end
    for part, data in pairs(cache) do
        pcall(function()
            part.Material = data.Material
            part.Color = data.Color
        end)
    end
    PartCache[plr] = nil
end

local function removeESP(plr)
    local d = ESPObjects[plr]
    if d then
        for _, obj in pairs(d) do
            pcall(function() obj:Remove() end)
        end
        ESPObjects[plr] = nil
    end
    destroyHighlight(plr)
    restoreParts(plr)
end

local function hideESP(d)
    for _, obj in pairs(d) do
        obj.Visible = false
    end
end

-- bounding box projetada dos 8 cantos do bounding box do personagem
local function getScreenBox(char)
    local head = char:FindFirstChild('Head')
    local root = char:FindFirstChild('HumanoidRootPart')
    if not (head and root) then return nil end

    local hp = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, head.Size.Y / 2, 0))
    local fp = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
    if hp.Z <= 0 or fp.Z <= 0 then return nil end

    local h = math.abs(fp.Y - hp.Y)
    local w = h / 2
    local cx = (hp.X + fp.X) / 2
    return cx - w / 2, math.min(hp.Y, fp.Y), cx + w / 2, math.max(hp.Y, fp.Y)
end

local function isTeammate(plr)
    return ESP.TeamCheck and plr.Team ~= nil and plr.Team == player.Team
end

local function isVisible(char, root)
    local origin = Camera.CFrame.Position
    local dir = root.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { player.Character, Camera }
    local hit = visRaycast(origin, dir, params)
    return hit == nil or hit.Instance:IsDescendantOf(char)
end

local function updateChams(plr)
    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass('Humanoid')
    local active = ESP.Enabled and ESP.Chams and hum and hum.Health > 0 and not isTeammate(plr)
    local h = Highlights[plr]

    if not active then
        if h then h.Enabled = false end
        restoreParts(plr)
        return
    end

    if ESP.ChamsMaterial == 'Highlight' then
        restoreParts(plr)

        if not h then
            h = Instance.new('Highlight')
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.FillTransparency = 0.5
            h.OutlineTransparency = 0
            h.Parent = Workspace
            Highlights[plr] = h
        end

        h.Adornee = char
        h.FillColor = ESP.ChamsColor
        h.OutlineColor = ESP.ChamsColor
        h.Enabled = true
    else
        if h then h.Enabled = false end

        local cache = PartCache[plr] or {}
        PartCache[plr] = cache
        local mat = Enum.Material[ESP.ChamsMaterial]

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA('BasePart') then
                if not cache[part] then
                    cache[part] = { Material = part.Material, Color = part.Color }
                end
                part.Material = mat
                part.Color = ESP.ChamsColor
            end
        end
    end
end


local function updatePlayer(plr, d)
    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass('Humanoid')
    local root = char and char:FindFirstChild('HumanoidRootPart')

    if not (ESP.Enabled and char and hum and root and hum.Health > 0) then
        return hideESP(d)
    end

    if isTeammate(plr) then
        return hideESP(d)
    end

    if ESP.VisibleCheck and not isVisible(char, root) then
        return hideESP(d)
    end

    local dist = (Camera.CFrame.Position - root.Position).Magnitude
    if dist > ESP.MaxDistance then
        return hideESP(d)
    end

    local x1, y1, x2, y2 = getScreenBox(char)
    if not x1 then
        return hideESP(d)
    end

    local w, h = x2 - x1, y2 - y1

    -- box
    if ESP.Box then
        d.BoxOutline.Position = Vector2.new(x1, y1)
        d.BoxOutline.Size = Vector2.new(w, h)
        d.BoxOutline.Visible = true
        d.Box.Position = Vector2.new(x1, y1)
        d.Box.Size = Vector2.new(w, h)
        d.Box.Color = ESP.BoxColor
        d.Box.Visible = true
    else
        d.BoxOutline.Visible = false
        d.Box.Visible = false
    end

    -- tracer: centro de baixo da tela até os pés
    if ESP.Tracer then
        local vp = Camera.ViewportSize
        d.Tracer.From = Vector2.new(vp.X / 2, vp.Y)
        d.Tracer.To = Vector2.new((x1 + x2) / 2, y2)
        d.Tracer.Color = ESP.TracerColor
        d.Tracer.Visible = true
    else
        d.Tracer.Visible = false
    end

        -- name: acima do box, centralizado
    if ESP.Name then
        d.Name.Text = plr.DisplayName
        d.Name.Position = Vector2.new((x1 + x2) / 2, ESP.NamePos == 'Bottom' and (y2 + 2) or (y1 - 16))
        d.Name.Color = ESP.NameColor
        d.Name.Visible = true
    else
        d.Name.Visible = false
    end

    -- health: barra vertical à esquerda do box, cor pela vida
    if ESP.Health then
        local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
        local barX = x1 - 4
        d.HealthBg.From = Vector2.new(barX, y2)
        d.HealthBg.To = Vector2.new(barX, y1)
        d.HealthBg.Visible = true
        d.HealthFg.From = Vector2.new(barX, y2)
        d.HealthFg.To = Vector2.new(barX, y2 - h * hp)
        d.HealthFg.Color = Color3.fromRGB(255 * (1 - hp), 255 * hp, 0)
        d.HealthFg.Visible = true
    else
        d.HealthBg.Visible = false
        d.HealthFg.Visible = false
    end
end

for _, plr in ipairs(Players:GetPlayers()) do
    createESP(plr)
end

table.insert(ESPConnections, Players.PlayerAdded:Connect(createESP))
table.insert(ESPConnections, Players.PlayerRemoving:Connect(removeESP))

table.insert(ESPConnections, RunService.RenderStepped:Connect(function()
    for plr, d in pairs(ESPObjects) do
        local ok = pcall(updatePlayer, plr, d)
        if not ok then hideESP(d) end

        pcall(updateChams, plr)
    end
end))

-- Visuals word: ColorCorrection do Lighting (saturação, contraste, brilho, tint)
local VW = {
    Enabled = false,
    Brightness = 0,
    Contrast = 0,
    Saturation = 0,
    TintColor = Color3.fromRGB(255, 255, 255),
}

local ColorCorrection = Instance.new('ColorCorrectionEffect')
ColorCorrection.Name = 'SpreadVisualsWord'
ColorCorrection.Enabled = false
ColorCorrection.Brightness = VW.Brightness
ColorCorrection.Contrast = VW.Contrast
ColorCorrection.Saturation = VW.Saturation
ColorCorrection.TintColor = VW.TintColor
ColorCorrection.Parent = Lighting

-- Aim (camlock), independente do silent aim
local AIM = {
    Enabled = false,
    ShowFOV = true,
    FOVColor = Color3.fromRGB(255, 255, 255),
    FOVRadius = 150,
    Smoothness = 5,
    Prediction = 0.13,
    TargetPart = 'Head',
    KOCheck = false,
    VisibleCheck = false,
    TeamCheck = false,
}
getgenv().AIM = AIM

local AimCircle
pcall(function()
    AimCircle = Drawing.new('Circle')
    AimCircle.Thickness = 1
    AimCircle.NumSides = 60
    AimCircle.Filled = false
    AimCircle.Visible = false
end)

local LockedTarget = nil

local function getClosestPlayer()
    local closest, best = nil, AIM.FOVRadius
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)

    for _, v in ipairs(Players:GetPlayers()) do
        if v ~= player and v.Character then
            local part = v.Character:FindFirstChild(AIM.TargetPart)
            local hum = v.Character:FindFirstChildOfClass('Humanoid')
            local isTeam = AIM.TeamCheck and v.Team ~= nil and v.Team == player.Team
            local hidden = AIM.VisibleCheck and part and not isVisible(v.Character, part)
            local ko = AIM.KOCheck and isKO(v)

            if part and hum and hum.Health > 0 and not isTeam and not hidden and not ko then
                local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen and pos.Z > 0 then
                    local d = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
                    if d < best then
                        best = d
                        closest = v
                    end
                end
            end
        end
    end

    return closest
end

local function isValidTarget(plr)
    if not plr or not plr.Parent then return false end
    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass('Humanoid')
    local part = char and char:FindFirstChild(AIM.TargetPart)
    return hum ~= nil and hum.Health > 0 and part ~= nil
end

local function camlockStep()
    if not (AIM.Enabled and Options.CamlockKey and Options.CamlockKey:GetState()) then
        LockedTarget = nil
        return
    end

    if not isValidTarget(LockedTarget) then
        LockedTarget = getClosestPlayer()
    end
    if not LockedTarget then return end

    local part = LockedTarget.Character:FindFirstChild(AIM.TargetPart)
    if not part then return end

    local target = part.Position + part.AssemblyLinearVelocity * AIM.Prediction
    local goal = CFrame.lookAt(Camera.CFrame.Position, target)
    Camera.CFrame = Camera.CFrame:Lerp(goal, 1 / math.max(AIM.Smoothness, 1))
end

RunService:BindToRenderStep('SpreadCamlock', Enum.RenderPriority.Camera.Value + 1, camlockStep)

RunService.RenderStepped:Connect(function()
    if not AimCircle then return end
    pcall(function()
        local guiInset = GuiService:GetGuiInset()
        AimCircle.Position = Vector2.new(Mouse.X, Mouse.Y + guiInset.Y)
        AimCircle.Radius = AIM.FOVRadius
        AimCircle.Color = AIM.FOVColor
        AimCircle.Visible = AIM.Enabled and AIM.ShowFOV
    end)
end)

-- Player: movimento e stats
local UserInputService = game:GetService('UserInputService')

local PLAYER = {
    WalkSpeedEnabled = false,
    WalkSpeed = 16,
    JumpPowerEnabled = false,
    JumpPower = 50,
    InfiniteJump = false,
    Noclip = false,
}
getgenv().PLAYER = PLAYER

local function getCharAndHum()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass('Humanoid')
    return char, hum
end

table.insert(ESPConnections, RunService.Heartbeat:Connect(function()
    local char, hum = getCharAndHum()
    if not (char and hum) then return end

    if PLAYER.Noclip then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA('BasePart') then
                part.CanCollide = false
            end
        end
    end
end))

RunService:BindToRenderStep('SpreadJumpPower', Enum.RenderPriority.Last.Value, function()
    local _, h = getCharAndHum()
    if h and PLAYER.JumpPowerEnabled then
        h.UseJumpPower = true
        h.JumpPower = PLAYER.JumpPower
    end
end)

RunService:BindToRenderStep('SpreadWalkSpeed', Enum.RenderPriority.Last.Value, function()
    local _, h = getCharAndHum()
    if h and PLAYER.WalkSpeedEnabled then
        h.WalkSpeed = PLAYER.WalkSpeed
    end
end)

table.insert(ESPConnections, UserInputService.JumpRequest:Connect(function()
    if not PLAYER.InfiniteJump then return end
    local _, hum = getCharAndHum()
    if hum then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end))

-- Change hit box (usa uma parte separada: NAO mexe no corpo do player)
local HITBOX = {
    Enabled = false,
    Size = Vector3.new(20, 20, 20),
    Show = false,
    Color = Color3.fromRGB(216, 126, 157),
}
local hitboxApplied = {}

getgenv().HITBOX = HITBOX

local HITBOX_PART_NAME = 'SpreadHitbox'
local hookedChars = {}

local function refreshAll()
    for _, plr in ipairs(Players:GetPlayers()) do
        applyHitbox(plr)
    end
end

local function applyHitbox(plr)
    if plr == player or not plr.Character then return end
    local hum = plr.Character:FindFirstChildOfClass('Humanoid')
    local root = hum and hum.RootPart
    if not root then return end

    if HITBOX.Enabled then
        if not hitboxApplied[root] then
            hitboxApplied[root] = {
                Size = root.Size,
                Transparency = root.Transparency,
                CanCollide = root.CanCollide,
                Color = root.Color,
                Material = root.Material,
            }
        end
        root.CanCollide = false
        root.Size = HITBOX.Size
        root.Transparency = HITBOX.Show and 0.5 or 1
        root.Color = HITBOX.Color
        root.Material = Enum.Material.ForceField
    else
        local orig = hitboxApplied[root]
        if orig then
            root.Size = orig.Size
            root.Transparency = orig.Transparency
            root.CanCollide = orig.CanCollide
            root.Color = orig.Color
            root.Material = orig.Material
            hitboxApplied[root] = nil
        end
    end
end

-- reaplica a cada 5s, o jogo reseta o size
-- reaplica rápido: pega spawn, morte e reset do jogo
task.spawn(function()
    while true do
        if HITBOX.Enabled then
            for _, plr in ipairs(Players:GetPlayers()) do
                local root = plr.Character and plr.Character:FindFirstChild('HumanoidRootPart')
                if root and (root.Size ~= HITBOX.Size or root.Transparency ~= (HITBOX.Show and 0.5 or 1)) then
                    applyHitbox(plr)
                end
            end
        end
        task.wait(0.25)
    end
end)

-- conecta CharacterAdded uma vez por player (sem duplicar)
local function hookChar(plr)
    if hookedChars[plr] then return end
    hookedChars[plr] = true
    local function onChar(char)
        if plr == player then return end
        char:WaitForChild('Humanoid', 10)
        char:WaitForChild('HumanoidRootPart', 10)
        task.wait(0.2)
        applyHitbox(plr)
    end
    plr.CharacterAdded:Connect(onChar)
    if plr.Character then task.spawn(onChar, plr.Character) end
end

for _, plr in ipairs(Players:GetPlayers()) do
    hookChar(plr)
end
Players.PlayerAdded:Connect(hookChar)
Players.PlayerRemoving:Connect(function(plr)
    hookedChars[plr] = nil
end)

-- Impact notification
local IMPACT = {
    Enabled = false,
    Size = 16,
    Font = 'UI',
    Duration = 1,
    Rise = 2,
    Color = Color3.fromRGB(255, 80, 80),
}
getgenv().IMPACT = IMPACT

local FontMap = { UI = 0, System = 1, Plex = 2, Monospace = 3 }
local ImpactTexts = {}
local LastClickChar = nil
local LastClickTime = 0

table.insert(ESPConnections, UserInputService.InputBegan:Connect(function(Input, Processed)
    if Processed then return end
    if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local target = Mouse.Target
    LastClickChar = target and target:FindFirstAncestorOfClass('Model') or nil
    LastClickTime = os.clock()
end))

local function spawnImpact(worldPos, amount)
    local ok, txt = pcall(Drawing.new, 'Text')
    if not ok or not txt then return end
    txt.Text = tostring(math.floor(amount + 0.5))
    txt.Size = IMPACT.Size
    txt.Font = FontMap[IMPACT.Font] or 0
    txt.Center = true
    txt.Outline = true
    txt.Color = IMPACT.Color
    txt.Transparency = 1
    txt.Visible = true
    table.insert(ImpactTexts, { Drawing = txt, Origin = worldPos, Start = os.clock() })
end

table.insert(ESPConnections, RunService.RenderStepped:Connect(function()
    local now = os.clock()
    for i = #ImpactTexts, 1, -1 do
        local e = ImpactTexts[i]
        local t = (now - e.Start) / IMPACT.Duration
        if t >= 1 or not IMPACT.Enabled then
            pcall(function() e.Drawing:Remove() end)
            table.remove(ImpactTexts, i)
        else
            local pos, onScreen = Camera:WorldToViewportPoint(e.Origin + Vector3.new(0, t * IMPACT.Rise, 0))
            e.Drawing.Visible = onScreen and pos.Z > 0
            e.Drawing.Position = Vector2.new(pos.X, pos.Y)
            e.Drawing.Size = IMPACT.Size
            e.Drawing.Font = FontMap[IMPACT.Font] or 0
            e.Drawing.Transparency = 1 - t
        end
    end
end))

local function watchCharacter(plr, char)
    local hum = char:WaitForChild('Humanoid', 5)
    if not hum then return end
    local last = hum.Health
    table.insert(ESPConnections, hum.HealthChanged:Connect(function(hp)
        local delta = last - hp
        last = hp
        if not IMPACT.Enabled or delta <= 0 then return end
        if plr == player or isTeammate(plr) then return end
        if char ~= LastClickChar or (os.clock() - LastClickTime) > 0.5 then return end
        local root = char:FindFirstChild('HumanoidRootPart') or char:FindFirstChild('Head')
        if root then
            spawnImpact(root.Position + Vector3.new(0, 2, 0), delta)
        end
    end))
end

local function onPlayer(plr)
    if plr == player then return end
    table.insert(ESPConnections, plr.CharacterAdded:Connect(function(char)
        task.spawn(watchCharacter, plr, char)
    end))
    if plr.Character then
        task.spawn(watchCharacter, plr, plr.Character)
    end
end

for _, plr in ipairs(Players:GetPlayers()) do
    onPlayer(plr)
end
table.insert(ESPConnections, Players.PlayerAdded:Connect(onPlayer))

-- Backtrack visual (clone fantasma do personagem na pose de alguns ms atrás)
local BT = {
    Enabled = false,
    Color = Color3.fromRGB(255, 255, 255),
    Time = 0.5,
    Step = 0.05,
}
getgenv().BT = BT

local BTHistory = {}  -- [plr] = { {cf = {[partName] = CFrame}, t}, ... }
local BTGhost = {}    -- [plr] = { m = Model, char = Model }
local btLast = 0

local function btDestroyGhost(plr)
    local g = BTGhost[plr]
    if g then pcall(function() g.m:Destroy() end) end
    BTGhost[plr] = nil
end

local function btMakeGhost(char)
    pcall(function() char.Archivable = true end)
    local ok, m = pcall(function() return char:Clone() end)
    if not ok or not m then
        warn('[backtrack] clone falhou:', m)
        return nil
    end

    -- tira a hitbox separada e os scripts/humanoid do clone
    local hb = m:FindFirstChild('SpreadHitbox')
    if hb then hb:Destroy() end

    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA('Script') or d:IsA('LocalScript') or d:IsA('Humanoid') then
            d:Destroy()
        end
    end

    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA('BasePart') then
            p.Anchored = true
            p.CanCollide = false
            p.CanQuery = false
            p.CanTouch = false
            p.Transparency = 1
        end
    end

    local hl = Instance.new('Highlight')
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.FillColor = BT.Color
    hl.OutlineColor = BT.Color
    hl.Adornee = m
    hl.Parent = m

    m.Name = 'BT_' .. char.Name
    return m
end

local function btSnapshot(char)
    local cf = {}
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA('BasePart') then cf[p.Name] = p.CFrame end
    end
    return cf
end

table.insert(ESPConnections, RunService.Heartbeat:Connect(function()
    if not BT.Enabled then return end
    local now = os.clock()
    if now - btLast < BT.Step then return end
    btLast = now

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and plr.Character then
            local char = plr.Character
            local g = BTGhost[plr]
            if not g or g.char ~= char then
                btDestroyGhost(plr)
                local m = btMakeGhost(char)
                if m then BTGhost[plr] = { m = m, char = char } end
            end

            local h = BTHistory[plr] or {}
            BTHistory[plr] = h
            h[#h + 1] = { cf = btSnapshot(char), t = now }
        end
    end
end))

table.insert(ESPConnections, RunService.RenderStepped:Connect(function()
    if not BT.Enabled then
        for plr in pairs(BTGhost) do btDestroyGhost(plr) end
        for plr in pairs(BTHistory) do BTHistory[plr] = nil end
        return
    end

    local now = os.clock()
    for plr, h in pairs(BTHistory) do
        while #h > 0 and now - h[1].t > BT.Time do
            table.remove(h, 1)
        end

        local g = BTGhost[plr]
        if g then
            if #h > 0 then
                for name, cf in pairs(h[1].cf) do
                    local p = g.m:FindFirstChild(name)
                    if p then p.CFrame = cf end
                end
                if g.m.Parent ~= Workspace then g.m.Parent = Workspace end
            elseif g.m.Parent then
                g.m.Parent = nil
            end
        end
    end
end))

table.insert(ESPConnections, Players.PlayerRemoving:Connect(function(plr)
    BTHistory[plr] = nil
    btDestroyGhost(plr)
end))

-- Linoria menu
local Window = Library:CreateWindow({
    Title = 'Spread Menu',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.35
})

local Tabs = {
    Main = Window:AddTab('Main'),
    Visuals = Window:AddTab('Visuals'),
     Player = Window:AddTab('Player'),
    ['UI Settings'] = Window:AddTab('UI Settings'),
}

local TabBox = Tabs.Main:AddLeftTabbox()

local SilentTab = TabBox:AddTab('Silent')

SilentTab:AddToggle('SilentEnabled', {
    Text = 'Silent aim',
    Default = false,
    Callback = function(v) MOOZE.Lock = v end
})

SilentTab:AddToggle('SilentFOVVisible', {
    Text = 'Show FOV',
    Default = false,
    Callback = function(v) MOOZE.ShowFOV = v end
})

SilentTab:AddSlider('SilentFOV', {
    Text = 'FOV',
    Default = 120, Min = 5, Max = 800, Rounding = 0,
    Callback = function(v) MOOZE.FOV = v end
})

SilentTab:AddSlider('SilentHitChance', {
    Text = 'Hit chance',
    Default = 100, Min = 0, Max = 100, Rounding = 0,
    Callback = function(v) MOOZE.HitChance = v end
})

SilentTab:AddInput('SilentPrediction', {
    Text = 'Prediction',
    Default = '0',
    Numeric = true,
    Finished = true,
    Placeholder = '0',
    Callback = function(v)
        local n = tonumber(v)
        if n then MOOZE.Prediction = n end
    end
})

SilentTab:AddDropdown('SilentMethod', {
    Text = 'Method',
    Values = { 'Raycast' },
    Default = 'Raycast',
    Multi = false,
    Callback = function(v) MOOZE.Method = v end
})

local AimTab = TabBox:AddTab('Aim')

local CamlockToggle = AimTab:AddToggle('CamlockEnabled', {
    Text = 'Camlock',
    Default = false,
    Callback = function(v) AIM.Enabled = v end
})
CamlockToggle:AddKeyPicker('CamlockKey', {
    Default = 'None',
    Mode = 'Hold',
    Text = 'Camlock',
    NoUI = false,
})

local AimFOVToggle = AimTab:AddToggle('AimShowFOV', {
    Text = 'Show FOV',
    Default = true,
    Callback = function(v) AIM.ShowFOV = v end
})
AimFOVToggle:AddColorPicker('AimFOVColor', {
    Default = AIM.FOVColor,
    Title = 'FOV color',
    Callback = function(v) AIM.FOVColor = v end
})

AimTab:AddSlider('AimFOV', {
    Text = 'FOV size',
    Default = 150, Min = 10, Max = 800, Rounding = 0,
    Callback = function(v) AIM.FOVRadius = v end
})

AimTab:AddSlider('AimSmooth', {
    Text = 'Smoothness',
    Default = 5, Min = 1, Max = 20, Rounding = 0,
    Callback = function(v) AIM.Smoothness = v end
})

AimTab:AddInput('AimPrediction', {
    Text = 'Prediction',
    Default = '0.13',
    Numeric = true,
    Finished = true,
    Placeholder = '0.13',
    Callback = function(v)
        local n = tonumber(v)
        if n then AIM.Prediction = n end
    end
})

AimTab:AddDropdown('AimPart', {
    Text = 'Target part',
    Values = { 'Head', 'UpperTorso', 'HumanoidRootPart', 'LowerTorso' },
    Default = 'Head',
    Multi = false,
    Callback = function(v) AIM.TargetPart = v end
})

local AimSettingsSection = Tabs.Main:AddRightGroupbox('Aim settings')

AimSettingsSection:AddToggle('AimTeamCheck', {
    Text = 'Team check',
    Default = false,
    Callback = function(v) MOOZE.TeamCheck = v AIM.TeamCheck = v end
})

AimSettingsSection:AddToggle('AimVisibleCheck', {
    Text = 'Visible check',
    Default = false,
    Callback = function(v) MOOZE.VisibleCheck = v AIM.VisibleCheck = v end
})

AimSettingsSection:AddToggle('AimKOCheck', {
    Text = 'K.O check',
    Default = false,
    Callback = function(v) MOOZE.KOCheck = v end
})
-- Triggerbot
local TRIG = {
    Enabled = false,
    Mode = 'Always',
    Delay = 50,
    KOCheck = true,
}
getgenv().TRIG = TRIG

local trigSeen = nil
local trigLast = 0

local function trigActive()
    if not TRIG.Enabled then return false end
    local kp = Options.TriggerbotKey
    return (kp and kp:GetState()) or false
end

local function trigTargetModel()
    local hit = Mouse.Target
    if not hit then return nil end
    local model = hit:FindFirstAncestorOfClass('Model')
    if not model or model == player.Character then return nil end
    if not Players:GetPlayerFromCharacter(model) then return nil end
    return model
end

local function trigAlive(model)
    local hum = model:FindFirstChildOfClass('Humanoid')
    if not hum or hum.Health <= 0 then return false end
    if TRIG.KOCheck then
        local fx = model:FindFirstChild('BodyEffects')
        local ko = fx and fx:FindFirstChild('K.O')
        if ko and ko.Value then return false end
    end
    return true
end

RunService.Heartbeat:Connect(function()
    if not trigActive() then
        trigSeen = nil
        return
    end
    local model = trigTargetModel()
    if not (model and trigAlive(model)) then
        trigSeen = nil
        return
    end
    local now = os.clock()
    if not trigSeen then trigSeen = now end
    if (now - trigSeen) * 1000 < TRIG.Delay then return end
    if now - trigLast < 0.1 then return end
    trigLast = now
    mouse1click()
end)

local TriggerSection = Tabs.Main:AddLeftGroupbox('Triggerbot')

local TrigToggle = TriggerSection:AddToggle('TriggerbotEnabled', {
    Text = 'Enable',
    Default = false,
    Callback = function(v) TRIG.Enabled = v end
})
TrigToggle:AddKeyPicker('TriggerbotKey', {
    Default = 'None',
    Mode = 'Toggle',
    Modes = { 'Always', 'Toggle', 'Hold' },
    Text = 'Triggerbot',
})

TriggerSection:AddSlider('TriggerbotDelay', {
    Text = 'Delay (ms)',
    Default = 50, Min = 0, Max = 500, Rounding = 0,
    Callback = function(v) TRIG.Delay = v end
})

TriggerSection:AddToggle('TriggerbotKOCheck', {
    Text = 'K.O check',
    Default = true,
    Callback = function(v) TRIG.KOCheck = v end
})

local HitboxSection = Tabs.Main:AddRightGroupbox('Change hit box')

HitboxSection:AddToggle('HitboxEnabled', {
    Text = 'Enable',
    Default = false,
    Callback = function(v)
        HITBOX.Enabled = v
        refreshAll()
    end
})

local HitboxShowToggle = HitboxSection:AddToggle('HitboxShow', {
    Text = 'Show hitbox',
    Default = false,
    Callback = function(v)
        HITBOX.Show = v
        if HITBOX.Enabled then refreshAll() end
    end
})
HitboxShowToggle:AddColorPicker('HitboxColor', {
    Default = HITBOX.Color,
    Title = 'Hitbox color',
    Callback = function(v)
        HITBOX.Color = v
        if HITBOX.Enabled then refreshAll() end
    end
})

HitboxSection:AddSlider('HitboxSizeX', {
    Text = 'Size',
    Default = 20, Min = 2, Max = 60, Rounding = 0,
    Callback = function(v)
        HITBOX.Size = Vector3.new(v, v, v)
        if HITBOX.Enabled then refreshAll() end
    end
})

-- Visuals > ESP
local ESPSection = Tabs.Visuals:AddLeftGroupbox('ESP')

ESPSection:AddToggle('ESPEnabled', {
    Text = 'Enable',
    Default = false,
    Callback = function(v) ESP.Enabled = v end
})

local BoxToggle = ESPSection:AddToggle('ESPBox', {
    Text = 'Box',
    Default = false,
    Callback = function(v) ESP.Box = v end
})
local NameToggle = ESPSection:AddToggle('ESPName', {
    Text = 'Name',
    Default = false,
    Callback = function(v) ESP.Name = v end
})
local NamePosBox = ESPSection:AddDependencyBox()
NamePosBox:AddDropdown('ESPNamePos', {
    Text = 'Name position',
    Values = { 'Top', 'Bottom' },
    Default = 'Top',
    Multi = false,
    Callback = function(v) ESP.NamePos = v end
})
NamePosBox:SetupDependencies({
    { NameToggle, true }
})
BoxToggle:AddColorPicker('ESPBoxColor', {
    Default = ESP.BoxColor,
    Title = 'Box color',
    Callback = function(v) ESP.BoxColor = v end
})

local TracerToggle = ESPSection:AddToggle('ESPTracer', {
    Text = 'Tracer',
    Default = false,
    Callback = function(v) ESP.Tracer = v end
})
TracerToggle:AddColorPicker('ESPTracerColor', {
    Default = ESP.TracerColor,
    Title = 'Tracer color',
    Callback = function(v) ESP.TracerColor = v end
})

ESPSection:AddToggle('ESPHealth', {
    Text = 'Health',
    Default = false,
    Callback = function(v) ESP.Health = v end
})

-- Visuals > Chams
local ChamsSection = Tabs.Visuals:AddRightGroupbox('Chams')

local ChamsToggle = ChamsSection:AddToggle('ChamsEnabled', {
    Text = 'Chams',
    Default = false,
    Callback = function(v) ESP.Chams = v end
})
ChamsToggle:AddColorPicker('ChamsColor', {
    Default = ESP.ChamsColor,
    Title = 'Chams color',
    Callback = function(v) ESP.ChamsColor = v end
})

ChamsSection:AddDropdown('ChamsMaterial', {
    Text = 'Material',
    Values = ChamsMaterials,
    Default = 'Highlight',
    Multi = false,
    Callback = function(v) ESP.ChamsMaterial = v end
})

-- Visuals word
local VisualsWordSection = Tabs.Visuals:AddRightGroupbox('Visuals word')

VisualsWordSection:AddToggle('VWEnabled', {
    Text = 'Enable',
    Default = false,
    Callback = function(v)
        VW.Enabled = v
        ColorCorrection.Enabled = v
    end
})

VisualsWordSection:AddSlider('VWSaturation', {
    Text = 'Saturation',
    Default = 0, Min = -1, Max = 1, Rounding = 2,
    Callback = function(v)
        VW.Saturation = v
        ColorCorrection.Saturation = v
    end
})

VisualsWordSection:AddSlider('VWContrast', {
    Text = 'Contrast',
    Default = 0, Min = -1, Max = 1, Rounding = 2,
    Callback = function(v)
        VW.Contrast = v
        ColorCorrection.Contrast = v
    end
})

VisualsWordSection:AddSlider('VWBrightness', {
    Text = 'Brightness',
    Default = 0, Min = -1, Max = 1, Rounding = 2,
    Callback = function(v)
        VW.Brightness = v
        ColorCorrection.Brightness = v
    end
})

local TintToggle = VisualsWordSection:AddLabel('Tint')
TintToggle:AddColorPicker('VWTint', {
    Default = VW.TintColor,
    Title = 'Tint color',
    Callback = function(v)
        VW.TintColor = v
        ColorCorrection.TintColor = v
    end
})

local ImpactSection = Tabs.Visuals:AddLeftGroupbox('Impact notification')

local ImpactEnabledToggle = ImpactSection:AddToggle('ImpactEnabled', {
    Text = 'Enable',
    Default = false,
    Callback = function(v) IMPACT.Enabled = v end
})
ImpactEnabledToggle:AddColorPicker('ImpactColor', {
    Default = IMPACT.Color,
    Title = 'Impact color',
    Callback = function(v) IMPACT.Color = v end
})

ImpactSection:AddSlider('ImpactSize', {
    Text = 'Size',
    Default = 16, Min = 8, Max = 40, Rounding = 0,
    Callback = function(v) IMPACT.Size = v end
})

ImpactSection:AddDropdown('ImpactFont', {
    Text = 'Font',
    Values = { 'UI', 'System', 'Plex', 'Monospace' },
    Default = 'UI',
    Multi = false,
    Callback = function(v) IMPACT.Font = v end
})

local BacktrackSection = Tabs.Visuals:AddRightGroupbox('Backtrack')

local BacktrackToggle = BacktrackSection:AddToggle('BacktrackEnabled', {
    Text = 'Enable',
    Default = false,
    Callback = function(v) BT.Enabled = v end
})
BacktrackToggle:AddColorPicker('BacktrackColor', {
    Default = BT.Color,
    Title = 'Backtrack color',
    Callback = function(v)
        BT.Color = v
        for _, g in pairs(BTGhost) do
            local hl = g.m:FindFirstChildOfClass('Highlight')
            if hl then
                hl.FillColor = v
                hl.OutlineColor = v
            end
        end
    end
})

local VisualsSettingsSection = Tabs.Visuals:AddLeftGroupbox('Visuals settings')

VisualsSettingsSection:AddToggle('TeamCheck', {
    Text = 'Team check',
    Default = false,
    Callback = function(v) ESP.TeamCheck = v end
})

VisualsSettingsSection:AddToggle('VisibleCheck', {
    Text = 'Visible check',
    Default = false,
    Callback = function(v) ESP.VisibleCheck = v end
})

-- ============================================================
-- WORLD (fog, atmosphere, ambient, bloom, sunrays)
-- ============================================================
local WORLD = {
    FogEnabled = false,
    FogColor = Color3.fromRGB(200, 200, 200),
    FogEnd = 1000,
    FogStart = 0,

    AtmosphereEnabled = false,
    AtmosphereColor = Color3.fromRGB(199, 199, 199),
    AtmosphereDensity = 0.3,
    AtmosphereHaze = 0,
    AtmosphereGlare = 0,
    AtmosphereOffset = 0,

    AmbientEnabled = false,
    AmbientColor = Color3.fromRGB(128, 128, 128),
    OutdoorAmbientColor = Color3.fromRGB(128, 128, 128),

    ClockEnabled = false,
    ClockTime = 14,

    BloomEnabled = false,
    BloomColor = Color3.fromRGB(255, 255, 255),
    BloomIntensity = 0.5,
    BloomSize = 24,

    SunRaysEnabled = false,
    SunRaysIntensity = 0.1,
    SunRaysSpread = 1,
}
getgenv().WORLD = WORLD

-- guarda os valores originais para restaurar
local WorldOriginal = {
    FogColor = Lighting.FogColor,
    FogStart = Lighting.FogStart,
    FogEnd = Lighting.FogEnd,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    ClockTime = Lighting.ClockTime,
    Atmosphere = nil,
    Bloom = nil,
    SunRays = nil,
}

-- cria/pega Atmosphere
local Atmosphere
for _, v in ipairs(Lighting:GetChildren()) do
    if v:IsA('Atmosphere') then Atmosphere = v break end
end
if not Atmosphere then
    Atmosphere = Instance.new('Atmosphere')
    Atmosphere.Parent = Lighting
    WorldOriginal.Atmosphere = 'created'
else
    WorldOriginal.Atmosphere = {
        Density = Atmosphere.Density,
        Offset = Atmosphere.Offset,
        Color = Atmosphere.Color,
        Decay = Atmosphere.Decay,
        Glare = Atmosphere.Glare,
        Haze = Atmosphere.Haze,
    }
end

-- cria/pega Bloom
local Bloom
for _, v in ipairs(Lighting:GetChildren()) do
    if v:IsA('BloomEffect') then Bloom = v break end
end
if not Bloom then
    Bloom = Instance.new('BloomEffect')
    Bloom.Parent = Lighting
    WorldOriginal.Bloom = 'created'
else
    WorldOriginal.Bloom = {
        Enabled = Bloom.Enabled,
        Intensity = Bloom.Intensity,
        Size = Bloom.Size,
        Threshold = Bloom.Threshold,
    }
end

-- cria/pega SunRays
local SunRays
for _, v in ipairs(Lighting:GetChildren()) do
    if v:IsA('SunRaysEffect') then SunRays = v break end
end
if not SunRays then
    SunRays = Instance.new('SunRaysEffect')
    SunRays.Parent = Lighting
    WorldOriginal.SunRays = 'created'
else
    WorldOriginal.SunRays = {
        Enabled = SunRays.Enabled,
        Intensity = SunRays.Intensity,
        Spread = SunRays.Spread,
    }
end

local function ensureFogOriginal()
    if WORLD._fogOriginalSaved then return end
    WorldOriginal.FogColor = Lighting.FogColor
    WorldOriginal.FogStart = Lighting.FogStart
    WorldOriginal.FogEnd = Lighting.FogEnd
    WORLD._fogOriginalSaved = true
end

-- aplica o estado atual do WORLD
local function applyWorld()
    -- FOG
    if WORLD.FogEnabled then
        Lighting.FogColor = WORLD.FogColor
        Lighting.FogStart = WORLD.FogStart
        Lighting.FogEnd = WORLD.FogEnd
        WORLD._fogWasOn = true
    elseif WORLD._fogWasOn then
        Lighting.FogColor = WorldOriginal.FogColor
        Lighting.FogStart = WorldOriginal.FogStart
        Lighting.FogEnd = WorldOriginal.FogEnd
        WORLD._fogWasOn = false
    end

    -- ATMOSPHERE
    if WORLD.AtmosphereEnabled then
        Atmosphere.Density = WORLD.AtmosphereDensity
        Atmosphere.Offset = WORLD.AtmosphereOffset
        Atmosphere.Color = WORLD.AtmosphereColor
        Atmosphere.Glare = WORLD.AtmosphereGlare
        Atmosphere.Haze = WORLD.AtmosphereHaze
        WORLD._atmosWasOn = true
    elseif WORLD._atmosWasOn and type(WorldOriginal.Atmosphere) == 'table' then
        Atmosphere.Density = WorldOriginal.Atmosphere.Density
        Atmosphere.Offset = WorldOriginal.Atmosphere.Offset
        Atmosphere.Color = WorldOriginal.Atmosphere.Color
        Atmosphere.Glare = WorldOriginal.Atmosphere.Glare
        Atmosphere.Haze = WorldOriginal.Atmosphere.Haze
        WORLD._atmosWasOn = false
    end

    -- AMBIENT
    if WORLD.AmbientEnabled then
        Lighting.Ambient = WORLD.AmbientColor
        Lighting.OutdoorAmbient = WORLD.OutdoorAmbientColor
        WORLD._ambientWasOn = true
    elseif WORLD._ambientWasOn then
        Lighting.Ambient = WorldOriginal.Ambient
        Lighting.OutdoorAmbient = WorldOriginal.OutdoorAmbient
        WORLD._ambientWasOn = false
    end

    -- CLOCK
    if WORLD.ClockEnabled then
        Lighting.ClockTime = WORLD.ClockTime
        WORLD._clockWasOn = true
    elseif WORLD._clockWasOn then
        Lighting.ClockTime = WorldOriginal.ClockTime
        WORLD._clockWasOn = false
    end

    -- BLOOM
    if WORLD.BloomEnabled then
        Bloom.Enabled = true
        Bloom.Intensity = WORLD.BloomIntensity
        Bloom.Size = WORLD.BloomSize
        Bloom.Threshold = 0.5
        WORLD._bloomWasOn = true
    elseif WORLD._bloomWasOn and type(WorldOriginal.Bloom) == 'table' then
        Bloom.Enabled = WorldOriginal.Bloom.Enabled
        Bloom.Intensity = WorldOriginal.Bloom.Intensity
        Bloom.Size = WorldOriginal.Bloom.Size
        Bloom.Threshold = WorldOriginal.Bloom.Threshold
        WORLD._bloomWasOn = false
    end

    -- SUNRAYS
    if WORLD.SunRaysEnabled then
        SunRays.Enabled = true
        SunRays.Intensity = WORLD.SunRaysIntensity
        SunRays.Spread = WORLD.SunRaysSpread
        WORLD._sunWasOn = true
    elseif WORLD._sunWasOn and type(WorldOriginal.SunRays) == 'table' then
        SunRays.Enabled = WorldOriginal.SunRays.Enabled
        SunRays.Intensity = WorldOriginal.SunRays.Intensity
        SunRays.Spread = WorldOriginal.SunRays.Spread
        WORLD._sunWasOn = false
    end
end

-- UI
local WorldSection = Tabs.Visuals:AddRightGroupbox('World')

-- FOG
local FogToggle = WorldSection:AddToggle('WorldFogEnabled', {
    Text = 'Fog',
    Default = false,
    Callback = function(v) WORLD.FogEnabled = v applyWorld() end
})
FogToggle:AddColorPicker('WorldFogColor', {
    Default = WORLD.FogColor,
    Title = 'Fog color',
    Callback = function(v) WORLD.FogColor = v applyWorld() end
})
WorldSection:AddSlider('WorldFogEnd', {
    Text = 'Fog distance',
    Default = 1000, Min = 50, Max = 5000, Rounding = 0,
    Callback = function(v) WORLD.FogEnd = v applyWorld() end
})

-- ATMOSPHERE
local AtmosToggle = WorldSection:AddToggle('WorldAtmosEnabled', {
    Text = 'Atmosphere',
    Default = false,
    Callback = function(v) WORLD.AtmosphereEnabled = v applyWorld() end
})
AtmosToggle:AddColorPicker('WorldAtmosColor', {
    Default = WORLD.AtmosphereColor,
    Title = 'Atmosphere color',
    Callback = function(v) WORLD.AtmosphereColor = v applyWorld() end
})
WorldSection:AddSlider('WorldAtmosDensity', {
    Text = 'Density',
    Default = 0.3, Min = 0, Max = 1, Rounding = 2,
    Callback = function(v) WORLD.AtmosphereDensity = v applyWorld() end
})
WorldSection:AddSlider('WorldAtmosHaze', {
    Text = 'Haze',
    Default = 0, Min = 0, Max = 10, Rounding = 1,
    Callback = function(v) WORLD.AtmosphereHaze = v applyWorld() end
})
WorldSection:AddSlider('WorldAtmosGlare', {
    Text = 'Glare',
    Default = 0, Min = 0, Max = 10, Rounding = 1,
    Callback = function(v) WORLD.AtmosphereGlare = v applyWorld() end
})

-- AMBIENT
local AmbientToggle = WorldSection:AddToggle('WorldAmbientEnabled', {
    Text = 'Ambient light',
    Default = false,
    Callback = function(v) WORLD.AmbientEnabled = v applyWorld() end
})
AmbientToggle:AddColorPicker('WorldAmbientColor', {
    Default = WORLD.AmbientColor,
    Title = 'Ambient color',
    Callback = function(v) WORLD.AmbientColor = v applyWorld() end
})
AmbientToggle:AddColorPicker('WorldOutdoorAmbientColor', {
    Default = WORLD.OutdoorAmbientColor,
    Title = 'Outdoor ambient',
    Callback = function(v) WORLD.OutdoorAmbientColor = v applyWorld() end
})

-- CLOCKTIME
local ClockToggle = WorldSection:AddToggle('WorldClockEnabled', {
    Text = 'Clock time',
    Default = false,
    Callback = function(v) WORLD.ClockEnabled = v applyWorld() end
})
WorldSection:AddSlider('WorldClockTime', {
    Text = 'Hour',
    Default = 14, Min = 0, Max = 24, Rounding = 0,
    Callback = function(v) WORLD.ClockTime = v applyWorld() end
})

-- BLOOM
local BloomToggle = WorldSection:AddToggle('WorldBloomEnabled', {
    Text = 'Bloom',
    Default = false,
    Callback = function(v) WORLD.BloomEnabled = v applyWorld() end
})
BloomToggle:AddColorPicker('WorldBloomColor', {
    Default = WORLD.BloomColor,
    Title = 'Bloom color',
    Callback = function(v) WORLD.BloomColor = v applyWorld() end
})
WorldSection:AddSlider('WorldBloomIntensity', {
    Text = 'Bloom intensity',
    Default = 0.5, Min = 0, Max = 5, Rounding = 2,
    Callback = function(v) WORLD.BloomIntensity = v applyWorld() end
})

-- SUNRAYS
local SunToggle = WorldSection:AddToggle('WorldSunEnabled', {
    Text = 'Sun rays',
    Default = false,
    Callback = function(v) WORLD.SunRaysEnabled = v applyWorld() end
})
WorldSection:AddSlider('WorldSunIntensity', {
    Text = 'Sun intensity',
    Default = 0.1, Min = 0, Max = 1, Rounding = 2,
    Callback = function(v) WORLD.SunRaysIntensity = v applyWorld() end
})
WorldSection:AddSlider('WorldSunSpread', {
    Text = 'Sun spread',
    Default = 1, Min = 0, Max = 5, Rounding = 2,
    Callback = function(v) WORLD.SunRaysSpread = v applyWorld() end
})

local PlayerTab = Tabs.Player

local MovementSection = PlayerTab:AddLeftGroupbox('Movement')

local WalkToggle = MovementSection:AddToggle('PlrWalkSpeedEnabled', {
    Text = 'WalkSpeed',
    Default = false,
    Callback = function(v) PLAYER.WalkSpeedEnabled = v end
})
WalkToggle:AddKeyPicker('WalkSpeedKey', {
    Default = 'None',
    Mode = 'Toggle',
    SyncToggleState = true,
    Text = 'WalkSpeed',
    NoUI = false,
})
MovementSection:AddSlider('PlrWalkSpeed', {
    Text = 'WalkSpeed value',
    Default = 16, Min = 16, Max = 750, Rounding = 0,
    Callback = function(v) PLAYER.WalkSpeed = v end
})

local JumpToggle = MovementSection:AddToggle('PlrJumpPowerEnabled', {
    Text = 'JumpPower',
    Default = false,
    Callback = function(v) PLAYER.JumpPowerEnabled = v end
})
JumpToggle:AddKeyPicker('JumpPowerKey', {
    Default = 'None',
    Mode = 'Toggle',
    SyncToggleState = true,
    Text = 'JumpPower',
    NoUI = false,
})
MovementSection:AddSlider('PlrJumpPower', {
    Text = 'JumpPower value',
    Default = 50, Min = 50, Max = 300, Rounding = 0,
    Callback = function(v) PLAYER.JumpPower = v end
})

-- No slowdown (independente do WalkSpeed)
local NOSLOW = { Enabled = false, Floor = 18 }
getgenv().NOSLOW = NOSLOW

local noSlowHum, noSlowConn = nil, nil

local function noSlowHook(hum)
    if noSlowConn then noSlowConn:Disconnect() end
    noSlowHum = hum
    noSlowConn = hum:GetPropertyChangedSignal('WalkSpeed'):Connect(function()
        if NOSLOW.Enabled and hum.WalkSpeed < NOSLOW.Floor then
            hum.WalkSpeed = NOSLOW.Floor
        end
    end)
end

RunService:BindToRenderStep('SpreadNoSlow', Enum.RenderPriority.Last.Value, function()
    if not NOSLOW.Enabled then return end
    local _, h = getCharAndHum()
    if h and h ~= noSlowHum then noSlowHook(h) end
end)

local NoSlowToggle = MovementSection:AddToggle('PlrNoSlowdown', {
    Text = 'No slowdown',
    Default = false,
    Callback = function(v) NOSLOW.Enabled = v end
})
NoSlowToggle:AddKeyPicker('NoSlowdownKey', {
    Default = 'None',
    Mode = 'Toggle',
    Text = 'No slowdown',
})

local MiscSection = PlayerTab:AddRightGroupbox('Misc')

MiscSection:AddToggle('PlrInfiniteJump', {
    Text = 'Infinite jump',
    Default = false,
    Callback = function(v) PLAYER.InfiniteJump = v end
})
MiscSection:AddToggle('PlrNoclip', {
    Text = 'Noclip',
    Default = false,
    Callback = function(v) PLAYER.Noclip = v end
})

-- Fly
local FLY = { Enabled = false, Speed = 50, Mode = 'Velocity' }
getgenv().FLY = FLY

local flyWasOn = false

local function flyDirection()
    local dir = Vector3.zero
    local cf = Camera.CFrame
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
    return dir.Magnitude > 0 and dir.Unit or Vector3.zero
end

table.insert(ESPConnections, RunService.Heartbeat:Connect(function(dt)
    local char, hum = getCharAndHum()
    local root = char and char:FindFirstChild('HumanoidRootPart')

    if not (FLY.Enabled and root and hum and hum.Health > 0) then
        if flyWasOn and hum then hum.PlatformStand = false end
        flyWasOn = false
        return
    end

    flyWasOn = true
    hum.PlatformStand = true

    local dir = flyDirection()
    if FLY.Mode == 'Velocity' then
        root.AssemblyLinearVelocity = dir * FLY.Speed
    else
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = root.CFrame + dir * FLY.Speed * dt
    end
end))

local FlySection = PlayerTab:AddLeftGroupbox('Fly')

local FlyToggle = FlySection:AddToggle('FlyEnabled', {
    Text = 'Fly',
    Default = false,
    Callback = function(v) FLY.Enabled = v end
})
FlyToggle:AddKeyPicker('FlyKey', {
    Default = 'None',
    Mode = 'Toggle',
    SyncToggleState = true,
    Text = 'Fly',
    NoUI = false,
})

FlySection:AddSlider('FlySpeed', {
    Text = 'Speed',
    Default = 50, Min = 10, Max = 300, Rounding = 0,
    Callback = function(v) FLY.Speed = v end
})

FlySection:AddDropdown('FlyMode', {
    Text = 'Mode',
    Values = { 'Velocity', 'Normal' },
    Default = 'Velocity',
    Multi = false,
    Callback = function(v) FLY.Mode = v end
})

Library:SetWatermarkVisibility(true)

local FrameTimer = tick()
local FrameCounter = 0
local FPS = 60

local WatermarkConnection = RunService.RenderStepped:Connect(function()
    FrameCounter += 1

    if (tick() - FrameTimer) >= 1 then
        FPS = FrameCounter
        FrameTimer = tick()
        FrameCounter = 0
    end

    Library:SetWatermark(('Spread Menu | %s fps | %s ms'):format(
        math.floor(FPS),
        math.floor(Stats.Network.ServerStatsItem['Data Ping']:GetValue())
    ))
end)

-- ESP preview ao lado do menu (aba Visuals)
local ESPRef = getgenv().ESP
local visualsActive = false
local PW, PH = 260, 360
local BoxX, BoxY, BoxW, BoxH = 70, 60, 120, 240

local PreviewFrame = Instance.new('Frame')
PreviewFrame.Name = 'ESPPreview'
PreviewFrame.Size = UDim2.fromOffset(PW, PH)
PreviewFrame.BackgroundColor3 = Library.BackgroundColor
PreviewFrame.BorderColor3 = Library.AccentColor
Library:AddToRegistry(PreviewFrame, { BorderColor3 = 'AccentColor' })
PreviewFrame.BorderMode = Enum.BorderMode.Inset
PreviewFrame.ZIndex = 2
PreviewFrame.Visible = false
PreviewFrame.Parent = Library.ScreenGui

Library:Create('TextLabel', {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 4),
    Size = UDim2.new(1, 0, 0, 14),
    Font = Library.Font,
    TextSize = 14,
    Text = 'ESP preview',
    TextColor3 = Library.FontColor,
    ZIndex = 3,
    Parent = PreviewFrame,
})

-- viewport 3D com o personagem
local Viewport = Instance.new('ViewportFrame')
Viewport.BackgroundTransparency = 1
Viewport.Position = UDim2.fromOffset(4, 22)
Viewport.Size = UDim2.new(1, -8, 1, -26)
Viewport.ZIndex = 3
Viewport.Parent = PreviewFrame

local ViewCam = Instance.new('Camera')
ViewCam.Parent = Viewport
Viewport.CurrentCamera = ViewCam

local Dummy
pcall(function()
    Dummy = Players:CreateHumanoidModelFromUserId(player.UserId)
end)
if not Dummy then
    Dummy = Instance.new('Model')
end
for _, d in ipairs(Dummy:GetDescendants()) do
    if d:IsA('Script') or d:IsA('LocalScript') then d:Destroy() end
end
Dummy.Parent = Viewport

-- guarda cor/material originais pra restaurar quando o chams desligar
local PreviewParts = {}
for _, p in ipairs(Dummy:GetDescendants()) do
    if p:IsA('BasePart') then
        PreviewParts[p] = { Color = p.Color, Material = p.Material }
    end
end

-- overlays do ESP por cima do modelo
local PreviewBox = Library:Create('Frame', {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(BoxX, BoxY),
    Size = UDim2.fromOffset(BoxW, BoxH),
    ZIndex = 4,
    Parent = PreviewFrame,
})
local PreviewBoxStroke = Library:Create('UIStroke', { Thickness = 1, Parent = PreviewBox })

local PreviewName = Library:Create('TextLabel', {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(BoxX, BoxY - 18),
    Size = UDim2.fromOffset(BoxW, 14),
    Font = Library.Font,
    TextSize = 13,
    Text = player.DisplayName,
    TextStrokeTransparency = 0,
    ZIndex = 5,
    Parent = PreviewFrame,
})

local PreviewHealthBg = Library:Create('Frame', {
    BackgroundColor3 = Color3.new(0, 0, 0),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(BoxX - 8, BoxY),
    Size = UDim2.fromOffset(4, BoxH),
    ZIndex = 4,
    Parent = PreviewFrame,
})
local PreviewHealthFg = Library:Create('Frame', {
    BorderSizePixel = 0,
    ZIndex = 5,
    Parent = PreviewHealthBg,
})

local PreviewTracer = Library:Create('Frame', {
    BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.fromOffset(BoxX + BoxW / 2, BoxY + BoxH),
    Size = UDim2.fromOffset(1, PH - (BoxY + BoxH)),
    ZIndex = 4,
    Parent = PreviewFrame,
})

local PreviewConn = RunService.RenderStepped:Connect(function()
    if not (visualsActive and Window.Holder.Visible) then
        PreviewFrame.Visible = false
        return
    end

    PreviewFrame.Visible = true
    local ap, as = Window.Holder.AbsolutePosition, Window.Holder.AbsoluteSize
    PreviewFrame.Position = UDim2.fromOffset(ap.X + as.X + 10, ap.Y)

    -- câmera girando devagar em volta do personagem
    local root = Dummy:FindFirstChild('HumanoidRootPart')
    if root then
        local spin = os.clock() * 0.5
        local offset = Vector3.new(math.sin(spin) * 6, 1.5, math.cos(spin) * 6)
        ViewCam.CFrame = CFrame.lookAt(root.Position + offset, root.Position + Vector3.new(0, 0, 0))
    end

    -- chams: pinta as partes do personagem
    for p, orig in pairs(PreviewParts) do
        if p.Parent then
            if ESPRef.Chams then
                p.Color = ESPRef.ChamsColor
                p.Material = Enum.Material.ForceField
            else
                p.Color = orig.Color
                p.Material = orig.Material
            end
        end
    end

    -- caixa
    PreviewBox.Visible = ESPRef.Box
    PreviewBoxStroke.Color = ESPRef.BoxColor

    -- nome
    PreviewName.Visible = ESPRef.Name
        PreviewName.Position = UDim2.fromOffset(BoxX, ESPRef.NamePos == 'Bottom' and (BoxY + BoxH + 2) or (BoxY - 18))
    PreviewName.TextColor3 = ESPRef.NameColor

    -- vida (pulsa só pra demonstrar)
    PreviewHealthBg.Visible = ESPRef.Health
    local hp = math.clamp(0.6 + 0.4 * math.sin(os.clock() * 1.5), 0.2, 1)
    PreviewHealthFg.Size = UDim2.fromOffset(4, BoxH * hp)
    PreviewHealthFg.Position = UDim2.fromOffset(0, BoxH * (1 - hp))
    PreviewHealthFg.BackgroundColor3 = Color3.fromRGB(255 * (1 - hp), 255 * hp, 0)

    -- tracer
    PreviewTracer.Visible = ESPRef.Tracer
    PreviewTracer.BackgroundColor3 = ESPRef.TracerColor
end)

-- liga o preview só quando a aba Visuals está aberta
local VisualsTab = Tabs.Visuals
local oldShowVisuals, oldHideVisuals = VisualsTab.ShowTab, VisualsTab.HideTab

VisualsTab.ShowTab = function(self, ...)
    oldShowVisuals(self, ...)
    visualsActive = true
end

VisualsTab.HideTab = function(self, ...)
    oldHideVisuals(self, ...)
    visualsActive = false
end

Library.KeybindFrame.Visible = true

local AccentConn

Library:OnUnload(function()
    WatermarkConnection:Disconnect()

    for _, c in ipairs(ESPConnections) do
        c:Disconnect()
    end
    for plr in pairs(ESPObjects) do
        removeESP(plr)
    end
    for plr in pairs(Highlights) do
        destroyHighlight(plr)
    end
    for plr in pairs(PartCache) do
        restoreParts(plr)
    end
    MOOZE.Lock = false
    MOOZE.ShowFOV = false
    if FOVCircle then
        pcall(function() FOVCircle:Remove() end)
    end
    if CachedAimPart then
        pcall(function() CachedAimPart:Destroy() end)
    end
    if ColorCorrection then
        pcall(function() ColorCorrection:Destroy() end)
    end
    RunService:UnbindFromRenderStep('SpreadCamlock')
    RunService:UnbindFromRenderStep('SpreadWalkSpeed')
    RunService:UnbindFromRenderStep('SpreadJumpPower')
    if AimCircle then
        pcall(function() AimCircle:Remove() end)
    end

    HITBOX.Enabled = false
    for _, plr in ipairs(Players:GetPlayers()) do
        applyHitbox(plr)
    end

    for i = #ImpactTexts, 1, -1 do
        pcall(function() ImpactTexts[i].Drawing:Remove() end)
        ImpactTexts[i] = nil
    end
    PreviewConn:Disconnect()
    pcall(function() PreviewFrame:Destroy() end)
    FLY.Enabled = false
    local _, unloadHum = getCharAndHum()
    if unloadHum then unloadHum.PlatformStand = false end
    WORLD.FogEnabled = false
    WORLD.AtmosphereEnabled = false
    WORLD.AmbientEnabled = false
    WORLD.ClockEnabled = false
    WORLD.BloomEnabled = false
    WORLD.SunRaysEnabled = false
    applyWorld()
    BT.Enabled = false
    for plr in pairs(BTGhost) do btDestroyGhost(plr) end
    AccentConn:Disconnect()
    NOSLOW.Enabled = false
    if noSlowConn then noSlowConn:Disconnect() end
    pcall(function() RunService:UnbindFromRenderStep('SpreadNoSlow') end)

    print('Unloaded!')
    Library.Unloaded = true
end)

local MenuGroup = Tabs['UI Settings']:AddLeftGroupbox('Menu')

MenuGroup:AddButton('Unload', function() Library:Unload() end)
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default = 'End', NoUI = true, Text = 'Menu keybind' })

local KEYFILE = 'MyScriptHub/menukeybind.json'
local HttpService = game:GetService('HttpService')

-- carrega a keybind salva (depois que o menu já foi criado)
pcall(function()
    if isfile(KEYFILE) then
        local d = HttpService:JSONDecode(readfile(KEYFILE))
        Options.MenuKeybind:SetValue({ d.Key, d.Mode })
    end
end)

-- salva sempre que a tecla mudar (registra depois do load, senão sobrescreve o arquivo)
Options.MenuKeybind:OnChanged(function(v)
    pcall(function()
        makefolder('MyScriptHub')
        writefile(KEYFILE, HttpService:JSONEncode({ Key = v, Mode = Options.MenuKeybind.Mode }))
    end)
end)
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })

ThemeManager:SetFolder('Spread')
SaveManager:SetFolder('Spread/specific-game')

SaveManager:BuildConfigSection(Tabs['UI Settings'])
ThemeManager:ApplyToTab(Tabs['UI Settings'])

SaveManager:LoadAutoloadConfig()

-- accent rosa pulsando entre tons de rosa
local pinks = {
    Color3.fromRGB(255, 105, 180),
    Color3.fromRGB(255, 182, 193),
    Color3.fromRGB(255, 20, 147),
    Color3.fromRGB(255, 105, 180),
}
local function pinkAt(t)
    local n = #pinks - 1
    local f = (t % 1) * n
    local i = math.floor(f)
    return pinks[i + 1]:Lerp(pinks[i + 2], f - i)
end


local accentLast = 0
Options.AccentColor:SetGradient(true)
AccentConn = RunService.RenderStepped:Connect(function()
    if not (Options.AccentColor and Options.AccentColor.Gradient) then return end
    local now = os.clock()
    if now - accentLast < 0.05 then return end
    accentLast = now
    local c = pinkAt(now * 0.1)
    Library.AccentColor = c
    Library.AccentColorDark = Library:GetDarkerColor(c)
    Library:UpdateColorsUsingRegistry()
    if Options.AccentColor then
        Options.AccentColor:SetValueRGB(c)
    end
end)
