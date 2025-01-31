local Types = loadstring(game:HttpGet("https://raw.githubusercontent.com/pupsore/Iris/refs/heads/main/main/Types.lua"))()

local Iris = {} :: Types.Iris

local InternalLoad = loadstring(game:HttpGet("https://github.com/pupsore/Iris/blob/main/main/Internal.lua"))()
local Internal: Types.Internal = InternalLoad(Iris)

Iris.Disabled = false

Iris.Args = {}

Iris.Events = {}

function Iris.Init(parentInstance: BasePlayerGui?, eventConnection: (RBXScriptSignal | () -> ())?, config: { [string]: any }?): Types.Iris
    assert(Internal._started == false, "Iris.Init can only be called once.")
    assert(Internal._shutdown == false, "Iris.Init cannot be called once shutdown.")

    if parentInstance == nil then
        parentInstance = game:GetService("CoreGui")
    end
    if eventConnection == nil then
        eventConnection = game:GetService("RunService").Heartbeat
    end
    Internal.parentInstance = parentInstance :: BasePlayerGui
    Internal._started = true

    Internal._generateRootInstance()
    Internal._generateSelectionImageObject()

    for _, callback: () -> () in Internal._initFunctions do
        callback()
    end

    task.spawn(function()
        if typeof(eventConnection) == "function" then
            while Internal._started do
                eventConnection()
                Internal._cycle()
            end
        elseif eventConnection ~= nil then
            Internal._eventConnection = eventConnection:Connect(function()
                Internal._cycle()
            end)
        end
    end)

    return Iris
end

function Iris.Shutdown()
    Internal._started = false
    Internal._shutdown = true

    if Internal._eventConnection then
        Internal._eventConnection:Disconnect()
    end
    Internal._eventConnection = nil

    if Internal._rootWidget then
        if Internal._rootWidget.Instance then
            Internal._widgets["Root"].Discard(Internal._rootWidget)
        end
        Internal._rootInstance = nil
    end

    if Internal.SelectionImageObject then
        Internal.SelectionImageObject:Destroy()
    end

    for _, connection: RBXScriptConnection in Internal._connections do
        connection:Disconnect()
    end
end

function Iris:Connect(callback: () -> ()) -- this uses method syntax for no reason.
    if Internal._started == false then
        warn("Iris:Connect() was called before calling Iris.Init(), the connected function will never run")
    end
    table.insert(Internal._connectedFunctions, callback)
end

function Iris.Append(userInstance: GuiObject)
    local parentWidget: Types.Widget = Internal._GetParentWidget()
    local widgetInstanceParent: GuiObject
    if Internal._config.Parent then
        widgetInstanceParent = Internal._config.Parent :: any
    else
        widgetInstanceParent = Internal._widgets[parentWidget.type].ChildAdded(parentWidget, { type = "userInstance" } :: Types.Widget)
    end
    userInstance.Parent = widgetInstanceParent
end

function Iris.End()
    if Internal._stackIndex == 1 then
        error("Callback has too many calls to Iris.End()", 2)
    end
    Internal._IDStack[Internal._stackIndex] = nil
    Internal._stackIndex -= 1
end

function Iris.ForceRefresh()
    Internal._globalRefreshRequested = true
end

--[=[
    @function UpdateGlobalConfig
    @within Iris
    @param deltaStyle table -- a table containing the changes in style ex: `{ItemWidth = UDim.new(0, 100)}`

    Allows callers to customize the config which **every** widget will inherit from.
    It can be used along with Iris.TemplateConfig to easily swap styles, ex: ```Iris.UpdateGlobalConfig(Iris.TemplateConfig.colorLight) -- use light theme```
    :::caution Caution: Performance
    this function internally calls [Iris.ForceRefresh] so that style changes are propogated, it may cause **performance issues** when used with many widgets.
    In **no** case should it be called every frame.
    :::
]=]
function Iris.UpdateGlobalConfig(deltaStyle: { [string]: any })
    for index, style in deltaStyle do
        Internal._rootConfig[index] = style
    end
    Iris.ForceRefresh()
