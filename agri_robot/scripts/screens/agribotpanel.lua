local Screen=require("widgets/screen")
local Widget=require("widgets/widget")
local Text=require("widgets/text")
local TextButton=require("widgets/textbutton")
local Image=require("widgets/image")
local U=require("agri/util")
local C=require("agri/constants")
local Visuals=require("agri/visuals")

local seasons={autumn="秋",winter="冬",spring="春",summer="夏"}
local modes={auto="自动最佳",fixed="固定推荐",crop="指定作物",ratio="指定多作物比例",pause="本季暂停播种"}
local labels={status="状态",ready="可执行",waiting="等待资源",blocked="阻塞",search_pending="继续搜索候选中",SEARCH_PENDING="继续搜索候选中",
    season="季节",maturity="预计成熟",maturity_seconds="成熟秒数",crossing="跨季",crossings="跨季阶段",reasons="原因",warnings="提示",
    nutrient_delta="营养净变化",nutrients="土壤营养",fertilizer="施肥计划",fertilizers="肥料",water="水分",water_uses="所需浇水次数",
    oversized="巨大资格",oversized_eligible="巨大资格",eligible="符合",rounds="可支持轮数",seed_rounds="库存可支持轮数",seeds="种子",counts="作物数量",crops="作物",
    layouts="布局",layout="布局",cluster="农田组",clusters="农田组",holes="孔位",growing="生长中",mature="成熟",managed="管理地块",time="时间",
    TOOL_HOE_MISSING="缺少园艺锄",OUTPUT_FULL="输出空间已满",BLOCKED_STRUCTURE="玩家建筑阻挡",SEASON_CROSS_BAD="成熟前进入不适宜季节",
    WATER_OK_RAIN="降雨足够，无需浇水",WATER_CAN_EMPTY="水壶已空",NO_SEEDS="缺少完整种植方案的种子",NUTRIENT_SHORT="土壤营养不足",
    RAIN_SUFFICIENT="当前雨水足够",SOIL_SUFFICIENT="当前土壤足够",NO_BLUEPRINT="请先确认农田蓝图"}
