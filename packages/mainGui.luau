--!strict
-- HubLib v2.0 — smooth, lightweight, no deps
-- Fitur utama:
--  ✔ SetTitle/SetSubtitle/SetIcon (URL) runtime
--  ✔ Multi-tab + selector halus
--  ✔ Minimize / Hide (toggle visibility) / Kill (Destroy)
--  ✔ Background opacity (alpha) + Theme live update
--  ✔ Notification stack (toast) + opsi jenis (info/success/warn/error)
--  ✔ Loading overlay (ShowLoader/HideLoader) dengan spinner
--  ✔ Config persistence (writefile/readfile jika tersedia)
--  ✔ Keybind toggle minimize bisa diubah runtime
--  ✔ Drag halus
--
-- Contoh penggunaan:
-- local HubLib = loadstring(game:HttpGet("..."))()
-- local ui = HubLib:CreateWindow({
--   title="My Hub", subtitle="v2.0",
--   icon="rbxassetid://7734068321", -- atau URL http(s) kalau environment mendukung
--   theme={bg=Color3.fromRGB(18,18,20), accent=Color3.fromRGB(0,170,255)},
--   opacity=0.06,                 -- 0..1 overlay blur/alpha pada background panel
--   minimize_key=Enum.KeyCode.RightControl,
--   autobuild_misc=true,          -- auto buat tab Misc (opacity & keybind)
--   config_file="hublib_config_v2.json"
-- })
-- local tab = ui:AddTab("General", "rbxassetid://3926305904") -- (opsional) icon
-- local sec = tab:AddSection("Actions")
-- sec:AddButton("Ping", function() ui:Notify("PONG!", 2, "success") end)
-- sec:AddToggle("God Mode", false, function(v) print("toggle", v) end)
-- sec:AddSlider("Speed", {min=0,max=100,default=50,step=1}, function(v) end)
-- ui:ShowLoader("Loading assets...")
-- task.wait(1.5) ui:HideLoader()
-- ui:Notify("Loaded!", 3)
--
-- Tombol window:
--  [_] Minimize, [👁] Hide/Show (via API juga), [✕] Kill/Destroy

local HubLib = {}
HubLib.__index = HubLib

-- services
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- CoreGui vs PlayerGui
local function getGuiParent()
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then return core end
    return Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- tiny Signal
local function Signal()
    local bindable = Instance.new("BindableEvent")
    local s = {}
    function s:Connect(fn) return bindable.Event:Connect(fn) end
    function s:Fire(...) bindable:Fire(...) end
    function s:Destroy() bindable:Destroy() end
    return s
end

-- utils
local function twn(i, ti, props, es, ed)
    return TweenService:Create(i, TweenInfo.new(ti or 0.2, es or Enum.EasingStyle.Quad, ed or Enum.EasingDirection.Out), props)
end
local function mk(class, props, parent)
    local inst = Instance.new(class)
    for k,v in pairs(props or {}) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end
local function round(n, step) step = step or 1; return math.floor(n/step + 0.5)*step end

-- config file io
local File = {}
function File.write(name, tbl)
    if writefile then
        local ok, s = pcall(function() return HttpService:JSONEncode(tbl) end)
        if ok then pcall(function() writefile(name, s) end); return true end
    end
    return false
end
function File.read(name)
    if readfile then
        local ok, s = pcall(function() return readfile(name) end)
        if ok and s then
            local jok, j = pcall(function() return HttpService:JSONDecode(s) end)
            if jok then return j end
        end
    end
    return nil
end

-- Theme defaults
local DEFAULT_THEME = {
    bg     = Color3.fromRGB(18, 18, 20),
    panel  = Color3.fromRGB(26, 26, 30),
    stroke = Color3.fromRGB(50, 50, 58),
    accent = Color3.fromRGB(0, 170, 255),
    text   = Color3.fromRGB(235, 235, 235),
    muted  = Color3.fromRGB(160, 160, 170),
}

-- Toast preset colors
local TOAST = {
    info    = Color3.fromRGB(0,170,255),
    success = Color3.fromRGB(80,200,120),
    warn    = Color3.fromRGB(255,170,0),
    error   = Color3.fromRGB(255,75,75),
}