end

function Iris.PushConfig(deltaStyle: { [string]: any })
    local ID = Iris.State(-1)
    if ID.value == -1 then
        ID:set(deltaStyle)
    else
        -- compare tables
        if Internal._deepCompare(ID:get(), deltaStyle) == false then
            -- refresh local
            Internal._localRefreshActive = true
            ID:set(deltaStyle)
        end
    end

    Internal._config = setmetatable(deltaStyle, {
        __index = Internal._config,
    }) :: any
end

function Iris.PopConfig()
    Internal._localRefreshActive = false
    Internal._config = getmetatable(Internal._config :: any).__index
end

Iris.TemplateConfig = loadstring(game:HttpGet("https://raw.githubusercontent.com/peke7374/Iris/main/config.lua"))()
Iris.UpdateGlobalConfig(Iris.TemplateConfig.colorDark) -- use colorDark and sizeDefault themes by default
Iris.UpdateGlobalConfig(Iris.TemplateConfig.sizeDefault)
Iris.UpdateGlobalConfig(Iris.TemplateConfig.utilityDefault)
Internal._globalRefreshRequested = false -- UpdatingGlobalConfig changes this to true, leads to Root being generated twice.

function Iris.PushId(id: Types.ID)
    assert(typeof(id) == "string", "Iris expected Iris.PushId id to PushId to be a string.")

    Internal._pushedId = tostring(id)
end

function Iris.PopId()
    Internal._pushedId = nil
end

function Iris.SetNextWidgetID(id: Types.ID)
    Internal._nextWidgetId = id
end

function Iris.State(initialValue: any): Types.State
    local ID: Types.ID = Internal._getID(2)
    if Internal._states[ID] then
        return Internal._states[ID]
    end
    Internal._states[ID] = {
        value = initialValue,
        ConnectedWidgets = {},
        ConnectedFunctions = {},
    } :: any
    setmetatable(Internal._states[ID], Internal.StateClass)
    return Internal._states[ID]
end

function Iris.WeakState(initialValue: any): Types.State
    local ID: Types.ID = Internal._getID(2)
    if Internal._states[ID] then
        if next(Internal._states[ID].ConnectedWidgets) == nil then
            Internal._states[ID] = nil
        else
            return Internal._states[ID]
        end
    end
    Internal._states[ID] = {
        value = initialValue,
        ConnectedWidgets = {},
        ConnectedFunctions = {},
    } :: any
    setmetatable(Internal._states[ID], Internal.StateClass)
    return Internal._states[ID]
end

function Iris.ComputedState(firstState: Types.State, onChangeCallback: (firstState: any) -> any): Types.State
    local ID: Types.ID = Internal._getID(2)

    if Internal._states[ID] then
        return Internal._states[ID]
    else
        Internal._states[ID] = {
            value = onChangeCallback(firstState.value),
            ConnectedWidgets = {},
            ConnectedFunctions = {},
        } :: any
        firstState:onChange(function(newValue: any)
            Internal._states[ID]:set(onChangeCallback(newValue))
        end)
        setmetatable(Internal._states[ID], Internal.StateClass)
        return Internal._states[ID]
    end
end

local DemoLoad = loadstring(game:HttpGet("https://raw.githubusercontent.com/pupsore/Iris/refs/heads/main/main/demoWindow.lua"))()
Iris.ShowDemoWindow = DemoLoad(Iris)

local ApiLoad = loadstring(game:HttpGet("https://raw.githubusercontent.com/peke7374/Iris/main/API.lua"))()
local WidgetLoad = loadstring(game:HttpGet("https://raw.githubusercontent.com/peke7374/Iris/main/widgets.lua"))()
WidgetLoad(Internal)
ApiLoad(Iris)

return Iris
demoWindow