for key,value in pairs({
    code="原因",count="数量",current="当前工作",primary="主机器人",order="机器人编号",module="模块",none="无",robots="机器人",
    source="水源",has_source="附近可补水",cans="水壶",uses="剩余次数",capacity="容量",temperature="温度",ready="可执行",free="空格",
    plots="农田数",growing="生长株数",mature="成熟株数",issues="异常区域",hoe="锄头",plow="耕地机",hammer="锤子",shovel="铲子",
    recycle="回收的耕地机",carried="机器人携带",stored="仓库中",
    mode="模式",ordinary="普通",fridge="冰箱保鲜",super="超级保鲜",groups="分区",seed="种子",crop="作物",
    net="净变化",deficit="缺口",minimum="最低养分",final="轮末养分",nutrients="养分（生长/堆肥/粪肥）",
    stock_rounds="保守可支持轮数",seed_rounds="种子轮数上界",supported_rounds="资源支持轮数",limiting_resources="限制资源",
    best_known="当前已验证最佳，搜索继续",proven_optimal="已证明最优",optimality="方案搜索状态",search_pending="正在继续搜索",
    INCOMPLETE_ROUND_SEEDS="种子不足以完成整个配比",NO_COMPLETE_ROUND="暂无完整资源可执行方案",
    INSUFFICIENT_WATER="水不足，且工作范围内没有可用水源",INSUFFICIENT_FERTILIZER="可解析肥料不足以保证整轮养分",
    INSUFFICIENT_HOE_USES="真实锄头耐久不足",INSUFFICIENT_PLOW_USES="真实耕地机次数不足",NO_SAFE_FAMILY_LAYOUT="家族或拥挤条件不满足",
    RATIO_DOES_NOT_FIT_LAYOUT="指定比例无法完整填入当前布局",NUTRIENT_WINDOW_EXCEEDS_CAPACITY="保守阶段营养界超过土壤容量，需调整方案",
    LAYOUT_OBSTRUCTED="布局有障碍，先安全清理或调整蓝图",PRESET_PAUSED="本季预设暂停播种",CONTINUOUS_OFF="已完成本轮，连续种植关闭",
    DAY_LENGTH_MODIFIER_UNCERTAIN="日长规则发生变化，巨大资格无法保证",CALENDAR_UNAVAILABLE="当前世界日历信息不可用",
    NIGHT_PAUSE_UNLESS_VERIFIED_LIGHT="无可靠夜间照明时计入暂停",CURRENT_NATIVE_DAY_LENGTH_RULES_UNCHANGED="预测假设当前日长规则保持不变",
    CURRENT_STOCK_AND_SOIL="使用当前库存与土壤",FUTURE_SEASON_START="模拟从该季开始播种",NO_UNVERIFIED_FUTURE_RAIN_CREDIT="不预支未知未来雨水",
    PLOW="耕地机收尾",TILL="打孔",PLANT="播种",FERTILIZE="按需施肥",WATER="按需浇水",TEND="逐株照料",MUSIC_TEND="音乐照料",
    HARVEST="收获",HAMMER="敲开巨大作物",PICKUP="拾取",CLEAR="安全清理",REFILL="批量补水",HEAT="工具回温",FETCH="批量取料",UNLOAD="批量入库",
    pending="等待依赖或时机",claimed="已认领",running="正在执行",paused="已抢占暂停",blocked="阻塞",complete="完成",
    PLAN_EMPTY="种植方案为空：请在管理页用 + 添加要种的作物",MISSING_SEEDS="部分种子不足，已按现有种子先种",
    NEED_FARMLAND="农田不够：请手动开垦农田（机器人不会自动耕地）",NEED_PLOW="农田不够：请手动开垦农田（机器人不会自动耕地）",
    plow_disabled="自动耕地已关闭，旧耕地任务不再执行",
    recycle_no_warehouse="捡到的耕地机暂留在机器人里：请绑定仓库",recycle_warehouse_full="仓库作物/回收区已满，耕地机暂留在机器人里",
    NEED_HOE="需要打孔：请把园艺锄放进机器人工具格",NOT_ENOUGH_HOLES="孔位不足：增加农田或调高密度",
    NO_FARM_CELLS="工作范围内没有农田",PLOW_IN_PROGRESS="耕地机正在工作",DENSITY_SPACING_UNSAFE="该密度在此地块无法安全排布",
    OFFGRID_PLANT="地块里有不在网格上的作物",randomseed="通用种子",
    WATER_MOISTURE_UNKNOWN="读不到土壤湿度，暂不浇水",WATER_NO_CAN="作物缺水：没有水壶",
    WATER_CAN_NOT_CARRIED="作物缺水：请把水壶放进机器人的水壶格",WATER_NO_SOURCE="作物缺水：水壶已空且范围内没有水源",
    WATER_REFILLING="水壶已空，先去补水再浇",
    zone_paused="田块已暂停",zone_editing="田块编辑中",zone_invalidated="田块方案已变化",
    ZONE_WITHHELD="部分孔位暂缓",ZONE_REVIEW="田块方案待确认",ADJACENT_ZONE_SPACING="相邻田块孔距不足",MOISTURE_SNAPSHOT_UNAVAILABLE="土壤湿度读取失败",moisture_unknown="读不到土壤湿度，本次未浇水",
}) do labels[key]=value end
local function name(value)
    if value==nil then return "—" end
    return labels[value] or seasons[value] or (STRINGS.NAMES and STRINGS.NAMES[string.upper(tostring(value))]) or tostring(value)