-- Spinner (loading)
local function makeSpinner(parent, color)
    local sp = mk("ImageLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(28,28),
        Image = "rbxassetid://8131946445", -- simple circle
        ImageColor3 = color,
    }, parent)
    -- rotate forever
    task.spawn(function()
        while sp.Parent do
            local tw = twn(sp, 0.9, {Rotation = sp.Rotation + 360}, Enum.EasingStyle.Linear)
            tw:Play(); tw.Completed:Wait()
        end
    end)
    return sp
end

-- ========= WINDOW =========
function HubLib:CreateWindow(opt)
    opt = opt or {}

    -- theme merge
    local theme = {}
    for k,v in pairs(DEFAULT_THEME) do theme[k] = (opt.theme and opt.theme[k]) or v end
    local opacity = tonumber(opt.opacity or 0.06) -- applied to panel as BackgroundTransparency

    local title = opt.title or "Hub"
    local subtitle = opt.subtitle or ""
    local iconUrl = opt.icon -- optional

    -- ScreenGui root
    local gui = mk("ScreenGui", {
        Name = "HubLibUI",
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
    }, getGuiParent())

    -- Toast root (top-right)
    local notifyRoot = mk("Frame", {
        Name = "NotifyRoot",
        AnchorPoint = Vector2.new(1,0),
        Position = UDim2.new(1,-16,0,16),
        Size = UDim2.new(0, 320, 1, -32),
        BackgroundTransparency = 1,
    }, gui)
    local notifyList = mk("UIListLayout", {
        Padding = UDim.new(0,8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Top,
    }, notifyRoot)

    -- Loading overlay (hidden by default)
    local overlay = mk("Frame", {
        Name = "LoaderOverlay",
        BackgroundColor3 = Color3.new(0,0,0),
        BackgroundTransparency = 0.35,
        Visible = false,
        Size = UDim2.fromScale(1,1),
    }, gui)
    local olCenter = mk("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(260, 90),
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.fromScale(0.5,0.5),
    }, overlay)
    local olCard = mk("Frame", {
        BackgroundColor3 = theme.panel,
        Size = UDim2.fromOffset(260, 90),
    }, olCenter)
    mk("UICorner", {CornerRadius = UDim.new(0,12)}, olCard)
    mk("UIStroke", {Color = theme.stroke, Thickness = 1, Transparency = 0.2}, olCard)
    local olSpinner = makeSpinner(olCard, theme.accent)
    olSpinner.Position = UDim2.fromOffset(16, 31)
    local olText = mk("TextLabel", {
        BackgroundTransparency = 1,
        Text = "Loading...",
        Font = Enum.Font.GothamMedium,
        TextColor3 = theme.text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(56, 18),
        Size = UDim2.fromOffset(190, 54),
    }, olCard)

    -- Main window
    local main = mk("Frame", {
        Name = "Main",
        BackgroundColor3 = theme.bg,
        BackgroundTransparency = 0, -- base
        Size = UDim2.fromOffset(620, 400),
        Position = UDim2.new(0, 40, 0, 60),
        ClipsDescendants = true,
        Active = true,
        Draggable = false, -- manual smooth drag
    }, gui)
    mk("UICorner", {CornerRadius = UDim.new(0,14)}, main)
    mk("UIStroke", {Color = theme.stroke, Thickness = 1, Transparency = 0.2}, main)

    -- Top bar
    local top = mk("Frame", {
        Name = "TopBar",
        BackgroundColor3 = theme.panel,
        BackgroundTransparency = opacity,
        Size = UDim2.new(1,0,0,44),
    }, main)
    mk("UICorner", {CornerRadius = UDim.new(0,14)}, top)
    mk("UIStroke", {Color = theme.stroke, Thickness = 1, Transparency = 0.3}, top)

    -- Icon (optional)
    local iconImg = mk("ImageLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(22,22),
        Position = UDim2.fromOffset(14,11),
        Image = iconUrl or "",
        ImageTransparency = 0,
    }, top)

    -- Title/Subtitle
    local titleLbl = mk("TextLabel", {
        BackgroundTransparency = 1,
        Text = title,
        Font = Enum.Font.GothamBold,
        TextColor3 = theme.text,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(iconUrl and 44 or 16, 2),
        Size = UDim2.new(1,-160,0,22),
    }, top)
    local subLbl = mk("TextLabel", {
        BackgroundTransparency = 1,
        Text = subtitle,
        Font = Enum.Font.Gotham,
        TextColor3 = theme.muted,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(iconUrl and 44 or 16, 22),
        Size = UDim2.new(1,-160,0,20),
    }, top)

    -- Window controls: Minimize [_], Hide [👁], Kill [✕]
    local btnMin = mk("TextButton", {
        Text = "–",
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        TextColor3 = theme.text,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(38, 40),
        Position = UDim2.new(1,-118,0,2),
        AutoButtonColor = false,
    }, top)
    local btnHide = mk("TextButton", {
        Text = "👁",
        Font = Enum.Font.Gotham,
        TextSize = 16,
        TextColor3 = theme.text,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(38, 40),
        Position = UDim2.new(1,-80,0,2),
        AutoButtonColor = false,
    }, top)
    local btnKill = mk("TextButton", {
        Text = "✕",
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        TextColor3 = Color3.fromRGB(255,90,90),
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(38, 40),
        Position = UDim2.new(1,-42,0,2),
        AutoButtonColor = false,
    }, top)

    -- Body
    local body = mk("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0,0,0,50),
        Size = UDim2.new(1,0,1,-54),
    }, main)

    local tabs = mk("Frame", {
        Name = "Tabs",
        BackgroundColor3 = theme.panel,
        BackgroundTransparency = opacity,
        Size = UDim2.new(0, 160, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
    }, body)
    mk("UICorner", {CornerRadius = UDim.new(0,10)}, tabs)
    mk("UIStroke", {Color=theme.stroke, Thickness=1, Transparency=0.3}, tabs)
    local tabsList = mk("UIListLayout", {Padding = UDim.new(0,8), SortOrder = Enum.SortOrder.LayoutOrder}, tabs)
    mk("UIPadding", {PaddingTop=UDim.new(0,10), PaddingLeft=UDim.new(0,10), PaddingRight=UDim.new(0,10), PaddingBottom=UDim.new(0,10)}, tabs)

    local content = mk("Frame", {
        Name = "Content",
        BackgroundColor3 = theme.panel,
        BackgroundTransparency = opacity,
        Size = UDim2.new(1, -(160 + 24), 1, 0),
        Position = UDim2.new(0, 160 + 24, 0, 0),
        ClipsDescendants = true,
    }, body)
    mk("UICorner", {CornerRadius=UDim.new(0,10)}, content)
    mk("UIStroke", {Color=theme.stroke, Thickness=1, Transparency=0.3}, content)

    -- Drag smooth
    do
        local dragging = false
        local dragStart, startPos
        top.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = i.Position
                startPos = main.Position
            end
        end)
        top.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
        UserInputService.InputChanged:Connect(function(i)
            if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
                local d = i.Position - dragStart
                twn(main, 0.05, {Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)}):Play()
            end
        end)
    end

    -- Minimize / Hide / Kill
    local minimized = false
    local storedSize = main.Size
    btnMin.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            twn(main, 0.18, {Size = UDim2.fromOffset(main.Size.X.Offset, 46)}):Play()
        else
            twn(main, 0.18, {Size = storedSize}):Play()
        end
    end)
    btnHide.MouseButton1Click:Connect(function()
        main.Visible = not main.Visible
    end)
    btnKill.MouseButton1Click:Connect(function()
        gui:Destroy()
    end)

    -- Pages
    local pages : {[Instance]: Frame} = {}
    local currentPage : Frame? = nil

    -- window object
    local window = setmetatable({
        _gui = gui,
        _main = main,
        _top = top,
        _tabs = tabs,
        _content = content,
        _pages = pages,
        _theme = theme,
        _opacity = opacity,
        _notifyRoot = notifyRoot,
        _overlay = overlay,
        _overlayText = olText,
        _icon = iconImg,
        _titleLbl = titleLbl,
        _subLbl = subLbl,
        _config = { values = {} },
        _configFile = opt.config_file or "hublib_config_v2.json",
        _toggleKey = opt.minimize_key or Enum.KeyCode.RightControl,
    }, HubLib)

    -- load config (best-effort)
    do
        local loaded = File.read(window._configFile)
        if loaded and type(loaded) == "table" and type(loaded.values) == "table" then
            window._config = loaded
        end
    end

    -- API: SaveConfig
    function window:SaveConfig()
        File.write(self._configFile, self._config)
    end

    -- API: Theme/Opacity update
    function window:SetOpacity(a : number)
        self._opacity = math.clamp(a, 0, 1)
        twn(self._top, 0.12, {BackgroundTransparency = self._opacity}):Play()
        twn(self._tabs,0.12,{BackgroundTransparency = self._opacity}):Play()
        twn(self._content,0.12,{BackgroundTransparency = self._opacity}):Play()
    end
    function window:SetTheme(newTheme : {[string]: any})
        for k,v in pairs(newTheme or {}) do
            if self._theme[k] ~= nil then self._theme[k] = v end
        end
        -- re-apply some surfaces
        self._top.BackgroundColor3 = self._theme.panel
        self._tabs.BackgroundColor3 = self._theme.panel
        self._content.BackgroundColor3 = self._theme.panel
        self._main.BackgroundColor3 = self._theme.bg
        self._titleLbl.TextColor3 = self._theme.text
        self._subLbl.TextColor3 = self._theme.muted
    end

    -- API: Title/Subtitle/Icon
    function window:SetTitle(t : string) self._titleLbl.Text = t or "" end
    function window:SetSubtitle(s : string) self._subLbl.Text = s or "" end
    function window:SetIcon(url : string?)
        self._icon.Image = url or ""
        self._icon.Visible = (url ~= nil and url ~= "")
        -- adjust title padding
        self._titleLbl.Position = UDim2.fromOffset(self._icon.Visible and 44 or 16, 2)
        self._subLbl.Position  = UDim2.fromOffset(self._icon.Visible and 44 or 16, 22)
    end
    if iconUrl then window:SetIcon(iconUrl) end

    -- API: Show/Hide/Destroy programmatically
    function window:Show() self._main.Visible = true end
    function window:Hide() self._main.Visible = false end
    function window:Destroy() self._gui:Destroy() end

    -- API: Change toggle key (minimize key)
    function window:SetMinimizeKey(kc : Enum.KeyCode)
        self._toggleKey = kc
    end

    -- API: Loader overlay
    function window:ShowLoader(text : string?)
        self._overlay.Visible = true
        self._overlayText.Text = text or "Loading..."
        twn(self._overlay, 0.15, {BackgroundTransparency = 0.35}):Play()
    end
    function window:HideLoader()
        local tw = twn(self._overlay, 0.15, {BackgroundTransparency = 1})
        tw.Completed:Connect(function() self._overlay.Visible = false; self._overlay.BackgroundTransparency = 0.35 end)
        tw:Play()
    end

    -- API: Notification
    function window:Notify(text : string, duration : number?, kind : "info"|"success"|"warn"|"error"?)
        duration = duration or 2
        kind = kind or "info"
        local accent = TOAST[kind] or self._theme.accent

        local card = mk("Frame", {
            BackgroundColor3 = self._theme.panel,
            BackgroundTransparency = self._opacity,
            Size = UDim2.fromOffset(0, 38),
        }, self._notifyRoot)
        mk("UICorner", {CornerRadius = UDim.new(0,8)}, card)
        mk("UIStroke", {Color=self._theme.stroke, Thickness=1, Transparency=0.2}, card)

        local bar = mk("Frame", {
            BackgroundColor3 = accent,
            Size = UDim2.new(0, 4, 1, 0),
        }, card)
        mk("UICorner", {CornerRadius = UDim.new(0,8)}, bar)

        local lbl = mk("TextLabel", {
            BackgroundTransparency = 1,
            Text = text,
            Font = Enum.Font.GothamMedium,
            TextColor3 = self._theme.text,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.fromOffset(10,0),
            Size = UDim2.new(1,-16,1,0),
        }, card)

        twn(card, 0.2, {Size = UDim2.fromOffset(300,38)}):Play()
        task.delay(duration, function()
            local tw = twn(card, 0.18, {Size = UDim2.fromOffset(0,38)})
            tw.Completed:Connect(function() card:Destroy() end)
            tw:Play()
        end)
    end

    -- Tabs API
    function window:AddTab(name : string, icon : string?)
        -- button
        local btn = mk("TextButton", {
            AutoButtonColor = false,
            Text = "",
            BackgroundColor3 = self._theme.bg,
            BackgroundTransparency = 0,
            Size = UDim2.new(1, -0, 0, 36),
        }, self._tabs)
        mk("UICorner", {CornerRadius=UDim.new(0,8)}, btn)

        local row = mk("Frame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -8, 1, 0),
            Position = UDim2.fromOffset(4,0),
        }, btn)
        local il = mk("ImageLabel", {
            BackgroundTransparency = 1,
            Image = icon or "",
            Size = UDim2.fromOffset(18,18),
            Position = UDim2.fromOffset(10,9),
            ImageTransparency = icon and 0 or 1,
        }, row)
        local txt = mk("TextLabel", {
            BackgroundTransparency = 1,
            Text = name,
            Font = Enum.Font.GothamMedium,
            TextSize = 14,
            TextColor3 = self._theme.text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.fromOffset(icon and 34 or 12, 0),
            Size = UDim2.new(1, -(icon and 40 or 16), 1, 0),
        }, row)

        -- page
        local page = mk("ScrollingFrame", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1,-16,1,-16),
            Position = UDim2.fromOffset(8,8),
            ScrollBarThickness = 4,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            CanvasSize = UDim2.new(0,0,0,0),
            Visible = false,
        }, self._content)
        local list = mk("UIListLayout", {Padding = UDim.new(0,10), SortOrder = Enum.SortOrder.LayoutOrder}, page)
        mk("UIPadding", {PaddingTop=UDim.new(0,8), PaddingLeft=UDim.new(0,8), PaddingRight=UDim.new(0,8), PaddingBottom=UDim.new(0,8)}, page)

        self._pages[btn] = page

        local function select()
            for b, p in pairs(self._pages) do
                local sel = (b == btn)
                p.Visible = sel
                twn(b, 0.12, {BackgroundColor3 = sel and self._theme.accent or self._theme.bg}):Play()
                twn(txt,0.12, {TextColor3 = sel and Color3.new(1,1,1) or self._theme.text}):Play()
                twn(il, 0.12, {ImageColor3 = sel and Color3.new(1,1,1) or self._theme.text, ImageTransparency = (icon and 0 or 1)}):Play()
            end
            currentPage = page
        end

        btn.MouseButton1Click:Connect(select)
        if not currentPage then select() end

        -- tab object
        local tabObj = {}
        function tabObj:AddSection(titleText : string)
            local section = mk("Frame", {
                BackgroundColor3 = window._theme.bg,
                BackgroundTransparency = window._opacity,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
            }, page)
            mk("UICorner", {CornerRadius=UDim.new(0,10)}, section)
            mk("UIStroke", {Color=window._theme.stroke, Thickness=1, Transparency=0.2}, section)
            mk("UIPadding", {PaddingTop=UDim.new(0,10), PaddingBottom=UDim.new(0,10), PaddingLeft=UDim.new(0,10), PaddingRight=UDim.new(0,10)}, section)
            local vlist = mk("UIListLayout", {Padding=UDim.new(0,8), SortOrder=Enum.SortOrder.LayoutOrder}, section)

            local title = mk("TextLabel", {
                BackgroundTransparency = 1,
                Text = titleText,
                Font = Enum.Font.GothamBold,
                TextColor3 = window._theme.text,
                TextSize = 14,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(1,0,0,18),
            }, section)

            local secObj = {}

            function secObj:AddButton(text : string, callback)
                local b = mk("TextButton", {
                    Text = text,
                    Font = Enum.Font.GothamMedium,
                    TextSize = 14,
                    TextColor3 = Color3.new(1,1,1),
                    BackgroundColor3 = window._theme.accent,
                    AutoButtonColor = false,
                    Size = UDim2.new(1,0,0,34),
                }, section)
                mk("UICorner", {CornerRadius=UDim.new(0,8)}, b)
                b.MouseButton1Click:Connect(function()
                    twn(b, 0.05, {BackgroundTransparency = 0.15}):Play()
                    task.wait(0.07)
                    twn(b, 0.12, {BackgroundTransparency = 0}):Play()
                    if callback then task.spawn(callback) end
                end)
                return b
            end

            function secObj:AddToggle(text : string, defaultVal : boolean?, callback)
                local key = ("toggle:%s"):format(text)
                local val = (window._config.values[key] ~= nil) and window._config.values[key] or (defaultVal == true)

                local holder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,28)}, section)
                local lbl = mk("TextLabel", {
                    BackgroundTransparency=1, Text=text, Font=Enum.Font.Gotham,
                    TextColor3=window._theme.text, TextSize=13, TextXAlignment=Enum.TextXAlignment.Left,
                    Size=UDim2.new(1,-46,1,0),
                }, holder)
                local box = mk("TextButton", {
                    Text="", AutoButtonColor=false,
                    BackgroundColor3 = val and window._theme.accent or window._theme.panel,
                    Size = UDim2.fromOffset(36,20),
                    Position = UDim2.new(1,-36,0.5,-10),
                }, holder)
                mk("UICorner",{CornerRadius=UDim.new(1,999)}, box)
                local knob = mk("Frame", {
                    BackgroundColor3 = Color3.new(1,1,1),
                    Size = UDim2.fromOffset(16,16),
                    Position = val and UDim2.fromOffset(18,2) or UDim2.fromOffset(2,2),
                }, box)
                mk("UICorner",{CornerRadius=UDim.new(1,999)}, knob)

                local sig = Signal()
                local function set(v:boolean)
                    val = v
                    window._config.values[key] = v
                    window:SaveConfig()
                    twn(box,0.12,{BackgroundColor3 = v and window._theme.accent or window._theme.panel}):Play()
                    twn(knob,0.12,{Position = v and UDim2.fromOffset(18,2) or UDim2.fromOffset(2,2)}):Play()
                    if callback then task.spawn(callback, v) end
                    sig:Fire(v)
                end
                box.MouseButton1Click:Connect(function() set(not val) end)
                return { Set=set, Get=function() return val end, OnChanged=function(_,fn) return sig:Connect(fn) end }
            end

            function secObj:AddSlider(text : string, conf, callback)
                conf = conf or {min=0,max=100,default=0,step=1}
                local key = ("slider:%s"):format(text)
                local val = (window._config.values[key] ~= nil) and window._config.values[key] or (conf.default or conf.min or 0)

                local holder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,42)}, section)
                local lbl = mk("TextLabel", {
                    BackgroundTransparency=1, Text=string.format("%s: %s", text, tostring(val)),
                    Font=Enum.Font.Gotham, TextColor3=window._theme.text, TextSize=13,
                    TextXAlignment=Enum.TextXAlignment.Left, Size=UDim2.new(1,0,0,18),
                }, holder)
                local bar = mk("Frame", {
                    BackgroundColor3=window._theme.panel, Size=UDim2.new(1,0,0,6), Position=UDim2.new(0,0,0,24),
                }, holder)
                mk("UICorner",{CornerRadius=UDim.new(1,999)}, bar)
                mk("UIStroke",{Color=window._theme.stroke, Thickness=1, Transparency=0.4}, bar)
                local fill = mk("Frame", {
                    BackgroundColor3=window._theme.accent,
                    Size=UDim2.new((val-conf.min)/(conf.max-conf.min),0,1,0),
                }, bar)
                mk("UICorner",{CornerRadius=UDim.new(1,999)}, fill)

                local dragging=false
                local sig = Signal()
                local function apply(x:number)
                    local a = math.clamp(x,0,1)
                    local raw = conf.min + a*(conf.max-conf.min)
                    local stepped = round(raw, conf.step or 1)
                    val = math.clamp(stepped, conf.min, conf.max)
                    window._config.values[key] = val; window:SaveConfig()
                    lbl.Text = string.format("%s: %s", text, tostring(val))
                    twn(fill,0.05,{Size=UDim2.new((val-conf.min)/(conf.max-conf.min),0,1,0)}):Play()
                    if callback then task.spawn(callback, val) end
                    sig:Fire(val)
                end
                bar.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then
                        dragging=true
                        local rel=(i.Position.X - bar.AbsolutePosition.X)/bar.AbsoluteSize.X
                        apply(rel)
                    end
                end)
                UserInputService.InputEnded:Connect(function(i)
                    if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
                end)
                UserInputService.InputChanged:Connect(function(i)
                    if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
                        local rel=(i.Position.X - bar.AbsolutePosition.X)/bar.AbsoluteSize.X
                        apply(rel)
                    end
                end)
                return {
                    Set=function(_,v:number) apply((v-conf.min)/(conf.max-conf.min)) end,
                    Get=function() return val end,
                    OnChanged=function(_,fn) return sig:Connect(fn) end
                }
            end

            function secObj:AddDropdown(text : string, list : {string}, defaultIndex : number?, callback)
                local idx = defaultIndex or 1
                idx = math.clamp(idx, 1, math.max(1, #list))
                local key = ("dropdown:%s"):format(text)
                if window._config.values[key] ~= nil then
                    local saved = window._config.values[key]
                    for i,v in ipairs(list) do if v==saved then idx=i break end end
                end
                local current = list[idx] or ""

                local holder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,32)}, section)
                local btn = mk("TextButton", {
                    Text = string.format("%s: %s", text, current),
                    Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = window._theme.text,
                    AutoButtonColor=false, BackgroundColor3=window._theme.panel,
                    Size=UDim2.new(1,0,1,0), TextXAlignment=Enum.TextXAlignment.Left,
                }, holder)
                mk("UICorner",{CornerRadius=UDim.new(0,8)}, btn)
                mk("UIStroke",{Color=window._theme.stroke, Thickness=1, Transparency=0.3}, btn)

                local open=false
                local listFrame = mk("Frame", {
                    BackgroundColor3 = window._theme.bg,
                    BackgroundTransparency = window._opacity,
                    Size = UDim2.new(1,0,0,0),
                    Position = UDim2.new(0,0,0,36),
                    Visible = false,
                }, holder)
                mk("UICorner",{CornerRadius=UDim.new(0,8)}, listFrame)
                mk("UIStroke",{Color=window._theme.stroke, Thickness=1, Transparency=0.2}, listFrame)
                local lay = mk("UIListLayout",{Padding=UDim.new(0,6)}, listFrame)
                mk("UIPadding",{PaddingTop=UDim.new(0,6),PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6),PaddingBottom=UDim.new(0,6)}, listFrame)

                local function rebuild()
                    for _,c in ipairs(listFrame:GetChildren()) do
                        if c:IsA("TextButton") then c:Destroy() end
                    end
                    for i,val in ipairs(list) do
                        local it = mk("TextButton", {
                            Text = val, Font=Enum.Font.Gotham, TextSize=12, TextColor3=window._theme.text,
                            AutoButtonColor=false, BackgroundColor3=window._theme.panel,
                            Size=UDim2.new(1,0,0,20),
                        }, listFrame)
                        mk("UICorner",{CornerRadius=UDim.new(0,6)}, it)
                        it.MouseButton1Click:Connect(function()
                            idx = i; current = list[idx]
                            window._config.values[key] = current; window:SaveConfig()
                            btn.Text = string.format("%s: %s", text, current)
                            local tw = twn(listFrame,0.12,{Size=UDim2.new(1,0,0,0)})
                            tw.Completed:Connect(function() listFrame.Visible=false end); tw:Play()
                            open=false
                            if callback then task.spawn(callback, current) end
                        end)
                    end
                end
                rebuild()

                btn.MouseButton1Click:Connect(function()
                    open = not open
                    if open then
                        listFrame.Visible = true
                        twn(listFrame,0.12,{Size=UDim2.new(1,0,0, math.min(6,#list)*26)}):Play()
                    else
                        local tw = twn(listFrame,0.12,{Size=UDim2.new(1,0,0,0)})
                        tw.Completed:Connect(function() listFrame.Visible=false end); tw:Play()
                    end
                end)

                return {
                    Get=function() return current end,
                    Set=function(_, v:string)
                        for i,val in ipairs(list) do if val==v then idx=i; current=v; btn.Text=string.format("%s: %s", text, current); break end end
                    end,
                    SetItems=function(_, newList:{string})
                        list = newList or {}
                        if idx>#list then idx=#list end
                        rebuild()
                    end
                }
            end

            function secObj:AddTextbox(text : string, placeholder : string?, callback)
                local holder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,32)}, section)
                local lbl = mk("TextLabel", {
                    BackgroundTransparency=1, Text=text, Font=Enum.Font.Gotham,
                    TextColor3=window._theme.text, TextSize=13, TextXAlignment=Enum.TextXAlignment.Left,
                    Size=UDim2.new(0.35,0,1,0),
                }, holder)
                local box = mk("TextBox", {
                    PlaceholderText=placeholder or "", Text="", Font=Enum.Font.Gotham,
                    TextColor3=window._theme.text, TextSize=13, BackgroundColor3=window._theme.panel,
                    Size=UDim2.new(0.65,-6,1,0), Position=UDim2.new(0.35,6,0,0), ClearTextOnFocus=false,
                }, holder)
                mk("UICorner",{CornerRadius=UDim.new(0,8)}, box)
                mk("UIStroke",{Color=window._theme.stroke, Thickness=1, Transparency=0.3}, box)
                box.FocusLost:Connect(function(enter) if callback then task.spawn(callback, box.Text, enter) end end)
                return box
            end

            function secObj:AddKeybind(text : string, defaultKey : Enum.KeyCode?, callback)
                local key = defaultKey or Enum.KeyCode.K
                local holder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,28)}, section)
                local lbl = mk("TextLabel", {
                    BackgroundTransparency=1, Text=string.format("%s: %s", text, key.Name),
                    Font=Enum.Font.Gotham, TextColor3=window._theme.text, TextSize=13,
                    TextXAlignment=Enum.TextXAlignment.Left, Size=UDim2.new(1,0,1,0),
                }, holder)

                local listening=false
                holder.InputBegan:Connect(function(i)
                    if i.UserInputType==Enum.UserInputType.MouseButton1 then listening=true; lbl.Text = text..": [press key]" end
                end)
                UserInputService.InputBegan:Connect(function(i,gp)
                    if gp then return end
                    if listening and i.KeyCode ~= Enum.KeyCode.Unknown then
                        key = i.KeyCode; listening=false; lbl.Text = string.format("%s: %s", text, key.Name)
                    elseif i.KeyCode == key then if callback then task.spawn(callback) end end
                end)
                return { Get=function() return key end, Set=function(_,kc) key=kc; lbl.Text=string.format("%s: %s", text, key.Name) end }
            end

            return secObj
        end

        return tabObj
    end

    -- Global hotkey: toggle visible (Hide/Show)
    UserInputService.InputBegan:Connect(function(i,gp)
        if gp then return end
        if i.KeyCode == window._toggleKey then
            window._main.Visible = not window._main.Visible
        end
    end)

    -- Optional: auto build Misc tab (opacity & keybind)
    if opt.autobuild_misc then
        local misc = window:AddTab("Misc", "rbxassetid://3926305904") -- gear icon (example)
        local s = misc:AddSection("Appearance")
        s:AddSlider("Background Opacity", {min=0,max=1,default=opacity,step=0.01}, function(v) window:SetOpacity(v) end)
        local s2 = misc:AddSection("Hotkey")
        s2:AddKeybind("Toggle Key", window._toggleKey, function() end)
        local s3 = misc:AddSection("Window")
        s3:AddButton("Hide/Show", function() window[window._main.Visible and "Hide" or "Show"](window) end)
        s3:AddButton("Minimize", function() btnMin:Activate() end)
        s3:AddButton("Kill (Destroy)", function() window:Destroy() end)
    end

    return window
end

return HubLib
