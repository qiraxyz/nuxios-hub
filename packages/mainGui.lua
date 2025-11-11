--!strict
-- HubLib v1.0 — smooth, lightweight, no deps
-- API ringkas:
-- local ui = HubLib:CreateWindow({title="My Hub", subtitle="v1.0", theme={bg=Color3..., accent=Color3...}})
-- local tab = ui:AddTab("Main")
-- local sec = tab:AddSection("Actions")
-- sec:AddButton("Do Something", function() print("clicked") end)
-- local t = sec:AddToggle("God Mode", false, function(v) print("toggle:", v) end)
-- local s = sec:AddSlider("Speed", {min=0,max=100,default=50,step=1}, function(v) end)
-- ui:Notify("Loaded!", 3)

local HubLib = {}
HubLib.__index = HubLib

-- services
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- compatibility: CoreGui if exploit; otherwise StarterGui
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

-- util
local function twn(i, ti, props)
    return TweenService:Create(i, TweenInfo.new(ti or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
end

local function mk(class, props, parent)
    local inst = Instance.new(class)
    for k,v in pairs(props or {}) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end

local function round(n, step)
    step = step or 1
    return math.floor(n/step + 0.5)*step
end

-- config storage (writefile/readfile jika ada)
local File = {}
function File.write(name, data)
    local ok = false
    if writefile then
        local s = game:GetService("HttpService"):JSONEncode(data)
        local suc = pcall(function() writefile(name, s) end)
        ok = suc and true or false
    end
    return ok
end
function File.read(name)
    if readfile then
        local suc, s = pcall(function() return readfile(name) end)
        if suc and s then
            local ok, json = pcall(function() return game:GetService("HttpService"):JSONDecode(s) end)
            if ok then return json end
        end
    end
    return nil
end

-- Theme defaults
local DEFAULT_THEME = {
    bg = Color3.fromRGB(18, 18, 20),
    panel = Color3.fromRGB(26, 26, 30),
    stroke = Color3.fromRGB(50, 50, 58),
    accent = Color3.fromRGB(0, 170, 255),
    text = Color3.fromRGB(235, 235, 235),
    muted = Color3.fromRGB(160, 160, 170),
}

-- ========= WINDOW =========
function HubLib:CreateWindow(opt)
    opt = opt or {}
    local theme = {}
    for k,v in pairs(DEFAULT_THEME) do theme[k] = (opt.theme and opt.theme[k]) or v end

    local title = opt.title or "Hub"
    local subtitle = opt.subtitle or ""

    -- ScreenGui
    local gui = mk("ScreenGui", {
        Name = "HubLibUI";
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling;
        ResetOnSpawn = false;
        IgnoreGuiInset = true;
    }, getGuiParent())

    -- notif root
    local notifyRoot = mk("Frame", {
        Name = "NotifyRoot";
        AnchorPoint = Vector2.new(1,0);
        Position = UDim2.new(1,-16,0,16);
        Size = UDim2.new(0, 320, 1, 0);
        BackgroundTransparency = 1;
    }, gui)

    -- main window
    local main = mk("Frame", {
        Name = "Main";
        BackgroundColor3 = theme.bg;
        Size = UDim2.fromOffset(560, 360);
        Position = UDim2.new(0, 40, 0, 60);
        ClipsDescendants = true;
        Active = true;
        Draggable = false; -- manual drag (smooth)
    }, gui)
    mk("UICorner", {CornerRadius = UDim.new(0,14)}, main)
    mk("UIStroke", {Color = theme.stroke, Thickness = 1, Transparency = 0.2}, main)

    -- top bar
    local top = mk("Frame", {
        Name = "TopBar";
        BackgroundColor3 = theme.panel;
        Size = UDim2.new(1,0,0,42);
    }, main)
    mk("UICorner", {CornerRadius = UDim.new(0,14)}, top)
    mk("UIStroke", {Color = theme.stroke, Thickness = 1, Transparency = 0.3}, top)

    local titleLbl = mk("TextLabel", {
        BackgroundTransparency = 1;
        Text = title;
        Font = Enum.Font.GothamBold;
        TextColor3 = theme.text;
        TextSize = 16;
        TextXAlignment = Enum.TextXAlignment.Left;
        Position = UDim2.fromOffset(16,0);
        Size = UDim2.new(1,-100,1,0);
    }, top)

    local subLbl = mk("TextLabel", {
        BackgroundTransparency = 1;
        Text = subtitle;
        Font = Enum.Font.Gotham;
        TextColor3 = theme.muted;
        TextSize = 12;
        TextXAlignment = Enum.TextXAlignment.Left;
        Position = UDim2.fromOffset(16,20);
        Size = UDim2.new(1,-100,0,18);
    }, top)

    -- minimize button
    local miniBtn = mk("TextButton", {
        Text = "–";
        Font = Enum.Font.GothamBold;
        TextSize = 18;
        TextColor3 = theme.text;
        BackgroundTransparency = 1;
        Size = UDim2.fromOffset(40, 40);
        Position = UDim2.new(1,-44,0,1);
    }, top)

    -- body layout: left tabs, right content
    local body = mk("Frame", {
        BackgroundTransparency = 1;
        Position = UDim2.new(0,0,0,48);
        Size = UDim2.new(1,0,1,-52);
    }, main)

    local tabs = mk("Frame", {
        Name = "Tabs";
        BackgroundColor3 = theme.panel;
        Size = UDim2.new(0, 140, 1, -0);
        Position = UDim2.new(0, 12, 0, 0);
    }, body)
    mk("UICorner", {CornerRadius = UDim.new(0,10)}, tabs)
    mk("UIStroke", {Color = theme.stroke, Thickness=1, Transparency=0.3}, tabs)

    local tabsList = mk("UIListLayout", {
        Padding = UDim.new(0,8);
        SortOrder = Enum.SortOrder.LayoutOrder;
    }, tabs)
    mk("UIPadding", {PaddingTop = UDim.new(0,10), PaddingLeft = UDim.new(0,10), PaddingRight = UDim.new(0,10)}, tabs)

    local content = mk("Frame", {
        Name = "Content";
        BackgroundColor3 = theme.panel;
        Size = UDim2.new(1, - (140 + 24), 1, 0);
        Position = UDim2.new(0, 140 + 24, 0, 0);
        ClipsDescendants = true;
    }, body)
    mk("UICorner", {CornerRadius = UDim.new(0,10)}, content)
    mk("UIStroke", {Color = theme.stroke, Thickness=1, Transparency=0.3}, content)

    local pages = {} -- { [tabBtn] = pageFrame }
    local currentPage: Frame? = nil

    -- drag logic
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
                local delta = i.Position - dragStart
                twn(main, 0.05, {Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)}):Play()
            end
        end)
    end

    -- minimize
    local minimized = false
    local storedSize = main.Size
    miniBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            twn(main, 0.2, {Size = UDim2.fromOffset(main.Size.X.Offset, 44)}):Play()
        else
            twn(main, 0.2, {Size = storedSize}):Play()
        end
    end)

    -- public window object
    local window = setmetatable({
        _gui = gui,
        _main = main,
        _tabs = tabs,
        _content = content,
        _pages = pages,
        _theme = theme,
        _notifyRoot = notifyRoot,
        _config = { values = {} },
        _configFile = opt.config_file or "hublib_config.json",
    }, HubLib)

    -- auto load config (best-effort)
    local loaded = File.read(window._configFile)
    if loaded and type(loaded) == "table" and type(loaded.values) == "table" then
        window._config = loaded
    end

    -- add API
    function window:SaveConfig()
        File.write(self._configFile, self._config)
    end

    function window:Notify(text: string, duration: number?)
        duration = duration or 2
        local card = mk("Frame", {
            BackgroundColor3 = self._theme.panel;
            Size = UDim2.fromOffset(0, 36);
            AnchorPoint = Vector2.new(1,0);
            Position = UDim2.new(1, 0, 0, 0);
        }, self._notifyRoot)
        mk("UICorner", {CornerRadius=UDim.new(0,8)}, card)
        mk("UIStroke", {Color=self._theme.stroke, Thickness=1, Transparency=0.2}, card)
        local lbl = mk("TextLabel", {
            BackgroundTransparency = 1;
            Text = text;
            Font = Enum.Font.GothamMedium;
            TextColor3 = self._theme.text;
            TextSize = 13;
            TextXAlignment = Enum.TextXAlignment.Left;
            Size = UDim2.new(1,-16,1,0);
            Position = UDim2.fromOffset(8,0);
        }, card)
        twn(card, 0.2, {Size = UDim2.fromOffset(300,36)}):Play()
        task.delay(duration, function()
            local tw = twn(card, 0.2, {Size = UDim2.fromOffset(0,36)})
            tw.Completed:Connect(function() card:Destroy() end)
            tw:Play()
        end)
    end

    function window:AddTab(name: string)
        -- tab button
        local btn = mk("TextButton", {
            Text = name;
            Font = Enum.Font.GothamMedium;
            TextSize = 14;
            TextColor3 = self._theme.text;
            BackgroundColor3 = self._theme.bg;
            AutoButtonColor = false;
            Size = UDim2.new(1, -0, 0, 34);
        }, self._tabs)
        mk("UICorner", {CornerRadius=UDim.new(0,8)}, btn)

        -- page
        local page = mk("ScrollingFrame", {
            BackgroundTransparency = 1;
            Size = UDim2.new(1,-16,1,-16);
            Position = UDim2.fromOffset(8,8);
            ScrollBarThickness = 4;
            ScrollingDirection = Enum.ScrollingDirection.Y;
            CanvasSize = UDim2.new(0,0,0,0);
        }, self._content)
        local list = mk("UIListLayout", {Padding = UDim.new(0,10), SortOrder = Enum.SortOrder.LayoutOrder}, page)
        mk("UIPadding", {PaddingTop=UDim.new(0,8), PaddingLeft=UDim.new(0,8), PaddingRight=UDim.new(0,8), PaddingBottom=UDim.new(0,8)}, page)

        page.Visible = false
        self._pages[btn] = page

        local function select()
            for b, p in pairs(self._pages) do
                local sel = (b == btn)
                p.Visible = sel
                twn(b, 0.15, {BackgroundColor3 = sel and self._theme.accent or self._theme.bg}):Play()
                twn(b, 0.15, {TextColor3 = sel and Color3.new(1,1,1) or self._theme.text}):Play()
            end
            currentPage = page
        end

        btn.MouseButton1Click:Connect(select)
        if not currentPage then select() end

        local tabObj = {}

        function tabObj:AddSection(titleText: string)
            local section = mk("Frame", {
                BackgroundColor3 = self._theme.bg;
                Size = UDim2.new(1, -0, 0, 0);
                AutomaticSize = Enum.AutomaticSize.Y;
            }, page)
            mk("UICorner", {CornerRadius=UDim.new(0,10)}, section)
            mk("UIStroke", {Color=self._theme.stroke, Thickness=1, Transparency=0.2}, section)
            local pad = mk("UIPadding", {PaddingTop=UDim.new(0,10), PaddingBottom=UDim.new(0,10), PaddingLeft=UDim.new(0,10), PaddingRight=UDim.new(0,10)}, section)
            local vlist = mk("UIListLayout", {Padding=UDim.new(0,8), SortOrder=Enum.SortOrder.LayoutOrder}, section)

            local title = mk("TextLabel", {
                BackgroundTransparency = 1;
                Text = titleText;
                Font = Enum.Font.GothamBold;
                TextColor3 = self._theme.text;
                TextSize = 14;
                TextXAlignment = Enum.TextXAlignment.Left;
                Size = UDim2.new(1,0,0,18);
            }, section)

            local secObj = {}

            function secObj:AddButton(text: string, callback)
                local btn = mk("TextButton", {
                    Text = text;
                    Font = Enum.Font.GothamMedium;
                    TextSize = 14;
                    TextColor3 = Color3.new(1,1,1);
                    BackgroundColor3 = HubLib._theme and HubLib._theme.accent or DEFAULT_THEME.accent;
                    AutoButtonColor = false;
                    Size = UDim2.new(1,0,0,34);
                }, section)
                mk("UICorner", {CornerRadius=UDim.new(0,8)}, btn)
                btn.MouseButton1Click:Connect(function()
                    twn(btn, 0.05, {BackgroundTransparency = 0.2}):Play()
                    task.wait(0.07)
                    twn(btn, 0.15, {BackgroundTransparency = 0}):Play()
                    if callback then task.spawn(callback) end
                end)
                return btn
            end

            function secObj:AddToggle(text: string, defaultVal: boolean?, callback)
                local val = (defaultVal == true)
                local key = ("toggle:%s"):format(text)
                if window._config.values[key] ~= nil then
                    val = window._config.values[key]
                end

                local holder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,28)}, section)
                local lbl = mk("TextLabel", {
                    BackgroundTransparency=1;
                    Text = text;
                    Font = Enum.Font.Gotham;
                    TextColor3 = window._theme.text;
                    TextSize = 13;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    Size = UDim2.new(1,-46,1,0);
                }, holder)

                local box = mk("TextButton", {
                    Text = "";
                    AutoButtonColor = false;
                    BackgroundColor3 = val and window._theme.accent or window._theme.panel;
                    Size = UDim2.fromOffset(36,20);
                    Position = UDim2.new(1,-36,0.5,-10);
                }, holder)
                mk("UICorner", {CornerRadius=UDim.new(1,999)}, box)
                local knob = mk("Frame", {
                    BackgroundColor3 = Color3.new(1,1,1);
                    Size = UDim2.fromOffset(16,16);
                    Position = val and UDim2.fromOffset(18,2) or UDim2.fromOffset(2,2);
                }, box)
                mk("UICorner", {CornerRadius=UDim.new(1,999)}, knob)

                local sig = Signal()

                local function set(v: boolean)
                    val = v
                    window._config.values[key] = v
                    window:SaveConfig()
                    twn(box, 0.15, {BackgroundColor3 = v and window._theme.accent or window._theme.panel}):Play()
                    twn(knob,0.15,{Position = v and UDim2.fromOffset(18,2) or UDim2.fromOffset(2,2)}):Play()
                    if callback then task.spawn(callback, v) end
                    sig:Fire(v)
                end

                box.MouseButton1Click:Connect(function() set(not val) end)

                return {
                    Set = set,
                    Get = function() return val end,
                    OnChanged = function(_, fn) return sig:Connect(fn) end,
                }
            end

            function secObj:AddSlider(text: string, conf, callback)
                conf = conf or {min=0,max=100,default=0,step=1}
                local key = ("slider:%s"):format(text)
                local val = conf.default or conf.min or 0
                if window._config.values[key] ~= nil then val = window._config.values[key] end

                local holder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,42)}, section)
                local lbl = mk("TextLabel", {
                    BackgroundTransparency=1;
                    Text = string.format("%s: %s", text, tostring(val));
                    Font = Enum.Font.Gotham;
                    TextColor3 = window._theme.text;
                    TextSize = 13;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    Size = UDim2.new(1,0,0,18);
                }, holder)

                local bar = mk("Frame", {
                    BackgroundColor3 = window._theme.panel;
                    Size = UDim2.new(1,0,0,6);
                    Position = UDim2.new(0,0,0,24);
                }, holder)
                mk("UICorner", {CornerRadius=UDim.new(1,999)}, bar)
                mk("UIStroke", {Color=window._theme.stroke, Thickness=1, Transparency=0.4}, bar)

                local fill = mk("Frame", {
                    BackgroundColor3 = window._theme.accent;
                    Size = UDim2.new((val - conf.min)/(conf.max - conf.min),0,1,0);
                }, bar)
                mk("UICorner", {CornerRadius=UDim.new(1,999)}, fill)

                local dragging = false
                local sig = Signal()

                local function apply(x)
                    local a = math.clamp(x, 0, 1)
                    local raw = conf.min + a*(conf.max - conf.min)
                    local stepped = round(raw, conf.step or 1)
                    val = math.clamp(stepped, conf.min, conf.max)
                    window._config.values[key] = val
                    window:SaveConfig()
                    lbl.Text = string.format("%s: %s", text, tostring(val))
                    twn(fill,0.05,{Size = UDim2.new((val-conf.min)/(conf.max-conf.min),0,1,0)}):Play()
                    if callback then task.spawn(callback, val) end
                    sig:Fire(val)
                end

                bar.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then
                        dragging = true
                        local rel = (i.Position.X - bar.AbsolutePosition.X)/bar.AbsoluteSize.X
                        apply(rel)
                    end
                end)
                UserInputService.InputEnded:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
                end)
                UserInputService.InputChanged:Connect(function(i)
                    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
                        local rel = (i.Position.X - bar.AbsolutePosition.X)/bar.AbsoluteSize.X
                        apply(rel)
                    end
                end)

                return {
                    Set = function(_, v) apply((v-conf.min)/(conf.max-conf.min)) end,
                    Get = function() return val end,
                    OnChanged = function(_, fn) return sig:Connect(fn) end,
                }
            end

            function secObj:AddDropdown(text: string, list: {string}, defaultIndex: number?, callback)
                local idx = defaultIndex or 1
                idx = math.clamp(idx, 1, math.max(1, #list))
                local key = ("dropdown:%s"):format(text)
                if window._config.values[key] ~= nil then
                    local saved = window._config.values[key]
                    for i, v in ipairs(list) do if v == saved then idx = i break end end
                end
                local current = list[idx] or ""

                local holder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,32)}, section)
                local btn = mk("TextButton", {
                    Text = string.format("%s: %s", text, current);
                    Font = Enum.Font.Gotham;
                    TextSize = 13;
                    TextColor3 = window._theme.text;
                    AutoButtonColor = false;
                    BackgroundColor3 = window._theme.panel;
                    Size = UDim2.new(1,0,1,0);
                    TextXAlignment = Enum.TextXAlignment.Left;
                }, holder)
                mk("UICorner", {CornerRadius=UDim.new(0,8)}, btn)
                mk("UIStroke", {Color=window._theme.stroke, Thickness=1, Transparency=0.3}, btn)

                local open = false
                local listFrame = mk("Frame", {
                    BackgroundColor3 = window._theme.bg;
                    Size = UDim2.new(1,0,0, math.min(6,#list)*26);
                    Position = UDim2.new(0,0,0,36);
                    Visible = false;
                }, holder)
                mk("UICorner", {CornerRadius=UDim.new(0,8)}, listFrame)
                mk("UIStroke", {Color=window._theme.stroke, Thickness=1, Transparency=0.2}, listFrame)
                local lay = mk("UIListLayout", {Padding=UDim.new(0,6)}, listFrame)
                mk("UIPadding", {PaddingTop=UDim.new(0,6), PaddingLeft=UDim.new(0,6), PaddingRight=UDim.new(0,6), PaddingBottom=UDim.new(0,6)}, listFrame)

                local function choose(i)
                    idx = i
                    current = list[idx]
                    window._config.values[key] = current
                    window:SaveConfig()
                    btn.Text = string.format("%s: %s", text, current)
                    if callback then task.spawn(callback, current) end
                    twn(listFrame,0.15,{Size=UDim2.new(1,0,0,0)}).Completed:Connect(function()
                        listFrame.Visible=false
                    end)
                    open=false
                end

                for i, val in ipairs(list) do
                    local it = mk("TextButton", {
                        Text = val;
                        Font = Enum.Font.Gotham;
                        TextSize = 12;
                        TextColor3 = window._theme.text;
                        AutoButtonColor = false;
                        BackgroundColor3 = window._theme.panel;
                        Size = UDim2.new(1,0,0,20);
                    }, listFrame)
                    mk("UICorner", {CornerRadius=UDim.new(0,6)}, it)
                    it.MouseButton1Click:Connect(function() choose(i) end)
                end

                btn.MouseButton1Click:Connect(function()
                    open = not open
                    if open then
                        listFrame.Visible = true
                        twn(listFrame,0.15,{Size=UDim2.new(1,0,0, math.min(6,#list)*26)}):Play()
                    else
                        local tw = twn(listFrame,0.15,{Size=UDim2.new(1,0,0,0)})
                        tw.Completed:Connect(function() listFrame.Visible=false end)
                        tw:Play()
                    end
                end)

                return {
                    Get = function() return current end,
                    Set = function(_, v)
                        for i,val in ipairs(list) do if val==v then choose(i) break end end
                    end,
                    SetItems = function(_, newList)
                        list = newList
                        -- TODO: rebuild items (left minimal for brevity)
                    end
                }
            end

            function secObj:AddTextbox(text: string, placeholder: string?, callback)
                local holder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,32)}, section)
                local lbl = mk("TextLabel", {
                    BackgroundTransparency=1;
                    Text = text;
                    Font = Enum.Font.Gotham;
                    TextColor3 = window._theme.text;
                    TextSize = 13;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    Size = UDim2.new(0.35,0,1,0);
                }, holder)

                local box = mk("TextBox", {
                    PlaceholderText = placeholder or "";
                    Text = "";
                    Font = Enum.Font.Gotham;
                    TextColor3 = window._theme.text;
                    TextSize = 13;
                    BackgroundColor3 = window._theme.panel;
                    Size = UDim2.new(0.65,-6,1,0);
                    Position = UDim2.new(0.35,6,0,0);
                    ClearTextOnFocus = false;
                }, holder)
                mk("UICorner", {CornerRadius=UDim.new(0,8)}, box)
                mk("UIStroke", {Color=window._theme.stroke, Thickness=1, Transparency=0.3}, box)

                box.FocusLost:Connect(function(enter)
                    if callback then task.spawn(callback, box.Text, enter) end
                end)

                return box
            end

            function secObj:AddKeybind(text: string, defaultKey: Enum.KeyCode?, callback)
                local key = defaultKey or Enum.KeyCode.K
                local holder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,28)}, section)
                local lbl = mk("TextLabel", {
                    BackgroundTransparency=1;
                    Text = string.format("%s: %s", text, key.Name);
                    Font = Enum.Font.Gotham;
                    TextColor3 = window._theme.text;
                    TextSize = 13;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    Size = UDim2.new(1,0,1,0);
                }, holder)

                local listening = false
                holder.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 then
                        listening = true
                        lbl.Text = text .. ": [press key]"
                    end
                end)

                UserInputService.InputBegan:Connect(function(i, gp)
                    if gp then return end
                    if listening and i.KeyCode ~= Enum.KeyCode.Unknown then
                        key = i.KeyCode
                        listening = false
                        lbl.Text = string.format("%s: %s", text, key.Name)
                    elseif i.KeyCode == key then
                        if callback then task.spawn(callback) end
                    end
                end)

                return {
                    Get = function() return key end,
                    Set = function(_, kc) key = kc; lbl.Text = string.format("%s: %s", text, key.Name) end
                }
            end

            return secObj
        end

        return tabObj
    end

    -- expose toggle of visibility + bind
    local toggleKey = opt.minimize_key or Enum.KeyCode.RightControl
    UserInputService.InputBegan:Connect(function(i, gp)
        if gp then return end
        if i.KeyCode == toggleKey then
            main.Visible = not main.Visible
        end
    end)

    return window
end

return HubLib