end
local function describe(value,depth)
    depth=depth or 0
    if type(value)=="number" then return value%1==0 and tostring(value) or string.format("%.2f",value) end
    if type(value)=="boolean" then return value and "是" or "否" end
    if type(value)~="table" then return name(value) end
    if depth>3 then return "…" end
    local lines={}
    for _,key in ipairs(U.Keys(value)) do
        local val=value[key]
        if key~="tasks" and key~="target" and key~="plant" and key~="inst" and type(val)~="function" then
            lines[#lines+1]=(type(key)=="number" and "" or name(key).."：")..describe(val,depth+1)
        end
    end
    return table.concat(lines,depth==0 and "\n" or " / ")
end

local function details(value)
    local lines={}
    local hidden={id=true,guid=true,source_build=true,nodes=true,metrics=true,tasks=true,inst=true,entity=true,target=true}
    local function visit(v,path,depth)
        if type(v)~="table" then lines[#lines+1]=path..describe(v);return end
        if depth>9 then return end
        local vector=#v>0 and #v<=5
        for k,item in pairs(v) do if type(k)~="number" or type(item)=="table" then vector=false end end
        if vector then lines[#lines+1]=path..describe(v);return end
        for _,key in ipairs(U.Keys(v)) do
            if not hidden[key] then visit(v[key],path..(type(key)=="number" and tostring(key) or name(key)).." / ",depth+1) end
        end
    end
    visit(value,"",0)
    return table.concat(lines,"\n")
end

local Panel=Class(Screen,function(self,robot,snapshot,send)
    Screen._ctor(self,"AgriBotPanel")
    self.robot,self.snapshot,self.send=robot,snapshot,send
    self.page,self.textpage,self.crop_page="status",1,1
    self.draft=U.Copy(snapshot.blueprint.cells or {})
    self.draft_revision=snapshot.revision
    self.draft_dirty=false
    self.season=snapshot.season or "autumn"
    self.preset=U.Copy(snapshot.presets[self.season] or {mode="auto"})
    self.markers={}
    self.root=self:AddChild(Widget("agri_root"))
    self.root:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self.root:SetHAnchor(ANCHOR_MIDDLE)
    self.root:SetVAnchor(ANCHOR_MIDDLE)
    self.bg=self.root:AddChild(Image("images/global.xml","square.tex"))
    self.bg:SetSize(1060,640);self.bg:SetTint(0.08,0.10,0.075,0.97)
    self:Label(self.root,"田间管家  /  农业机器人",0,285,28)
    self:Button(self.root,"关闭",465,285,function()self:Close()end)
    -- Simple branch: blueprint, seasonal presets and recommendations are hidden.
    local tabs={{"status","管理"},{"plan","农业计划"},{"resources","资源"},{"help","使用方法"}}
    if snapshot.zones_enabled then table.insert(tabs,2,{"zones","田块列表"}) end
    local step=#tabs>4 and 180 or 220
    self.plan=U.Copy(snapshot.settings.plan or {})
    for i,tab in ipairs(tabs) do
        self:Button(self.root,tab[2],-(#tabs-1)*step/2+(i-1)*step,238,function()
            self.page=tab[1];self.textpage=1;self:Render()
            if self.page=="recommendations" then self.send({cmd="recommendations",page=1}) end
        end)
    end
    self.notice=self:Label(self.root,"所有操作由服务器核验；关闭面板后机器人按方案开工。",0,-287,18)
    self.body=self.root:AddChild(Widget("agri_body"))
    self:Render()
    self:StartUpdating()
    self.elapsed=0
end)

function Panel:Label(parent,text,x,y,size,width,height)
    local label=parent:AddChild(Text(BODYTEXTFONT,size or 20,tostring(text)))
    label:SetPosition(x,y)
    if width then label:SetRegionSize(width,height or 40);label:EnableWordWrap(true);label:SetHAlign(ANCHOR_LEFT);label:SetVAlign(ANCHOR_TOP) end
    return label
end
function Panel:Button(parent,text,x,y,fn,size)
    local button=parent:AddChild(TextButton())
    button:SetText(text);button:SetTextSize(size or 21);button:SetPosition(x,y);button:SetOnClick(fn)
    return button
end
function Panel:Intent(cmd,data)
    self.send({cmd=cmd,data=data})
end
function Panel:Setting(key,value)
    self:Intent("settings",{[key]=value})
end
function Panel:CropName(id)
    for _,crop in ipairs(self.snapshot.crop_options or {}) do if crop.id==id then return name(crop.product) end end
    return name(id)
end
function Panel:TextPage(text)
    local lines={}
    for line in (text.."\n"):gmatch("(.-)\n") do
        -- Keep full detail accessible instead of truncating the forecast.
        lines[#lines+1]=line
    end
    local per=13
    local pages=math.max(1,math.ceil(#lines/per))
    self.textpage=math.min(self.textpage,pages)
    local out={}
    for i=(self.textpage-1)*per+1,math.min(#lines,self.textpage*per) do out[#out+1]=lines[i] end
    self:Label(self.body,table.concat(out,"\n"),0,20,20,940,360)
    self:Button(self.body,"上一页",-150,-235,function()self.textpage=math.max(1,self.textpage-1);self:Render()end)
    self:Label(self.body,self.textpage.." / "..pages,0,-235,18)
    self:Button(self.body,"下一页",150,-235,function()self.textpage=math.min(pages,self.textpage+1);self:Render()end)
end
function Panel:CropLabel(crop)
    if crop.random then return "通用种子" end
    return name(crop.product or crop.id)
end
function Panel:SendPlan()
    local out={};for k,v in pairs(self.plan) do if v>0 then out[k]=v end end
    self:Setting("plan",out)
end
function Panel:RenderStatus()
    local s=self.snapshot.settings
    if self.snapshot.editing then self.notice:SetString("玩家调整中：整个工作组已立即停工，关闭面板后按当前设置恢复。") end
    self:Label(self.body,"工作组 "..self.snapshot.group_id.."  ·  "..#self.snapshot.members.." 台机器人  ·  "..name(self.snapshot.season).."季",-230,190,22)
    self:Button(self.body,s.running and "运行中 · 点击暂停" or "已暂停 · 点击运行",190,190,function()self:Setting("running",not s.running)end,20)
    self:Button(self.body,"打开机器人库存",400,190,function()self.send({cmd="inventory"})end,20)
    -- Zone groups: these two rows are the DEFAULT template that zones without
    -- their own plan use (ratio, filling each zone's own capacity).
    local zoned=self.snapshot.zones_enabled==true
    -- 1. Planting density: holes per farm plot.
    local density=tostring(s.density=="dynamic" and C.DEFAULT_DENSITY or s.density)
    self:Label(self.body,zoned and "默认每格孔数（未单独设置的田块）" or "种植密度（每块农田的孔数）",-330,140,20)
    for i,d in ipairs(C.DENSITY_CHOICES) do
        self:Button(self.body,(density==d and "● " or "")..d.." 孔",-110+(i-1)*95,140,function()self:Setting("density",d)end)
    end
    -- 2. Planting plan: how many plants of each seed.
    local options=self.snapshot.crop_options or {}
    local seeds=(self.snapshot.resources or {}).seeds or {}
    local total=0;for _,v in pairs(self.plan) do total=total+v end
    local n=tonumber(density) or 9
    local plots=(self.snapshot.farm_stats or {}).plots or 0
    if zoned then
        self:Label(self.body,"默认比例模板：每个田块按此比例填满自己的容量 · 当前 "..#(self.snapshot.zones or {}).." 个田块（点田块上方标签可单独设置）",0,90,19)
    else
        self:Label(self.body,"种植方案：共 "..total.." 株 · 需要 "..math.ceil(total/n).." 块农田（现有 "..plots.." 块）",0,90,20)
    end
    local per=12
    local pages=math.max(1,math.ceil(#options/per))
    self.crop_page=math.min(self.crop_page or 1,pages)
    for index=(self.crop_page-1)*per+1,math.min(#options,self.crop_page*per) do
        local crop=options[index];local slot=(index-1)%per
        local bx=slot<6 and -480 or 20;local y=45-(slot%6)*40
        local count=self.plan[crop.id] or 0
        self:Label(self.body,self:CropLabel(crop),bx+85,y,20)
        self:Label(self.body,"库存 "..tostring(seeds[crop.seed] or 0),bx+220,y,17)
        self:Button(self.body,"-",bx+305,y,function()
            self.plan[crop.id]=math.max(0,count-1);if self.plan[crop.id]==0 then self.plan[crop.id]=nil end
            self:SendPlan();self:Render()
        end,26)
        self:Label(self.body,count,bx+355,y,22)
        self:Button(self.body,"+",bx+405,y,function()
            if total>=C.PLAN_MAX_TOTAL then return end
            self.plan[crop.id]=math.min(C.PLAN_MAX_PER_CROP,count+1);self:SendPlan();self:Render()
        end,26)
    end
    self:Button(self.body,"上一页",-250,-200,function()self.crop_page=math.max(1,self.crop_page-1);self:Render()end,19)
    self:Label(self.body,self.crop_page.." / "..pages,-130,-200,18)
    self:Button(self.body,"下一页",-10,-200,function()self.crop_page=math.min(pages,self.crop_page+1);self:Render()end,19)
    self:Button(self.body,zoned and "清空模板" or "清空方案",250,-200,function()self.plan={};self:SendPlan();self:Render()end,19)
    local nexttask=self.snapshot.tasks.queue and self.snapshot.tasks.queue[1]
    local state=nexttask and ("当前工作："..name(nexttask.kind).." · "..name(nexttask.state)..(nexttask.reason and " · "..name(nexttask.reason) or "")) or "当前没有待执行任务"
    local why={};for i,r in ipairs(self.snapshot.plan.reasons or {}) do if i<=2 then why[#why+1]=name(r.code) end end
    self:Label(self.body,state..(#why>0 and "   ·   "..table.concat(why,"；") or ""),0,-240,17)
end
function Panel:RenderBlueprint()
    self:Label(self.body,"同一蓝图可混合：拖选矩形、范围填充、点击增删",-25,205,20)
    self:Button(self.body,"范围填充",-400,174,function()self.send({cmd="fill"})end)
    self:Button(self.body,"矩形："..(self.rectmode and "开" or "关"),-240,174,function()self.rectmode=not self.rectmode;self:Render()end)
    self:Button(self.body,"操作："..(self.remove_mode and "删除" or "添加"),-60,174,function()self.remove_mode=not self.remove_mode;self:Render()end)
    self:Button(self.body,"清空草稿",125,174,function()self.draft={};self.draft_dirty=true;self:Render()end)
    self:Button(self.body,"确认蓝图",350,174,function()self.send({cmd="blueprint",cells=self.draft,revision=self.draft_revision})end)
    local center=self.snapshot.center
    local cx,_,cz=TheWorld.Map:GetTileCenterPoint(center.x,0,center.z)
    self.grid={cx=cx,cz=cz,size=26,left=-169,bottom=-185,n=13}
    local chosen={}
    for _,cell in ipairs(self.draft) do chosen[U.CellKey(cell.x,cell.z)]=true end
    for row=0,12 do
        for col=0,12 do
            local x,z=cx+(col-6)*4,cz+(row-6)*4
            local outside=U.DistanceSq({x=x,z=z},center)>self.snapshot.settings.radius^2
            local selected=chosen[U.CellKey(x,z)]
            local square=self.body:AddChild(Image("images/global.xml","square.tex"))
            square:SetSize(24,24);square:SetPosition(-156+col*26,-172+row*26)
            if outside then square:SetTint(0.12,0.12,0.12,1)
            elseif selected then square:SetTint(0.35,0.72,0.4,0.8)
            else square:SetTint(0.42,0.4,0.3,0.6) end
        end
    end
    self:Label(self.body,"绿：草稿区域\n灰：范围外\n按住左键拖选矩形\n单击可增删一个地格\n确认前不消耗资源",-350,-30,19,230,220)
    self:Label(self.body,"地格数："..#self.draft.."\n"..describe(self.snapshot.blueprint.warnings or {}),340,10,18,270,180)
    self:Button(self.body,"重载已保存蓝图",330,-70,function()
        self.draft=U.Copy(self.snapshot.blueprint.cells or {})
        self.draft_revision=self.snapshot.revision
        self.draft_dirty=false
        self:Render()
    end,18)
    self:Button(self.body,"世界中预览",330,-115,function()self:ShowRange(self.draft)end)
    self:Button(self.body,self.snapshot.blueprint.visible and "隐藏蓝图" or "显示蓝图",330,-160,function()
        local visible=not self.snapshot.blueprint.visible
        self.send({cmd="visibility",visible=visible});if visible then self:ShowRange(self.draft) else Visuals.Clear(self.markers) end
    end)
    self:Button(self.body,"重新计算布局",330,-205,function()self.send({cmd="recalculate"})end)
end
function Panel:Preview()
    self.send({cmd="preview",season=self.season,data=self.preset,detail_page=self.detail_page or 1})
end
function Panel:RenderPresets()
    for i,season in ipairs(C.SEASONS) do self:Button(self.body,(self.season==season and "● " or "")..seasons[season].."季",-400+(i-1)*120,170,function()
        self.season=season;self.preset=U.Copy(self.snapshot.presets[season] or {mode="auto"});self:Render();self:Preview()
    end) end
    self:Button(self.body,modes[self.preset.mode] or modes.auto,-250,115,function()
        local seq={auto="crop",crop="ratio",ratio="pause",pause="auto",fixed="auto"};self.preset.mode=seq[self.preset.mode] or "auto"
        self.preset.crop=self.preset.crop or (self.snapshot.crop_options[1] or {}).id
        self.preset.ratio=self.preset.ratio or {}
        self:Render();self:Preview()
    end)
    self:Button(self.body,"保存本季预设",20,115,function()self.send({cmd="preset",season=self.season,data=self.preset})end)
    self:Label(self.body,"允许保存非最优方案；风险见预测。",-225,75,18)
    local options=self.snapshot.crop_options or {}
    for index=(self.crop_page-1)*6+1,math.min(#options,self.crop_page*6) do
        local crop=options[index];local y=25-((index-1)%6)*38
        local count=(self.preset.ratio or {})[crop.id] or 0
        self:Button(self.body,(self.preset.crop==crop.id and "● " or "")..self:CropName(crop.id),-340,y,function()
            self.preset.crop=crop.id;self.preset.mode="crop";self:Render();self:Preview()
        end,19)
        self:Button(self.body,"-",-200,y,function()
            self.preset.mode="ratio";self.preset.ratio=self.preset.ratio or {};self.preset.ratio[crop.id]=count>1 and count-1 or nil;self:Render();self:Preview()
        end)
        self:Label(self.body,count,-150,y,20)
        self:Button(self.body,"+",-100,y,function()
            self.preset.mode="ratio";self.preset.ratio=self.preset.ratio or {};self.preset.ratio[crop.id]=math.min(64,count+1);self:Render();self:Preview()
        end)
    end
    self:Button(self.body,"更多作物",-280,-227,function()self.crop_page=self.crop_page%math.max(1,math.ceil(#options/6))+1;self:Render()end)
    self.forecast_label=self:Label(self.body,describe(self.forecast and {status=self.forecast.status,summary=self.forecast.summary,reasons=self.forecast.reasons} or {reasons={"修改设置后自动模拟；选择完美搭配可固定方案。"}}),260,10,18,460,310)
    self:Button(self.body,"展开预测明细",260,-180,function()self.page="forecast";self.textpage=1;self:Render()end,19)
    local d=self.forecast or {}
    self:Button(self.body,"上一组地格",135,-225,function()self.detail_page=math.max(1,(d.detail_page or 1)-1);self:Preview()end,17)
    self:Button(self.body,"下一组地格",370,-225,function()self.detail_page=math.min(d.detail_pages or 1,(d.detail_page or 1)+1);self:Preview()end,17)
end
function Panel:RenderRecommendations()
    local data=self.recommendations or {items={},page=1,total=0}
    self:Label(self.body,(data.reference and "原版营养平衡参考（需补齐资源）" or "当前可执行的完美搭配").." · "..tostring(data.total or 0).." 项"..(data.complete==false and "（搜索继续）" or ""),0,175,22)
    if #(data.items or {})==0 then
        self:Label(self.body,"暂无可直接执行的完美方案。\n"..describe(data.reasons or self.snapshot.plan.reasons or {}).."\n请检查种子、锄头、水壶和肥料；稳定生产可使用指定作物。",0,10,21,860,235)
    end
    for i,item in ipairs(data.items or {}) do
        local counts=item.counts or item.ratio or item.crops or {}
        self:Button(self.body,describe(counts),-250,130-(i-1)*39,function()
            self.preset={mode="fixed",ratio=U.Copy(counts),candidate_id=item.id};self.page="presets";self.forecast=item;self:Render();self:Preview()
        end,18)
        self:Button(self.body,"查看预测",330,130-(i-1)*39,function()self.forecast=item;self.page="forecast";self.textpage=1;self:Render()end,18)
    end
    self:Button(self.body,"上一页",-190,-232,function()self.send({cmd="recommendations",page=math.max(1,(data.page or 1)-1)})end)
    self:Label(self.body,tostring(data.page or 1),0,-232,18)
    self:Button(self.body,"下一页",190,-232,function()self.send({cmd="recommendations",page=(data.page or 1)+1})end)
end
local zone_states={ok="正常",editing="编辑中",paused="已暂停",review="待确认方案",unsafe="密度无法排布",empty="未设置方案"}
function Panel:RenderZones()
    local lines={"每片相连的农田是一个田块，各有独立方案。在世界中点击田块上方的浮动标签编辑；",
        "未单独设置的田块使用“管理”页的默认比例模板。打开本面板会让整组机器人暂停。",""}
    for _,z in ipairs(self.snapshot.zones or {}) do
        local crops={}
        for _,t in ipairs(z.tg or {}) do crops[#crops+1]=self:CropName(t.c).." "..tostring(t.h or 0).."/"..tostring(t.n or 0) end
        lines[#lines+1]="田块 #"..tostring(z.id):sub(2).." · "..tostring(z.n).." 格 × "..tostring(z.d).." 孔 · "..(z.m=="exact" and "精确数量" or "比例填满")
            ..(z.cf and "" or "（默认模板）").." · 可用 "..tostring(z.use).."/名义 "..tostring(z.nom).." · 已种 "..tostring(z.pl)
            ..((z.wh or 0)>0 and " · 暂缓 "..z.wh or "")..((z.miss or 0)>0 and " · 缺种 "..z.miss or "").." · "..(zone_states[z.st] or tostring(z.st))
        lines[#lines+1]="    "..(#crops>0 and table.concat(crops,"  ") or "无种植目标")
    end
    if #(self.snapshot.zones or {})==0 then lines[#lines+1]="工作范围内还没有农田田块（机器人不会自动耕地）。" end
    self:TextPage(table.concat(lines,"\n"))
end
function Panel:Render()
    self.body:KillAllChildren();self.forecast_label=nil
    if self.page=="status" then self:RenderStatus()
    elseif self.page=="zones" then self:RenderZones()
    elseif self.page=="blueprint" then self:RenderBlueprint()
    elseif self.page=="presets" then self:RenderPresets()
    elseif self.page=="recommendations" then self:RenderRecommendations()
    elseif self.page=="forecast" then self:TextPage(details(self.forecast or {}))
    elseif self.page=="help" then self:TextPage("1. 把机器人放在空地或农田附近；仓库放在工作范围附近会自动绑定。\n2. 每片上下左右相连的农田是一个田块（只斜角相接或隔着空地就是两个田块）。田块上方有浮动标签：点击打开该田块的种植方案，可选“比例填满”或“精确数量”，以及每格孔数。\n3. 管理页是默认比例模板：未单独设置的田块按这个比例填满自己的容量。机器人不会自动耕地：请自己用耕地机开垦。工作范围内地上的耕地机会被机器人捡起，送进仓库作物/回收区。\n4. 工具格依次是园艺锄、铲子、锤子、斧头、镐子。锄头打孔，铲子清理杂物。耕地机不能放进工具格。\n5. 种子放机器人工作库存或仓库种子区；有多少种多少，不足的部分等补齐后继续种。\n6. 水壶放水壶格；附近有水源会自动补水。成熟作物自动收获，收获后按方案补种。\n7. 打开面板或机器人库存时整个组暂停；关闭后自动恢复。\n8. 农业计划与资源页会显示等待原因。")
    elseif self.page=="plan" then self:TextPage("第 "..tostring((self.snapshot.cycles or 0)+1).." 天 · "..name(self.snapshot.season).."季\n"..details(self.snapshot.plan))
    elseif self.page=="resources" then self:TextPage("仓库："..(self.snapshot.warehouse and "已绑定" or "附近未找到").."\n"..details(self.snapshot.farm_stats or {}).."\n"..details(self.snapshot.resources)) end
end
function Panel:Receive(data)
    if data.locked==false then self:Close();return end
    if data.inventory_open then self:Close();return end
    local blueprint_changed=false
    if data.snapshot then
        blueprint_changed=not self.draft_dirty and self.snapshot.revision~=data.snapshot.revision
        self.snapshot=data.snapshot
        if not self.draft_dirty then
            self.draft=U.Copy(self.snapshot.blueprint.cells or {})
            self.draft_revision=self.snapshot.revision
        end
    end
    if data.draft then
        self.draft=U.Copy(data.draft)
        self.draft_revision=self.snapshot.revision
        self.draft_dirty=data.draft_confirmed~=true
    end
    if data.forecast then self.forecast=data.forecast end
    if data.recommendations then self.recommendations=data.recommendations end
    if data.error then self.notice:SetString(data.error) else self.notice:SetString("农场已同步 · "..self.snapshot.group_id) end
    if self.page~="blueprint" or data.draft or data.error or blueprint_changed then self:Render() end
end
function Panel:ShowRange(draft)
    Visuals.Clear(self.markers);self.markers=Visuals.Show(self.snapshot,draft,8)
end
function Panel:GridPoint(x,y)
    if self.page~="blueprint" or not self.grid then return nil end
    local p=self.root:GetWorldPosition();local scale=self.root:GetScale().x
    local lx,ly=(x-p.x)/scale,(y-p.y)/scale
    local col=math.floor((lx-self.grid.left)/self.grid.size)
    local row=math.floor((ly-self.grid.bottom)/self.grid.size)
    if col<0 or col>12 or row<0 or row>12 then return nil end
    return {x=self.grid.cx+(col-6)*4,z=self.grid.cz+(row-6)*4}
end
function Panel:OnMouseButton(button,down,x,y)
    if button==MOUSEBUTTON_LEFT and self.page=="blueprint" then
        local p=self:GridPoint(x,y)
        if down and p then self.drag_start=p;return true end
        if not down and self.drag_start then
            local a,b=self.drag_start,p or self.drag_start;self.drag_start=nil
            if not self.rectmode then a=b end
            local map={};for _,cell in ipairs(self.draft) do map[U.CellKey(cell.x,cell.z)]=cell end
            for tx=math.min(a.x,b.x),math.max(a.x,b.x),4 do for tz=math.min(a.z,b.z),math.max(a.z,b.z),4 do
                if U.DistanceSq({x=tx,z=tz},self.snapshot.center)<=self.snapshot.settings.radius^2 then
                    local key=U.CellKey(tx,tz)
                    if self.remove_mode or (not self.rectmode and map[key]) then map[key]=nil else map[key]={x=tx,z=tz} end
                end
            end end
            self.draft={};for _,key in ipairs(U.Keys(map)) do self.draft[#self.draft+1]=map[key] end
            self.draft_dirty=true
            self:Render();return true
        end
    end
    if Panel._base.OnMouseButton then return Panel._base.OnMouseButton(self,button,down,x,y) end
    return false
end
function Panel:OnControl(control,down)
    if Panel._base.OnControl(self,control,down) then return true end
    if not down and control==CONTROL_CANCEL then self:Close();return true end
end
function Panel:OnUpdate(dt)
    if self.closed then return end
    if not U.Valid(self.robot) then self:Close();return end
    self.elapsed=self.elapsed+dt
    if self.elapsed>=5 then self.elapsed=0;self.send({cmd="ping"}) end
end
function Panel:Close()
    if self.closed then return end
    self.closed=true;self.send({cmd="close"});Visuals.Clear(self.markers)
    if ThePlayer and ThePlayer.HUD and ThePlayer.HUD._agri_panel==self then ThePlayer.HUD._agri_panel=nil end
    TheFrontEnd:PopScreen(self)
end
return Panel
