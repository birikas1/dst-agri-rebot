-- The robot panel no longer hosts the default planting-template editor.
-- Farmland badges remain the place to set crop plans.
Class=function(base,ctor)
    if ctor==nil then ctor=base;base=nil end
    local cls={_ctor=ctor,_base=base};cls.__index=cls
    if type(base)=="table" then
        cls._base=base
        setmetatable(cls,{__index=base,__call=function(_,...) local self=setmetatable({},cls);ctor(self,...);return self end})
    else
        return setmetatable(cls,{__call=function(_,...) local self=setmetatable({},cls);ctor(self,...);return self end})
    end
    return cls
end
TheWorld={ismastersim=true,Map={},components={}}
TUNING={}
STRINGS={NAMES={}}
SCALEMODE_PROPORTIONAL,ANCHOR_MIDDLE,ANCHOR_LEFT,ANCHOR_TOP,BODYTEXTFONT=1,2,3,4,5
package.preload["widgets/screen"]=function()
    local S={}
    function S._ctor(self,name) self.name=name end
    return S
end
for _,name in ipairs({"widget","text","textbutton","image"}) do
    package.preload["widgets/"..name]=function()
        local W={}
        return setmetatable(W,{__call=function() return {} end})
    end
end

local failures,passed={},0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1 else failures[#failures+1]=name..": "..tostring(err) end
end

test("panel and help source no longer contain the template editor",function()
    local f=assert(io.open("agri_robot/scripts/screens/agribotpanel.lua","r"))
    local src=f:read("*a");f:close()
    for _,needle in ipairs({"默认比例模板","默认每格孔数","清空模板","清空方案","默认每根孔数"}) do
        assert(not src:find(needle,1,true),"panel still contains "..needle)
    end
    assert(not src:find("function Panel:SendPlan",1,true),"SendPlan should be gone")
    assert(src:find("打开机器人库存",1,true))
    assert(src:find("点击暂停",1,true) or src:find("点击运行",1,true))
    assert(src:find("田块列表",1,true) and src:find("农业计划",1,true)
        and src:find("资源",1,true) and src:find("使用方法",1,true))
    assert(src:find("农田上方的浮动标签",1,true),"help/status should point at farmland badges")
end)

test("farmland zone HUD still has the crop-plan editor",function()
    local f=assert(io.open("agri_robot/scripts/widgets/agrizonehud.lua","r"))
    local src=f:read("*a");f:close()
    assert(src:find("使用默认模板",1,true))
    assert(src:find("每格孔数",1,true))
    assert(src:find("比例填满",1,true) or src:find("精确数量",1,true) or src:find("MODE_TEXT",1,true))
    assert(src:find("function Editor:RenderSlots",1,true) or src:find("RenderSlots",1,true))
end)

local Panel=require("screens/agribotpanel")

local function capture(snapshot)
    snapshot=snapshot or {}
    snapshot.group_id=snapshot.group_id or "farm_1"
    snapshot.members=snapshot.members or {1,2,3,4}
    snapshot.season=snapshot.season or "autumn"
    snapshot.settings=snapshot.settings or {running=true,density="8",plan={carrot=4}}
    snapshot.farm_stats=snapshot.farm_stats or {plots=4,growing=2,mature=1}
    snapshot.resources=snapshot.resources or {tools={hoe={count=1},shovel={count=0},hammer={count=0},axe={count=0},pickaxe={count=0}},water={cans={{}}}}
    snapshot.warehouse=snapshot.warehouse or {guid=9}
    snapshot.zones_enabled=snapshot.zones_enabled~=false
    snapshot.zones=snapshot.zones or {{id="z1"},{id="z2"}}
    snapshot.tasks=snapshot.tasks or {queue={{kind="TILL",state="ready"}}}
    snapshot.plan=snapshot.plan or {reasons={}}
    snapshot.crop_options=snapshot.crop_options or {
        {id="asparagus",product="asparagus",seed="asparagus_seeds"},
        {id="carrot",product="carrot",seed="carrot_seeds"},
        {id="corn",product="corn",seed="corn_seeds"},
    }
    local texts={}
    local panel=setmetatable({
        snapshot=snapshot,
        body={},
        notice={SetString=function()end},
        send=function()end,
    },{__index=Panel})
    function panel:Label(_,text)
        texts[#texts+1]=tostring(text)
        return {}
    end
    function panel:Button(_,text)
        texts[#texts+1]=tostring(text)
        return {}
    end
    function panel:Setting() end
    panel:RenderStatus()
    return table.concat(texts,"\n"),texts
end

test("management tab keeps pause and inventory, drops the template editor controls",function()
    local blob=capture()
    assert(blob:find("打开机器人库存",1,true))
    assert(blob:find("运行中",1,true) and blob:find("点击暂停",1,true))
    assert(blob:find("工作组 farm_1",1,true))
    assert(blob:find("4 台机器人",1,true))
    for _,needle in ipairs({"默认比例模板","默认每格孔数","清空模板","清空方案","种植方案：共","库存 ","上一页","下一页"}) do
        assert(not blob:find(needle,1,true),"management tab still shows "..needle.."\n"..blob)
    end
    -- Density hole buttons like "8 孔" must not return.
    assert(not blob:find("%d+ 孔"))
    assert(not blob:find("+",1,true) or blob:find("打开机器人库存",1,true))
    -- The leftover '+' in crop steppers is gone; a lone "+" button would be the stepper.
    local has_stepper=blob:find("\n%+\n") or blob:find("^%+\n") or blob:find("\n%+$")
    assert(not has_stepper,"crop + stepper is still on the management tab:\n"..blob)
    assert(blob:find("仓库：已绑定",1,true))
    assert(blob:find("浮动标签",1,true))
    assert(blob:find("多余的工具",1,true) or blob:find("农业仓库",1,true))
end)

if #failures>0 then error(table.concat(failures,"\n")) end
return passed.." panel template-removal scenarios"
